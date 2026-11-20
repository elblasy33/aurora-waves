#!/usr/bin/env python3
"""YouTube Music for the Aurora Waves plasmoid (optional feature).

Search and browse go through ytmusicapi; playback goes through mpv + yt-dlp. Both libraries
live in a private folder (~/.local/share/aurora-radio/pylib) so the system Python is never
touched, and yt-dlp there can be kept fresh: YouTube changes often and old copies stop working.

  ytmusic.py status  -                     -> {"ready", "ytmusicapi", "ytdlp", "updatedDays"}
  ytmusic.py setup   -                     -> installs / upgrades both, then status
  ytmusic.py update  -                     -> upgrades yt-dlp only (cheap), then status
  ytmusic.py search  '{"q","filter","country"}'  filter: all | songs | artists | albums
  ytmusic.py artist  <channelId>           -> {name, thumb, songs[], albums[], singles[], playlistUrl}
  ytmusic.py album   <browseId>            -> {title, artist, thumb, year, tracks[], playlistUrl}
  ytmusic.py radio   <videoId>             -> {tracks[]}  "more like this" mix starting at that song
  ytmusic.py home    '{"lang","country"}'  -> {shelves: [{title, items[]}]}  (personal when signed in)
  ytmusic.py playlist <playlistId>         -> {title, thumb, tracks[], playlistUrl}
  ytmusic.py library -                     -> {liked[], playlists[], history[]}       (signed in)
  ytmusic.py like    '{"id","on"}'         -> {ok}                                    (signed in)
  ytmusic.py login   '{"browser"}' | '{"headers"}'  -> {account} | {error}
  ytmusic.py logout  -

Signing in is optional. It reuses the YouTube session of a browser the user is already signed in
to (or request headers they paste), stored only in ~/.local/share/aurora-radio (mode 600).

A track is {"id": videoId, "title", "artist", "album", "duration" (s), "thumb"}.
All output is one JSON line; failures are {"error": "..."}.
"""
import json
import os
import re
import subprocess
import sys
import time

DATA = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "aurora-radio")
PYLIB = os.path.join(DATA, "pylib")
YTDLP_WRAPPER = os.path.join(DATA, "bin", "yt-dlp")
STAMP = os.path.join(DATA, "pylib.updated")
AUTH = os.path.join(DATA, "ytm-auth.json")          # request headers (cookie) of the signed-in account
ACCOUNT = os.path.join(DATA, "ytm-account.json")    # {name, handle, photo, method, browser}
BROWSER_UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
              "Chrome/140.0.0.0 Safari/537.36")
BROWSER_DIRS = {
    "chrome": ["~/.config/google-chrome"],
    "chromium": ["~/.config/chromium", "~/snap/chromium/common/chromium"],
    "brave": ["~/.config/BraveSoftware/Brave-Browser"],
    "edge": ["~/.config/microsoft-edge"],
    "vivaldi": ["~/.config/vivaldi"],
    "opera": ["~/.config/opera"],
    "firefox": ["~/.mozilla/firefox", "~/snap/firefox/common/.mozilla/firefox",
                "~/.var/app/org.mozilla.firefox/.mozilla/firefox"],
}

if os.path.isdir(PYLIB):
    sys.path.insert(0, PYLIB)


def out(obj):
    print(json.dumps(obj, ensure_ascii=False))


# ------------------------------------------------------------------ setup
def versions():
    v = {"ytmusicapi": "", "ytdlp": ""}
    if not os.path.isdir(PYLIB):
        return v
    for name in os.listdir(PYLIB):
        m = re.match(r"(ytmusicapi|yt_dlp)-(.+)\.dist-info$", name)
        if m:
            v["ytmusicapi" if m.group(1) == "ytmusicapi" else "ytdlp"] = m.group(2)
    return v


def write_wrapper():
    """mpv's ytdl hook runs this instead of the (often outdated) system yt-dlp."""
    os.makedirs(os.path.dirname(YTDLP_WRAPPER), exist_ok=True)
    body = '#!/bin/sh\nPYTHONPATH="%s" exec python3 -m yt_dlp "$@"\n' % PYLIB
    try:
        with open(YTDLP_WRAPPER) as f:
            if f.read() == body:
                return
    except OSError:
        pass
    with open(YTDLP_WRAPPER, "w") as f:
        f.write(body)
    os.chmod(YTDLP_WRAPPER, 0o755)


def status():
    v = versions()
    ready = bool(v["ytmusicapi"] and v["ytdlp"])
    if ready:
        write_wrapper()
    try:
        days = (time.time() - os.path.getmtime(STAMP)) / 86400
    except OSError:
        days = -1
    acc = read_json(ACCOUNT) if os.path.exists(AUTH) else None
    return {"ready": ready, "ytmusicapi": v["ytmusicapi"], "ytdlp": v["ytdlp"],
            "updatedDays": round(days, 1), "signedIn": bool(acc), "account": acc or {},
            "browsers": [b for b, dirs in BROWSER_DIRS.items()
                         if any(os.path.isdir(os.path.expanduser(d)) for d in dirs)]}


def read_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def write_private(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False)


def pip_install(pkgs):
    os.makedirs(PYLIB, exist_ok=True)
    r = subprocess.run([sys.executable, "-m", "pip", "install", "--quiet", "--disable-pip-version-check",
                        "--no-warn-script-location", "--upgrade", "--target", PYLIB] + pkgs,
                       capture_output=True, text=True, timeout=600)
    # pip --target leaves the old copy's metadata next to the new one; keep the newest only
    seen = {}
    for name in sorted(os.listdir(PYLIB)):
        m = re.match(r"(.+?)-(\d[^-]*)\.dist-info$", name)
        if m:
            seen.setdefault(m.group(1), []).append(name)
    for olds in seen.values():
        for old in sorted(olds, key=lambda n: [int(x) if x.isdigit() else 0 for x in re.split(r"[.-]", n)])[:-1]:
            subprocess.run(["rm", "-rf", os.path.join(PYLIB, old)])
    if r.returncode != 0 and not all(versions().values()):
        tail = (r.stderr or r.stdout).strip().splitlines()[-3:]
        raise RuntimeError(" ".join(tail) or "pip failed")
    with open(STAMP, "w") as f:
        f.write(time.strftime("%F %T"))


# ------------------------------------------------------------------ helpers
_YT = {}


def yt(country="", lang="en"):
    """A client; signed in when an account is saved. lang only changes shelf titles (home)."""
    key = (country, lang)
    if key not in _YT:
        from ytmusicapi import YTMusic
        auth = None
        if os.path.exists(AUTH):
            refresh_browser_login()
            auth = AUTH
        try:
            _YT[key] = YTMusic(auth=auth, language=lang, location=country or "")
        except Exception:          # unsupported language / location
            _YT[key] = YTMusic(auth=auth)
    return _YT[key]


# ------------------------------------------------------------------ account
def headers_from_browser(browser):
    from yt_dlp.cookies import extract_cookies_from_browser

    class Quiet:
        def debug(self, *a, **k): pass
        def info(self, *a, **k): pass
        def warning(self, *a, **k): pass
        def error(self, *a, **k): pass

    jar = extract_cookies_from_browser(browser, logger=Quiet())
    cookies = {}
    for c in jar:
        if c.domain.lstrip(".").endswith("youtube.com") and c.value:
            cookies[c.name] = c.value
    if not ({"SAPISID", "__Secure-3PAPISID"} & set(cookies)):
        raise LookupError("not-signed-in")
    cookies.setdefault("__Secure-3PAPISID", cookies.get("SAPISID", ""))
    return {
        "cookie": "; ".join("%s=%s" % kv for kv in cookies.items()),
        "x-goog-authuser": "0",
        "authorization": "SAPISIDHASH 0_0",      # marks browser auth; recomputed on every request
        "user-agent": BROWSER_UA,
        "accept": "*/*",
        "content-type": "application/json",
        "origin": "https://music.youtube.com",
        "x-origin": "https://music.youtube.com",
    }


def refresh_browser_login():
    """Browser sessions rotate their cookies; re-read them at most every 12 hours."""
    acc = read_json(ACCOUNT) or {}
    if acc.get("method") != "browser":
        return
    try:
        if time.time() - os.path.getmtime(AUTH) < 12 * 3600:
            return
        write_private(AUTH, headers_from_browser(acc["browser"]))
    except Exception:
        pass                       # keep the old headers; they may still work


def account_info():
    from ytmusicapi import YTMusic
    info = YTMusic(auth=AUTH).get_account_info()
    if not info or not info.get("accountName"):
        raise LookupError("not-signed-in")
    return {"name": info.get("accountName", ""), "handle": info.get("channelHandle") or "",
            "photo": info.get("accountPhotoUrl") or ""}


def login(params):
    if params.get("browser"):
        headers = headers_from_browser(params["browser"])
        method = {"method": "browser", "browser": params["browser"]}
    else:
        from ytmusicapi.setup import setup_browser
        raw = params.get("headers") or ""
        headers = json.loads(setup_browser(filepath=None, headers_raw=raw))
        method = {"method": "headers"}
    write_private(AUTH, headers)
    try:
        acc = dict(account_info(), **method)
    except Exception:
        logout()
        raise LookupError("not-signed-in")
    write_private(ACCOUNT, acc)
    return {"account": acc}


def logout():
    for p in (AUTH, ACCOUNT):
        try:
            os.unlink(p)
        except OSError:
            pass
    return {"ok": True}


def thumb(thumbs, size=400):
    if not thumbs:
        return ""
    url = thumbs[-1].get("url", "")
    # googleusercontent images take their size in the URL; ask for a sharp one
    url = re.sub(r"=w\d+-h\d+[^/]*$", "=w%d-h%d-l90-rj" % (size, size), url)
    if url.startswith("//"):
        url = "https:" + url
    return url


def secs(item):
    if item.get("duration_seconds"):
        return int(item["duration_seconds"])
    d = item.get("duration") or item.get("length") or ""
    if isinstance(d, (int, float)):
        return int(d)
    try:
        parts = [int(p) for p in str(d).split(":")]
    except ValueError:
        return 0
    total = 0
    for p in parts:
        total = total * 60 + p
    return total


def artists(item):
    return ", ".join(a.get("name", "") for a in (item.get("artists") or []) if a.get("name"))


def track(item, album="", fallback_thumb=""):
    vid = item.get("videoId")
    if not vid:
        return None
    alb = item.get("album")
    return {
        "id": vid,
        "title": (item.get("title") or "").strip(),
        "artist": artists(item),
        "album": (alb.get("name") if isinstance(alb, dict) else alb) or album or "",
        "duration": secs(item),
        "thumb": thumb(item.get("thumbnails") or item.get("thumbnail")) or fallback_thumb,
    }


def tracks(items, **kw):
    return [t for t in (track(i, **kw) for i in items or []) if t]


def artist_card(a):
    return {"id": a.get("browseId") or a.get("channelId") or "", "name": a.get("artist") or a.get("title") or "",
            "thumb": thumb(a.get("thumbnails"), 240), "subs": a.get("subscribers") or ""}


def album_card(a):
    return {"id": a.get("browseId") or "", "title": a.get("title") or "", "artist": artists(a),
            "year": str(a.get("year") or ""), "type": a.get("type") or "", "thumb": thumb(a.get("thumbnails"), 300)}


def playlist_url(list_id):
    return "https://music.youtube.com/playlist?list=" + list_id if list_id else ""


# ------------------------------------------------------------------ commands
def search(params):
    q = (params.get("q") or "").strip()
    flt = params.get("filter") or "all"
    if not q:
        return {"songs": [], "artists": [], "albums": []}
    y = yt(params.get("country", ""))
    want = ["songs", "artists", "albums"] if flt == "all" else [flt]
    limit = 20 if flt != "all" else 12

    def one(f):
        try:
            return f, y.search(q, filter=f, limit=limit)
        except Exception:
            return f, []

    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=3) as ex:
        found = dict(ex.map(one, want))
    res = {
        "songs": tracks(found.get("songs")),
        "artists": [c for c in map(artist_card, found.get("artists") or []) if c["id"]],
        "albums": [c for c in map(album_card, found.get("albums") or []) if c["id"]],
    }
    if flt == "all":
        res["songs"] = res["songs"][:10]
        res["artists"] = res["artists"][:8]
        res["albums"] = res["albums"][:10]
    return res


def artist(cid):
    y = yt()
    a = y.get_artist(cid)
    pic = thumb(a.get("thumbnails"), 500)
    songs_sec = a.get("songs") or {}
    songs = tracks(songs_sec.get("results"))
    list_id = songs_sec.get("browseId") or ""
    if list_id:
        try:
            pl = y.get_playlist(list_id, limit=60)
            more = tracks(pl.get("tracks"))
            if len(more) > len(songs):
                songs = more
        except Exception:
            pass
    return {
        "id": cid,
        "name": a.get("name") or "",
        "thumb": pic,
        "subs": a.get("subscribers") or a.get("monthlyListeners") or "",
        "songs": songs,
        "albums": [album_card(x) for x in (a.get("albums") or {}).get("results", [])],
        "singles": [album_card(x) for x in (a.get("singles") or {}).get("results", [])],
        "playlistUrl": playlist_url(list_id[2:] if list_id.startswith("VL") else list_id),
    }


def album(bid):
    a = yt().get_album(bid)
    pic = thumb(a.get("thumbnails"), 500)
    name = a.get("title") or ""
    return {
        "id": bid,
        "title": name,
        "artist": artists(a),
        "year": str(a.get("year") or ""),
        "type": a.get("type") or "",
        "thumb": pic,
        "tracks": tracks(a.get("tracks"), album=name, fallback_thumb=pic),
        "playlistUrl": playlist_url(a.get("audioPlaylistId") or ""),
    }


def card(x):
    """Any home / library item as {kind, id, title, subtitle, thumb} (+ track fields for songs)."""
    bid = x.get("browseId") or ""
    sub = artists(x) or x.get("description") or x.get("subscribers") or ""
    if isinstance(x.get("author"), list):
        sub = sub or ", ".join(a.get("name", "") for a in x["author"])
    if x.get("videoId") and not bid:
        t = track(x)
        return dict(t, kind="song", subtitle=t["artist"]) if t else None
    if bid.startswith("MPRE"):
        return {"kind": "album", "id": bid, "title": x.get("title") or "", "subtitle": sub or str(x.get("year") or ""),
                "thumb": thumb(x.get("thumbnails"), 300)}
    if bid.startswith(("UC", "MPLA")):
        return {"kind": "artist", "id": bid, "title": x.get("title") or x.get("artist") or "", "subtitle": sub,
                "thumb": thumb(x.get("thumbnails"), 240)}
    pid = x.get("playlistId") or (bid[2:] if bid.startswith("VL") else bid)
    if pid:
        return {"kind": "playlist", "id": pid, "title": x.get("title") or "", "subtitle": str(sub),
                "thumb": thumb(x.get("thumbnails"), 300)}
    return None


def home(params):
    y = yt(params.get("country", ""), params.get("lang") or "en")
    shelves = []
    for sh in y.get_home(limit=8):
        items = [c for c in map(card, sh.get("contents") or []) if c]
        if items:
            shelves.append({"title": sh.get("title") or "", "items": items[:16]})
    return {"shelves": shelves}


def playlist(pid):
    pl = yt().get_playlist(pid, limit=150)
    pic = thumb(pl.get("thumbnails"), 500)
    return {
        "id": pid,
        "title": pl.get("title") or "",
        "artist": (pl.get("author") or {}).get("name", "") if isinstance(pl.get("author"), dict) else "",
        "year": str(pl.get("year") or ""),
        "type": str(pl.get("trackCount") or ""),
        "thumb": pic,
        "tracks": tracks(pl.get("tracks"), fallback_thumb=pic),
        "playlistUrl": playlist_url(pid),
    }


def library():
    y = yt()
    from concurrent.futures import ThreadPoolExecutor

    def safe(fn):
        try:
            return fn()
        except Exception:
            return None

    with ThreadPoolExecutor(max_workers=3) as ex:
        liked = ex.submit(safe, lambda: y.get_liked_songs(limit=200))
        pls = ex.submit(safe, lambda: y.get_library_playlists(limit=50))
        hist = ex.submit(safe, y.get_history)
    return {
        "liked": tracks((liked.result() or {}).get("tracks")),
        "playlists": [c for c in map(card, pls.result() or []) if c and c["id"] != "LM"],
        "history": tracks(hist.result())[:60],
    }


def like(params):
    from ytmusicapi.models.content.enums import LikeStatus
    yt().rate_song(params["id"], LikeStatus.LIKE if params.get("on", True) else LikeStatus.INDIFFERENT)
    return {"ok": True}


def radio(vid):
    w = yt().get_watch_playlist(videoId=vid, radio=True, limit=30)
    return {"tracks": tracks(w.get("tracks")),
            "playlistUrl": "https://music.youtube.com/watch?v=%s&list=RDAMVM%s" % (vid, vid)}


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    cmd, arg = argv[1], argv[2]
    try:
        if cmd == "status":
            out(status())
        elif cmd == "setup":
            pip_install(["ytmusicapi", "yt-dlp"])
            out(status())
        elif cmd == "update":
            pip_install(["yt-dlp"])
            out(status())
        elif cmd == "logout":
            out(logout())
        elif cmd in ("search", "artist", "album", "radio", "home", "playlist", "library", "like", "login"):
            if not status()["ready"]:
                out({"error": "not-installed"})
                return 0
            if cmd in ("library", "like") and not os.path.exists(AUTH):
                out({"error": "not-signed-in"})
                return 0
            fn = {"search": lambda: search(json.loads(arg)), "artist": lambda: artist(arg),
                  "album": lambda: album(arg), "radio": lambda: radio(arg),
                  "home": lambda: home(json.loads(arg)), "playlist": lambda: playlist(arg),
                  "library": library, "like": lambda: like(json.loads(arg)),
                  "login": lambda: login(json.loads(arg))}[cmd]
            out(fn())
        else:
            print(__doc__)
            return 1
    except LookupError as e:
        out({"error": str(e) or "not-found"})
    except Exception as e:
        out({"error": str(e) or e.__class__.__name__})
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
