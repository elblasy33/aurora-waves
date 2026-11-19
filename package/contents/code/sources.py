#!/usr/bin/env python3
"""Station discovery and logo helpers for the Egypt Radio plasmoid.

  sources.py search '<json>'   {"q","country","tag","limit","offset"} -> [station...]
  sources.py probe <url>       -> {"name","subtitle","logo","homepage"}  (logo = local file:// or "")
  sources.py logo <url>        -> {"logo": "file://..."}  download/copy an image into the logo store
  sources.py sitelogo <url>    -> {"logo": ...}  find the best icon of a web page and store it

All output is a single JSON line. Network failures produce {"error": "..."}.
"""
import hashlib
import html.parser
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request

UA = "EgyptRadioPlasmoid/1.0"
API = "https://all.api.radio-browser.info/json"
DATA = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "egypt-radio")
LOGOS = os.path.join(DATA, "logos")
MAX_IMG = 5 * 1024 * 1024
TIMEOUT = 12


def out(obj):
    print(json.dumps(obj, ensure_ascii=False))


def http_get(url, headers=None, limit=MAX_IMG, timeout=TIMEOUT):
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read(limit + 1), r.headers, r.geturl()


def api(path, params):
    url = API + path + "?" + urllib.parse.urlencode(params)
    body, _, _ = http_get(url, limit=8 * 1024 * 1024)
    return json.loads(body.decode("utf-8", "replace"))


# ------------------------------------------------------------------ search
def clean_station(s):
    tags = [t.strip() for t in (s.get("tags") or "").split(",") if t.strip()]
    return {
        "uuid": s.get("stationuuid", ""),
        "name": (s.get("name") or "").strip(),
        "url": s.get("url_resolved") or s.get("url") or "",
        "favicon": s.get("favicon") or "",
        "homepage": s.get("homepage") or "",
        "country": s.get("country") or "",
        "countrycode": s.get("countrycode") or "",
        "tags": tags[:4],
        "codec": s.get("codec") or "",
        "bitrate": s.get("bitrate") or 0,
        "votes": s.get("votes") or 0,
    }


# Stations in the directory are mostly named in Latin letters ("OM Kalthom", "Fairuz"),
# so an Arabic query is expanded to its common spellings (and vice versa).
ALIASES = {
    "ام كلثوم": ["kalthom", "kalthoum", "kulthum", "kolthoum", "koulthoum", "kolthom", "kalsoum"],
    "فيروز": ["fairuz", "fairouz", "fayrouz", "fayruz", "feiruz", "fyroz"],
    "عبد الحليم": ["halim", "abdel halim", "abdelhalim", "hafez"],
    "عبدالحليم": ["halim", "abdel halim", "abdelhalim", "hafez"],
    "عمرو دياب": ["amr diab", "diab"],
    "عبد الوهاب": ["abdel wahab", "abdelwahab", "wahab", "wahhab"],
    "وردة": ["warda"],
    "نجاة": ["najat", "nagat"],
    "شادية": ["shadia", "shadya"],
    "صباح": ["sabah"],
    "محمد منير": ["mounir", "mohamed mounir"],
    "منير": ["mounir"],
    "كاظم": ["kazem", "kadim", "kathem"],
    "ماجدة الرومي": ["majida", "magida"],
    "وديع الصافي": ["wadih", "wadie"],
    "راغب علامة": ["ragheb"],
    "نانسي": ["nancy ajram", "nancy"],
    "اصالة": ["assala", "asala"],
    "تامر حسني": ["tamer hosny", "tamer"],
    "محمد فؤاد": ["fouad"],
    "مشاري": ["mishary", "alafasy", "afasy"],
    "العفاسي": ["alafasy", "afasy", "mishary"],
    "عبد الباسط": ["abdulbasit", "abdel basset", "abdul basit"],
    "المنشاوي": ["minshawi", "menshawy"],
    "الحصري": ["hussary", "husary", "hosary"],
    "قران": ["quran", "koran", "coran"],
    "القران": ["quran", "koran", "coran"],
    "اغاني": ["aghani", "arabic songs"],
    "طرب": ["tarab"],
    "اخبار": ["news", "akhbar"],
    "موسيقى": ["music", "mousiqa"],
    "رياضة": ["sport"],
    "نجوم": ["nogoum", "nojoum"],
    "مكس": ["mix"],
    "راديو مصر": ["radio masr"],
    "الشرق الاوسط": ["middle east", "sharq"],
    "صوت العرب": ["sawt al arab", "voice of arabs"],
}
_LATIN_TO_AR = {}
for _ar, _lat in ALIASES.items():
    for _l in _lat:
        _LATIN_TO_AR.setdefault(_l, _ar)


def norm_ar(s):
    s = re.sub("[ً-ْـ]", "", s)          # tashkeel + tatweel
    s = re.sub("[أإآٱ]", "ا", s).replace("ة", "ه").replace("ى", "ي")
    s = re.sub(r"^(اذاعه|راديو)\s+", "", s.strip())
    return re.sub(r"\s+", " ", s)


def query_variants(q):
    q = q.strip()
    if not q:
        return []
    out = [q]
    n = norm_ar(q)
    keys = {norm_ar(k): v for k, v in ALIASES.items()}
    for k, v in keys.items():
        if k and (k in n or n in k and len(n) >= 3):
            out += v
    low = q.lower()
    for lat, ar in _LATIN_TO_AR.items():
        if lat in low or (len(low) >= 4 and low in lat):
            out.append(ar)
    if n != q:
        out.append(n)
    seen, res = set(), []
    for v in out:
        if v.lower() not in seen:
            seen.add(v.lower())
            res.append(v)
    return res[:8]


def search(params):
    base = {"hidebroken": "true", "order": "votes", "reverse": "true"}
    limit = int(params.get("limit") or 60)
    offset = int(params.get("offset") or 0)
    country = params.get("country") or ""
    tag = params.get("tag") or ""
    variants = query_variants(params.get("q") or "")

    if not variants:
        # browsing: the country / tag filters apply as chosen
        q = dict(base, limit=limit, offset=offset)
        if country:
            q["countrycode"] = country
        if tag:
            q["tag"] = tag
        res = [clean_station(s) for s in api("/stations/search", q)]
        return [s for s in res if s["url"].startswith(("http://", "https://"))]

    # searching by name: every spelling, by name and by tag, in all countries;
    # the chosen country is ranked first instead of hiding everything else
    from concurrent.futures import ThreadPoolExecutor
    reqs = []
    for v in variants:
        reqs.append(dict(base, name=v, limit=100, **({"tag": tag} if tag else {})))
        reqs.append(dict(base, tag=v.lower(), limit=40))
    with ThreadPoolExecutor(max_workers=8) as ex:
        batches = list(ex.map(lambda r: _safe_api(r), reqs))
    seen, merged = set(), []
    for batch in batches:
        for s in batch:
            c = clean_station(s)
            key = c["uuid"] or c["url"]
            if key in seen or not c["url"].startswith(("http://", "https://")):
                continue
            seen.add(key)
            merged.append(c)
    merged.sort(key=lambda c: (c["countrycode"] != country if country else False, -c["votes"]))
    return merged[offset:offset + limit]


def _safe_api(params):
    try:
        return api("/stations/search", params)
    except Exception:
        return []


# ------------------------------------------------------------------ logos
def sniff(data):
    head = data[:16]
    if head.startswith(b"\x89PNG"):
        return "png"
    if head.startswith(b"\xff\xd8"):
        return "jpg"
    if head[:6] in (b"GIF87a", b"GIF89a"):
        return "gif"
    if head[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    if head[:4] == b"\x00\x00\x01\x00":
        return "ico"
    text = data[:512].lstrip().lower()
    if text.startswith(b"<svg") or (text.startswith(b"<?xml") and b"<svg" in data[:2048].lower()):
        return "svg"
    return None


def store_image(data, key):
    kind = sniff(data)
    if not kind or len(data) > MAX_IMG:
        return None
    os.makedirs(LOGOS, exist_ok=True)
    name = hashlib.sha1(key.encode()).hexdigest()[:16]
    path = os.path.join(LOGOS, name + "." + kind)
    with open(path, "wb") as f:
        f.write(data)
    if kind == "ico" and shutil.which("magick"):
        # keep the biggest frame as png (favicons often bundle 16/32/48px)
        png = os.path.join(LOGOS, name + ".png")
        try:
            subprocess.run(["magick", path + "[-1]", png], timeout=15, check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            os.unlink(path)
            path = png
        except (subprocess.SubprocessError, OSError):
            pass
    return "file://" + path


def fetch_logo(url):
    if not url:
        return None
    if url.startswith("file://") or url.startswith("/"):
        path = urllib.parse.unquote(url[7:]) if url.startswith("file://") else url
        if os.path.dirname(os.path.abspath(path)) == LOGOS:
            return "file://" + path          # already stored
        with open(path, "rb") as f:
            data = f.read(MAX_IMG + 1)
        return store_image(data, "local:" + path + str(os.path.getmtime(path)))
    if not url.startswith(("http://", "https://")):
        return None
    data, _, _ = http_get(url)
    return store_image(data, url)


class IconFinder(html.parser.HTMLParser):
    """Collect candidate icons from a page's <head>, best first."""

    def __init__(self):
        super().__init__()
        self.found = []          # (score, href)

    def handle_starttag(self, tag, attrs):
        a = {k.lower(): (v or "") for k, v in attrs}
        if tag == "link":
            rel = a.get("rel", "").lower()
            href = a.get("href")
            if not href:
                return
            sizes = a.get("sizes", "")
            m = re.match(r"(\d+)x", sizes)
            px = int(m.group(1)) if m else 0
            if "apple-touch-icon" in rel:
                self.found.append((300 + px, href))
            elif "icon" in rel:
                self.found.append((100 + px + (80 if href.endswith(".svg") else 0), href))
        elif tag == "meta":
            prop = (a.get("property") or a.get("name") or "").lower()
            if prop in ("og:image", "twitter:image") and a.get("content"):
                self.found.append((250, a["content"]))


def site_logo(page):
    if not page or not page.startswith(("http://", "https://")):
        return None
    body, _, final = http_get(page, limit=600_000)
    finder = IconFinder()
    try:
        finder.feed(body.decode("utf-8", "replace"))
    except Exception:
        pass
    cands = [urllib.parse.urljoin(final, h) for _, h in sorted(finder.found, reverse=True)]
    cands.append(urllib.parse.urljoin(final, "/favicon.ico"))
    for c in cands:
        try:
            logo = fetch_logo(c)
            if logo:
                return logo
        except Exception:
            continue
    return None


# ------------------------------------------------------------------ probe
VIDEO_SITES = ("dailymotion.com", "dai.ly", "youtube.com", "youtu.be", "twitch.tv",
               "facebook.com", "soundcloud.com", "vimeo.com", "mixcloud.com")


def probe(url):
    info = {"name": "", "subtitle": "", "logo": "", "homepage": ""}
    host = urllib.parse.urlparse(url).netloc.lower()

    # 1) video/audio sites: ask yt-dlp for title + thumbnail
    if any(host == h or host.endswith("." + h) for h in VIDEO_SITES) and shutil.which("yt-dlp"):
        try:
            r = subprocess.run(["yt-dlp", "-J", "--no-warnings", "--skip-download", "--no-playlist", url],
                               capture_output=True, text=True, timeout=45)
            j = json.loads(r.stdout or "{}")
            # live streams get a timestamp appended to their title
            info["name"] = re.sub(r"\s+\d{4}-\d{2}-\d{2}\s+\d{1,2}:\d{2}(:\d{2})?$", "",
                                  (j.get("title") or "").strip())
            info["subtitle"] = (j.get("uploader") or j.get("channel") or "").strip()
            thumb = j.get("thumbnail") or ""
            if thumb:
                info["logo"] = fetch_logo(thumb) or ""
            return info
        except (subprocess.SubprocessError, ValueError, OSError):
            pass

    # 2) the Radio Browser directory knows many streams
    try:
        hits = api("/stations/byurl", {"url": url})
        if hits:
            s = clean_station(max(hits, key=lambda h: h.get("votes") or 0))
            info.update(name=s["name"], homepage=s["homepage"],
                        subtitle=" · ".join(filter(None, [s["country"], ", ".join(s["tags"][:2])])))
            if s["favicon"]:
                try:
                    info["logo"] = fetch_logo(s["favicon"]) or ""
                except Exception:
                    pass
    except Exception:
        pass

    # 3) ICY headers of the stream itself
    if not info["name"] or not info["homepage"]:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Icy-MetaData": "1"})
            with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
                h = r.headers
                info["name"] = info["name"] or (h.get("icy-name") or "").strip()
                info["subtitle"] = info["subtitle"] or (h.get("icy-description") or h.get("icy-genre") or "").strip()
                info["homepage"] = info["homepage"] or (h.get("icy-url") or "").strip()
        except Exception:
            pass

    # 4) icon of the station web site
    if not info["logo"]:
        page = info["homepage"] or ("%s://%s/" % (urllib.parse.urlparse(url).scheme, host) if host else "")
        try:
            info["logo"] = site_logo(page) or ""
        except Exception:
            pass
    if info["name"].lower() in ("unspecified name", "no name", "stream"):
        info["name"] = ""
    return info


# ------------------------------------------------------------------ health check
HOME = os.path.expanduser("~")
SEARCH_ROOTS = [os.path.join(HOME, d) for d in ("Music", "موسيقى", "Downloads", "التنزيلات", "Desktop",
                                                 "Documents", "Videos", "Audio", "Podcasts")]
SEARCH_ROOTS += [os.path.join(b, os.environ.get("USER", "")) for b in ("/media", "/run/media")] + ["/mnt", HOME]


def local_path(url):
    return urllib.parse.unquote(url[7:]) if url.startswith("file://") else url


def find_moved(path, want_dir):
    """Look for a file/folder with the same name somewhere likely; best match by shared parent names."""
    name = os.path.basename(path.rstrip("/"))
    if not name:
        return None
    old_parts = set(p for p in path.split("/") if p)
    best, best_score, seen = None, -1, set()
    for root in SEARCH_ROOTS:
        if not os.path.isdir(root):
            continue
        base_depth = root.rstrip("/").count("/")
        for cur, dirs, files in os.walk(root):
            if cur in seen:
                dirs[:] = []
                continue
            seen.add(cur)
            depth = cur.count("/") - base_depth
            dirs[:] = [d for d in dirs if not d.startswith(".") and d not in ("node_modules", "__pycache__")]
            if depth >= 6:
                dirs[:] = []
            pool = dirs if want_dir else files
            if name in pool:
                cand = os.path.join(cur, name)
                score = len(old_parts & set(p for p in cand.split("/") if p))
                if score > best_score:
                    best, best_score = cand, score
        if best:
            break
    return best


AUDIO_EXT = (".mp3", ".m4a", ".aac", ".ogg", ".oga", ".opus", ".flac", ".wav", ".wma", ".mka", ".mp4", ".webm")


def resolve_media(url):
    """Direct media URL for pages handled by yt-dlp (Dailymotion, YouTube...), else the url itself."""
    host = urllib.parse.urlparse(url).netloc.lower()
    if any(host == h or host.endswith("." + h) for h in VIDEO_SITES) and shutil.which("yt-dlp"):
        r = subprocess.run(["yt-dlp", "-q", "--no-warnings", "-g", "-f", "bestaudio/best", url],
                           capture_output=True, text=True, timeout=60)
        lines = [l for l in r.stdout.splitlines() if l.startswith("http")]
        if r.returncode != 0 or not lines:
            raise LookupError("resolve")
        return lines[0]
    return url


def audio_probe(url, seconds=6):
    """Really listen: decode a few seconds and measure the level.

    Returns (code, mean_db): ok | silent | auth | notfound | unreachable | noaudio | timeout | resolve
    """
    try:
        media = resolve_media(url)
    except LookupError:
        return "resolve", None
    except subprocess.TimeoutExpired:
        return "timeout", None
    local = media.startswith("file://") or media.startswith("/")
    # ffmpeg's own User-Agent on purpose: some hosts (zeno.fm) reject browser-like ones
    cmd = ["ffmpeg", "-nostdin", "-hide_banner", "-v", "info"]
    if not local:
        cmd += ["-rw_timeout", "12000000"]
    cmd += ["-i", local_path(media) if local else media, "-t", str(seconds), "-vn",
            "-af", "volumedetect", "-f", "null", "-"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=seconds + 25)
    except subprocess.TimeoutExpired:
        return "timeout", None
    err = r.stderr
    if re.search(r"\b(401|403)\b|Unauthorized|Forbidden|authorization failed", err, re.I) and r.returncode != 0:
        return "auth", None
    if re.search(r"\b404\b|Not Found|No such file", err, re.I):
        return "notfound", None
    if "does not contain any stream" in err or "matches no streams" in err or "Output file does not contain" in err:
        return "noaudio", None
    # ffmpeg reports volumedetect once per filter graph; the first one is an empty setup pass
    samples = [int(x) for x in re.findall(r"n_samples:\s*(\d+)", err)]
    if not samples:
        return ("unreachable" if r.returncode != 0 else "noaudio"), None
    if max(samples) == 0:
        return "noaudio", None
    mv = re.findall(r"mean_volume:\s*(-?[\d.]+|-inf) dB", err)
    mean = float(mv[-1]) if mv and mv[-1] != "-inf" else -200.0
    if mean <= -70:
        return "silent", mean
    return "ok", mean


def same_station(a, b):
    na, nb = norm_ar(a).lower(), norm_ar(b).lower()
    return bool(na) and bool(nb) and (na == nb or na in nb or nb in na)


def find_working_alternative(st):
    """A different URL for the same station from the directory, verified to carry audio."""
    try:
        cands = search({"q": st.get("name", ""), "limit": 15})
    except Exception:
        return None
    tried = 0
    for c in cands:
        if c["url"] == st.get("url") or not same_station(st.get("name", ""), c["name"]):
            continue
        tried += 1
        if audio_probe(c["url"], seconds=4)[0] == "ok":
            return c
        if tried >= 3:
            break
    return None


def check_local(st, issues):
    url, kind = st.get("url", ""), st.get("kind", "file")
    p = local_path(url)
    if not os.path.exists(p):
        moved = find_moved(p, kind == "folder")
        issues.append({"type": "path", "code": "missing", "detail": p,
                       "fix": {"url": "file://" + urllib.parse.quote(moved)} if moved else None,
                       "fixCode": "found_at" if moved else "pick_manually", "fixDetail": moved or ""})
        return
    if kind == "folder":
        n = 0
        for _, _, files in os.walk(p):
            n += sum(1 for f in files if f.lower().endswith(AUDIO_EXT))
            if n:
                break
        if not n:
            issues.append({"type": "path", "code": "empty_folder", "detail": p, "fix": None,
                           "fixCode": "pick_manually", "fixDetail": ""})
        return
    if kind == "playlist":
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "radioctl", os.path.join(os.path.dirname(os.path.abspath(__file__)), "radioctl.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        try:
            entries = mod.parse_playlist(p)
        except OSError:
            entries = []
        if not entries:
            issues.append({"type": "audio", "code": "empty_playlist", "detail": p, "fix": None,
                           "fixCode": "pick_manually", "fixDetail": ""})
            return
        code, _ = audio_probe(entries[0]["url"], seconds=3)
        if code != "ok":
            issues.append({"type": "audio", "code": code, "detail": entries[0]["url"], "fix": None,
                           "fixCode": "pick_manually", "fixDetail": ""})
        return
    code, _ = audio_probe("file://" + p, seconds=2)
    if code != "ok":
        issues.append({"type": "audio", "code": code, "detail": p, "fix": None,
                       "fixCode": "pick_manually", "fixDetail": ""})


def check_station(st):
    """Issues for one station, each with a verified fix when one exists."""
    issues = []
    url, kind = st.get("url", ""), st.get("kind", "stream")

    if kind in ("file", "folder", "playlist"):
        check_local(st, issues)
    elif url.startswith(("http://", "https://")):
        code, mean = audio_probe(url)
        if code != "ok":
            alt = find_working_alternative(st)
            issues.append({"type": "audio", "code": code, "detail": url,
                           "fix": {"url": alt["url"]} if alt else None,
                           "fixCode": "alt_url" if alt else "no_alt",
                           "fixDetail": (alt["name"] + " — " + alt["url"]) if alt else ""})

    logo = st.get("logo", "")
    if logo.startswith("file://") and not os.path.exists(local_path(logo)):
        fix = None
        if url.startswith("http"):
            try:
                pr = probe(url)
                if pr.get("logo"):
                    fix = {"logo": pr["logo"]}
            except Exception:
                pass
        if fix is None:
            moved = find_moved(local_path(logo), False)
            stored = fetch_logo("file://" + moved) if moved else None
            fix = {"logo": stored} if stored else None
        issues.append({"type": "logo", "code": "missing", "detail": local_path(logo),
                       "fix": fix or {"logo": ""}, "fixCode": "logo_found" if fix else "logo_glyph", "fixDetail": ""})
    elif logo.startswith(("http://", "https://")):
        # remote logo: keep a local copy so it works offline and in media controllers
        try:
            stored = fetch_logo(logo)
        except Exception:
            stored = None
        issues.append({"type": "logo", "code": "remote" if stored else "broken", "detail": logo,
                       "fix": {"logo": stored or ""}, "fixCode": "logo_local" if stored else "logo_glyph",
                       "fixDetail": ""})
    return issues


def check(stations):
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=6) as ex:
        results = list(ex.map(lambda s: (s, check_station(s)), stations))
    return [{"id": s.get("id"), "name": s.get("name", ""), "issues": iss} for s, iss in results]


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    cmd, arg = argv[1], argv[2]
    try:
        if cmd == "search":
            out(search(json.loads(arg)))
        elif cmd == "probe":
            out(probe(arg))
        elif cmd == "logo":
            out({"logo": fetch_logo(arg) or ""})
        elif cmd == "check":
            out(check(json.loads(arg)))
        elif cmd == "sitelogo":
            out({"logo": site_logo(arg) or ""})
        else:
            print(__doc__)
            return 1
    except Exception as e:
        out({"error": str(e)})
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
