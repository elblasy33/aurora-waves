#!/usr/bin/env python3
"""Client for radiod.py, used by the Aurora Radio plasmoid.

Usage:
  radioctl.py '<json request>'      e.g. '{"cmd":"status"}'  -> prints JSON reply
  radioctl.py --init                -> creates the art cache dir, prints {"artDir": ...}
  radioctl.py --playlist <path>     -> parses an .m3u/.pls file, prints [{"name","url"}...]
"""
import json
import os
import socket
import subprocess
import sys
import time
from urllib.parse import unquote

HERE = os.path.dirname(os.path.abspath(__file__))
RUN = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
CTL_SOCK = os.path.join(RUN, "aurora-radio.sock")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "aurora-radio")

STARTS_DAEMON = ("play", "toggle", "next", "prev", "sync")


def request(req, timeout=2.0):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    s.connect(CTL_SOCK)
    try:
        s.sendall((json.dumps(req) + "\n").encode())
        data = b""
        while not data.endswith(b"\n"):
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
        return data.decode().strip()
    finally:
        s.close()


def start_daemon():
    subprocess.Popen([sys.executable, "-I", os.path.join(HERE, "radiod.py")],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    for _ in range(50):
        time.sleep(0.1)
        try:
            request({"cmd": "ping"}, timeout=0.5)
            return True
        except OSError:
            pass
    return False


def parse_playlist(path):
    path = unquote(path[7:]) if path.startswith("file://") else path
    base = os.path.dirname(path)
    out, title = [], None
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = [l.strip() for l in f]
    if path.lower().endswith(".pls"):
        entries = {}
        for l in lines:
            if "=" in l:
                k, v = l.split("=", 1)
                kl = k.lower()
                for p in ("file", "title"):
                    if kl.startswith(p) and kl[len(p):].isdigit():
                        entries.setdefault(int(kl[len(p):]), {})[p] = v
        for _, e in sorted(entries.items()):
            if e.get("file"):
                out.append({"name": e.get("title") or e["file"].rsplit("/", 1)[-1], "url": e["file"]})
        return out
    for l in lines:
        if not l:
            continue
        if l.startswith("#EXTINF"):
            title = l.split(",", 1)[1].strip() if "," in l else None
            continue
        if l.startswith("#"):
            continue
        url = l if "://" in l else "file://" + os.path.normpath(os.path.join(base, l))
        out.append({"name": title or url.rstrip("/").rsplit("/", 1)[-1], "url": url})
        title = None
    return out


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    if argv[1] == "--init":
        art = os.path.join(CACHE, "art")
        os.makedirs(art, exist_ok=True)
        print(json.dumps({"artDir": art}))
        return 0
    if argv[1] == "--playlist":
        try:
            print(json.dumps(parse_playlist(argv[2]), ensure_ascii=False))
        except OSError as e:
            print(json.dumps({"error": str(e)}))
        return 0

    req = json.loads(argv[1])
    try:
        print(request(req))
        return 0
    except OSError:
        pass
    if req.get("cmd") not in STARTS_DAEMON:
        print(json.dumps({"daemon": False, "state": "stopped"}))
        return 0
    if not start_daemon():
        print(json.dumps({"daemon": False, "state": "error", "error": "daemon did not start"}))
        return 1
    print(request(req, timeout=4.0))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
