#!/usr/bin/env python3
"""Egypt Radio playback daemon.

Owns one mpv process, keeps playback state (with auto-retry for expiring stream
links), and exposes it on D-Bus as an MPRIS2 player so that media controllers,
visualizers, media keys and the lock screen can see and control it.

The plasmoid talks to it through radioctl.py over a unix socket (one JSON
request per connection, one JSON reply).
"""
import json
import os
import socket
import subprocess
import sys
import time

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

RUN = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
CTL_SOCK = os.path.join(RUN, "egypt-radio.sock")
MPV_SOCK = os.path.join(RUN, "egypt-radiod-mpv.sock")
BUS_NAME = "org.mpris.MediaPlayer2.egyptradio"
OBJ_PATH = "/org/mpris/MediaPlayer2"
IDLE_EXIT_SECS = 180          # daemon leaves after being stopped this long
APP_NAME = "إذاعات مصر"

MPRIS_XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek"><arg direction="in" name="Offset" type="x"/></method>
    <method name="SetPosition">
      <arg direction="in" name="TrackId" type="o"/>
      <arg direction="in" name="Position" type="x"/>
    </method>
    <method name="OpenUri"><arg direction="in" name="Uri" type="s"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""

LOCAL_KINDS = ("file", "folder", "playlist")


def station_kind(st):
    k = st.get("kind")
    if k:
        return k
    url = st.get("url", "")
    if url.startswith("file://") or url.startswith("/"):
        low = url.lower()
        if low.endswith((".m3u", ".m3u8", ".pls")):
            return "playlist"
        path = url[7:] if url.startswith("file://") else url
        return "folder" if os.path.isdir(GLib.uri_unescape_string(path, None) or path) else "file"
    return "stream"


class Mpv:
    """Minimal async mpv JSON-IPC client living on the GLib main loop."""

    OBSERVED = ["idle-active", "core-idle", "paused-for-cache", "pause", "metadata",
                "media-title", "audio-codec-name", "audio-bitrate", "time-pos",
                "duration", "volume", "playlist-pos", "playlist-count", "seekable"]

    def __init__(self, on_change):
        self.on_change = on_change
        self.proc = None
        self.sock = None
        self.buf = b""
        self.queue = []
        self.props = {}
        self.watch = None
        self.req = 0

    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    def start(self, volume):
        if self.alive():
            return
        self.close_socket()
        self.props = {}
        try:
            os.unlink(MPV_SOCK)
        except OSError:
            pass
        self.proc = subprocess.Popen(
            ["mpv", "--idle=yes", "--no-video", "--no-terminal", "--force-window=no",
             "--input-ipc-server=" + MPV_SOCK, "--volume=" + str(volume),
             "--ytdl-format=bestaudio/best", "--cache=yes", "--cache-secs=15",
             "--network-timeout=20", "--audio-client-name=egypt-radio",
             "--title=" + APP_NAME, "--load-scripts=no"],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        GLib.timeout_add(80, self._try_connect, time.time())

    def _try_connect(self, started):
        if not self.alive():
            return False
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(MPV_SOCK)
        except OSError:
            return time.time() - started < 6     # keep trying
        s.setblocking(False)
        self.sock = s
        self.watch = GLib.io_add_watch(s.fileno(), GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, self._on_read)
        for i, name in enumerate(self.OBSERVED, start=1):
            self._send_now({"command": ["observe_property", i, name]})
        pending, self.queue = self.queue, []
        for cmd in pending:
            self._send_now({"command": cmd})
        return False

    def _send_now(self, obj):
        try:
            self.sock.sendall((json.dumps(obj) + "\n").encode())
        except OSError:
            pass

    def command(self, *cmd):
        if self.sock:
            self._send_now({"command": list(cmd)})
        else:
            self.queue.append(list(cmd))

    def _on_read(self, fd, cond):
        try:
            chunk = self.sock.recv(65536) if self.sock else b""
        except BlockingIOError:
            return True
        except OSError:
            chunk = b""
        if not chunk:
            self.close_socket()
            self.on_change()
            return False
        self.buf += chunk
        changed = False
        while b"\n" in self.buf:
            line, self.buf = self.buf.split(b"\n", 1)
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            if msg.get("event") == "property-change":
                self.props[msg.get("name")] = msg.get("data")
                changed = True
        if changed:
            self.on_change()
        return True

    def close_socket(self):
        if self.watch:
            GLib.source_remove(self.watch)
            self.watch = None
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
        self.sock = None
        self.buf = b""

    def quit(self):
        if self.sock:
            self._send_now({"command": ["quit"]})
        self.close_socket()
        if self.proc:
            try:
                self.proc.wait(timeout=1.5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        self.proc = None
        self.queue = []
        self.props = {}


class Daemon:
    def __init__(self):
        self.loop = GLib.MainLoop()
        self.stations = []
        self.current = None           # station dict
        self.want = False
        self.state = "stopped"        # stopped | connecting | playing | paused | error
        self.requested_at = 0.0
        self.retries = 0
        self.volume = 70
        self.mpris_enabled = True
        self.stopped_since = time.time()
        self.track_no = 0
        self.mpv = Mpv(self.on_mpv_change)
        self.bus = None
        self.reg_ids = []
        self.owner_id = 0
        self.last_emitted = {}
        self.app_name = APP_NAME
        self.live_text = "بث مباشر"

    # ------------------------------------------------------------ control
    def find(self, sid):
        for st in self.stations:
            if st.get("id") == sid:
                return st
        return None

    def play(self, sid=None):
        st = self.find(sid) if sid else None
        if st is None:
            st = self.current if self.current else (self.stations[0] if self.stations else None)
        if st is None:
            return
        if self.current is None or self.current.get("id") != st.get("id"):
            self.track_no += 1
        self.current = st
        self.want = True
        self.state = "connecting"
        self.requested_at = time.time()
        kind = station_kind(st)
        self.mpv.start(self.volume)
        local = kind in LOCAL_KINDS
        self.mpv.command("set_property", "shuffle", bool(st.get("shuffle")) and kind != "stream")
        self.mpv.command("set_property", "loop-playlist", "inf" if kind in ("folder", "playlist") else "no")
        self.mpv.command("set_property", "pause", False)
        self.mpv.command("set_property", "volume", self.volume)
        self.mpv.command("loadfile", st.get("url", ""), "replace")
        if not local:
            self.mpv.props.pop("metadata", None)
        self.publish()

    def stop(self):
        self.want = False
        self.state = "stopped"
        self.retries = 0
        self.stopped_since = time.time()
        self.mpv.quit()
        self.publish()

    def is_local(self):
        return self.current is not None and station_kind(self.current) in LOCAL_KINDS

    def pause(self):
        if self.is_local() and self.state in ("playing", "connecting"):
            self.mpv.command("set_property", "pause", True)
            self.state = "paused"
            self.publish()
        elif self.state != "stopped":
            self.stop()

    def resume_or_play(self):
        if self.state == "paused" and self.mpv.alive():
            self.mpv.command("set_property", "pause", False)
            self.state = "playing"
            self.publish()
        elif not self.want:
            self.retries = 0
            self.play(None)

    def toggle(self):
        if self.state in ("playing", "connecting"):
            self.pause()
        else:
            self.resume_or_play()

    def step(self, delta, prefer_track=False):
        # inside a local playlist/folder, media "next" moves between tracks
        if prefer_track and self.is_local() and (self.mpv.props.get("playlist-count") or 0) > 1:
            self.mpv.command("playlist-next" if delta > 0 else "playlist-prev", "force")
            return
        if not self.stations:
            return
        idx = 0
        if self.current:
            for i, st in enumerate(self.stations):
                if st.get("id") == self.current.get("id"):
                    idx = i
                    break
        nxt = self.stations[(idx + delta) % len(self.stations)]
        self.retries = 0
        self.play(nxt.get("id"))

    def set_volume(self, v):
        self.volume = max(0, min(100, int(round(v))))
        if self.mpv.alive():
            self.mpv.command("set_property", "volume", self.volume)
        self.publish()

    # ------------------------------------------------------------ state machine
    def on_mpv_change(self):
        self.evaluate()

    def evaluate(self):
        if not self.want:
            return
        p = self.mpv.props
        elapsed = time.time() - self.requested_at
        if not self.mpv.alive():
            if elapsed > 5:
                self.fail_or_retry()
            return
        if self.state == "paused":
            return
        if p.get("idle-active", True):
            if self.state == "playing" and self.is_local() and station_kind(self.current) == "file":
                self.stop()          # single local file finished
            elif elapsed > 3:
                self.fail_or_retry()
            return
        if p.get("core-idle", True) or p.get("paused-for-cache"):
            if self.state != "playing" or elapsed > 3:
                self._set_state("connecting")
            return
        self.retries = 0
        self._set_state("playing")

    def _set_state(self, s):
        if self.state != s:
            self.state = s
        self.publish()

    def fail_or_retry(self):
        if self.retries < 3:
            self.retries += 1
            self.play(None)
        else:
            self.want = False
            self.state = "error"
            self.stopped_since = time.time()
            self.mpv.quit()
            self.publish()

    def tick(self):
        self.evaluate()
        if not self.want and self.state != "paused" and time.time() - self.stopped_since > IDLE_EXIT_SECS:
            self.loop.quit()
            return False
        return True

    # ------------------------------------------------------------ status
    def titles(self):
        """(title, artist, album) as shown in media controllers."""
        st = self.current or {}
        name = st.get("name", self.app_name)
        p = self.mpv.props
        meta = p.get("metadata") or {}
        lower = {str(k).lower(): v for k, v in meta.items()}
        icy = lower.get("icy-title") or lower.get("streamtitle") or ""
        if self.is_local():
            title = lower.get("title") or p.get("media-title") or name
            artist = lower.get("artist") or name
            return title, artist, lower.get("album") or name
        if icy:
            return icy, name, self.app_name
        return name, st.get("subtitle") or self.live_text, self.app_name

    def status(self):
        p = self.mpv.props
        title, artist, _ = self.titles()
        local = self.is_local()
        return {
            "daemon": True,
            "state": self.state,
            "currentId": self.current.get("id") if self.current else "",
            "title": title if (local or title != (self.current or {}).get("name")) else "",
            "artist": artist,
            "codec": (p.get("audio-codec-name") or "") if self.state == "playing" else "",
            "bitrate": (p.get("audio-bitrate") or 0) if self.state == "playing" else 0,
            "volume": self.volume,
            "pos": p.get("time-pos") or 0,
            "duration": p.get("duration") or 0,
            "local": local,
            "track": (p.get("playlist-pos") or 0) + 1,
            "tracks": p.get("playlist-count") or 0,
            "mpris": self.owner_id != 0 and self.bus is not None,
        }

    # ------------------------------------------------------------ MPRIS
    def mpris_props(self, iface):
        if iface == "org.mpris.MediaPlayer2":
            return {
                "CanQuit": GLib.Variant("b", True),
                "CanRaise": GLib.Variant("b", False),
                "HasTrackList": GLib.Variant("b", False),
                "Identity": GLib.Variant("s", self.app_name),
                "DesktopEntry": GLib.Variant("s", ""),
                "SupportedUriSchemes": GLib.Variant("as", ["http", "https", "file"]),
                "SupportedMimeTypes": GLib.Variant("as", ["audio/mpeg", "audio/aac", "application/x-mpegurl"]),
            }
        title, artist, album = self.titles()
        st = self.current or {}
        md = {
            "mpris:trackid": GLib.Variant("o", "/org/egyptradio/track/%d" % self.track_no),
            "xesam:title": GLib.Variant("s", title),
            "xesam:artist": GLib.Variant("as", [artist]),
            "xesam:album": GLib.Variant("s", album),
        }
        # always send artUrl: an empty value tells clients to drop the previous station's cover
        md["mpris:artUrl"] = GLib.Variant("s", st.get("art") or "")
        dur = self.mpv.props.get("duration")
        if self.is_local() and dur:
            md["mpris:length"] = GLib.Variant("x", int(dur * 1e6))
        if st.get("url", "").startswith("http"):
            md["xesam:url"] = GLib.Variant("s", st["url"])
        status = {"playing": "Playing", "connecting": "Playing", "paused": "Paused"}.get(self.state, "Stopped")
        local = self.is_local()
        return {
            "PlaybackStatus": GLib.Variant("s", status),
            "Rate": GLib.Variant("d", 1.0),
            "MinimumRate": GLib.Variant("d", 1.0),
            "MaximumRate": GLib.Variant("d", 1.0),
            "Metadata": GLib.Variant("a{sv}", md),
            "Volume": GLib.Variant("d", self.volume / 100.0),
            "Position": GLib.Variant("x", int((self.mpv.props.get("time-pos") or 0) * 1e6) if local else 0),
            "CanGoNext": GLib.Variant("b", len(self.stations) > 1 or local),
            "CanGoPrevious": GLib.Variant("b", len(self.stations) > 1 or local),
            "CanPlay": GLib.Variant("b", bool(self.stations)),
            "CanPause": GLib.Variant("b", True),
            "CanSeek": GLib.Variant("b", local and bool(self.mpv.props.get("seekable"))),
            "CanControl": GLib.Variant("b", True),
        }

    def publish(self):
        """Emit PropertiesChanged for whatever changed since last time."""
        if not self.bus or not self.owner_id:
            return
        props = self.mpris_props("org.mpris.MediaPlayer2.Player")
        props.pop("Position", None)    # position is polled, never signalled
        changed = {}
        for k, v in props.items():
            key = v.print_(False)
            if self.last_emitted.get(k) != key:
                self.last_emitted[k] = key
                changed[k] = v
        if changed:
            self.bus.emit_signal(None, OBJ_PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                 GLib.Variant("(sa{sv}as)", ("org.mpris.MediaPlayer2.Player", changed, [])))

    def _method(self, conn, sender, path, iface, method, params, inv):
        if iface == "org.mpris.MediaPlayer2":
            if method == "Quit":
                self.stop()
        else:
            if method == "Play":
                self.resume_or_play()
            elif method == "Pause":
                self.pause()
            elif method == "PlayPause":
                self.toggle()
            elif method == "Stop":
                self.stop()
            elif method == "Next":
                self.step(1, prefer_track=True)
            elif method == "Previous":
                self.step(-1, prefer_track=True)
            elif method == "Seek" and self.is_local():
                self.mpv.command("seek", params.unpack()[0] / 1e6, "relative")
            elif method == "SetPosition" and self.is_local():
                self.mpv.command("seek", params.unpack()[1] / 1e6, "absolute")
            elif method == "OpenUri":
                uri = params.unpack()[0]
                self.stations.append({"id": "uri", "name": uri.rsplit("/", 1)[-1], "url": uri})
                self.play("uri")
        inv.return_value(None)

    def _get_prop(self, conn, sender, path, iface, prop):
        return self.mpris_props(iface).get(prop)

    def _set_prop(self, conn, sender, path, iface, prop, value):
        if prop == "Volume":
            self.set_volume(value.unpack() * 100)
        return True

    def _on_bus(self, conn, name):
        self.bus = conn
        node = Gio.DBusNodeInfo.new_for_xml(MPRIS_XML)
        for iface in node.interfaces:
            self.reg_ids.append(conn.register_object(OBJ_PATH, iface, self._method, self._get_prop, self._set_prop))

    def enable_mpris(self, on):
        if on and not self.owner_id:
            self.owner_id = Gio.bus_own_name(Gio.BusType.SESSION, BUS_NAME, Gio.BusNameOwnerFlags.REPLACE,
                                             self._on_bus, None, None)
        elif not on and self.owner_id:
            for rid in self.reg_ids:
                self.bus.unregister_object(rid)
            self.reg_ids = []
            Gio.bus_unown_name(self.owner_id)
            self.owner_id = 0
            self.bus = None
            self.last_emitted = {}
        self.mpris_enabled = on

    # ------------------------------------------------------------ control socket
    def handle(self, req):
        cmd = req.get("cmd")
        if "stations" in req and isinstance(req["stations"], list):
            self.stations = req["stations"]
            if self.current:
                fresh = self.find(self.current.get("id"))
                if fresh:
                    self.current = fresh
        if "volume" in req and cmd != "volume":
            self.volume = int(req["volume"])
        if req.get("appName"):
            self.app_name = req["appName"]
        if req.get("liveText"):
            self.live_text = req["liveText"]
        if "mpris" in req:
            self.enable_mpris(bool(req["mpris"]))
        if cmd == "play":
            self.retries = 0
            self.play(req.get("id"))
        elif cmd == "stop":
            self.stop()
        elif cmd == "toggle":
            self.toggle()
        elif cmd == "next":
            self.step(1)
        elif cmd == "prev":
            self.step(-1)
        elif cmd == "volume":
            self.set_volume(req.get("v", self.volume))
        elif cmd == "art":
            # cover rendered after playback started (e.g. a preview station)
            for st in self.stations:
                if st.get("id") == req.get("id"):
                    st["art"] = req.get("art", "")
            if self.current and self.current.get("id") == req.get("id"):
                self.current["art"] = req.get("art", "")
                self.track_no += 1          # new trackid makes clients reload the cover
        elif cmd == "quit":
            self.stop()
            GLib.idle_add(self.loop.quit)
        self.publish()
        return self.status()

    def _on_client(self, fd, cond, server):
        try:
            conn, _ = server.accept()
        except OSError:
            return True
        conn.settimeout(1.0)
        try:
            data = b""
            while not data.endswith(b"\n"):
                chunk = conn.recv(65536)
                if not chunk:
                    break
                data += chunk
            reply = self.handle(json.loads(data.decode() or "{}"))
        except Exception as e:  # never let a bad request kill the daemon
            reply = {"daemon": True, "error": str(e)}
        try:
            conn.sendall((json.dumps(reply, ensure_ascii=False) + "\n").encode())
        except OSError:
            pass
        conn.close()
        return True

    def run(self):
        try:
            os.unlink(CTL_SOCK)
        except OSError:
            pass
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(CTL_SOCK)
        os.chmod(CTL_SOCK, 0o600)
        server.listen(8)
        GLib.io_add_watch(server.fileno(), GLib.IO_IN, self._on_client, server)
        GLib.timeout_add(1000, self.tick)
        self.enable_mpris(True)
        try:
            self.loop.run()
        finally:
            self.mpv.quit()
            server.close()
            try:
                os.unlink(CTL_SOCK)
            except OSError:
                pass


if __name__ == "__main__":
    Daemon().run()
    sys.exit(0)
