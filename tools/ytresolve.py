#!/usr/bin/env python3
"""ytresolve - a tiny YouTube resolver for Tubie, meant to run on your own computer (not the Pi, not tikie).

Tubie on iOS 6 can only fetch the first ~60 s of YouTube's adaptive files without a PO token, so long videos fall
back to the 360p progressive MP4. This helper lets yt-dlp - which keeps up with YouTube - hand the app a fresh,
fully playable stream instead: the best progressive MP4 (<=720p, H.264+AAC) to play straight away, plus the best
adaptive H.264 video and AAC audio for a later 1080p remux in the app.

Run it on a computer on the same network as the iPad:
    pip install -U yt-dlp
    python tools/ytresolve.py              # listens on 0.0.0.0:8740
Then in Tubie point the resolver at  http://<this-computer-LAN-IP>:8740  (see the Tubie settings / debug command).
The phone only asks this service for the stream URL; the video bytes still come straight from YouTube's CDN through
Tubie's own proxy, so this service is only needed at the moment a video starts.

Endpoints (JSON):
    GET /health
    GET /resolve?id=<videoId|watch url>
Set YTRESOLVE_KEY to require ?k=<key> on every call if you expose it beyond your LAN.
"""
import json
import os
import re
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    import yt_dlp
except ImportError:
    sys.exit("ytresolve: yt-dlp is not installed (pip install -U yt-dlp)")

KEY = os.environ.get("YTRESOLVE_KEY", "")
PORT = int(os.environ.get("YTRESOLVE_PORT", "8740"))
# A current iOS YouTube app user-agent: the "ios" player client hands back direct, un-throttled URLs.
UA = "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3 like Mac OS X)"

_LOCK = threading.Lock()


class TTLCache:
    def __init__(self):
        self._d = {}
        self._lock = threading.Lock()

    def get(self, key):
        with self._lock:
            item = self._d.get(key)
            if not item:
                return None
            if item[0] < time.time():
                self._d.pop(key, None)
                return None
            return item[1]

    def put(self, key, value, ttl):
        with self._lock:
            self._d[key] = (time.time() + ttl, value)


CACHE = TTLCache()


def video_id(s):
    s = (s or "").strip()
    m = re.search(r"(?:v=|/shorts/|/embed/|youtu\.be/|/v/|/live/)([A-Za-z0-9_-]{11})", s)
    if m:
        return m.group(1)
    return s if re.fullmatch(r"[A-Za-z0-9_-]{11}", s) else None


def _ydl():
    # Default player clients return the full H.264 DASH ladder (itags 133-137 ...) with direct URLs; forcing
    # ios/web cut it down to the 360p progressive only. The permissive format selector keeps extract_info from
    # failing with "no requested format" (we read info["formats"] ourselves; there is no ffmpeg to merge a pick).
    return yt_dlp.YoutubeDL({
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "noplaylist": True,
        "format": "bv*+ba/b/bv*/ba",
        "ignore_no_formats_error": True,
    })


def _pick(fmts, want):
    """want: 'prog' (video+audio mp4 <=720), 'video' (avc1 video-only <=1080), 'audio' (m4a audio-only)."""
    out = []
    for f in fmts:
        if not f.get("url"):
            continue
        has_v = f.get("vcodec") not in (None, "none")
        has_a = f.get("acodec") not in (None, "none")
        vc = f.get("vcodec") or ""
        h = f.get("height") or 0
        if want == "prog":
            if not (has_v and has_a and f.get("ext") == "mp4" and vc.startswith("avc") and (h == 0 or h <= 720)):
                continue
        elif want == "video":
            if not (has_v and not has_a and vc.startswith("avc") and (h == 0 or h <= 1080)):
                continue
        elif want == "audio":
            ac = f.get("acodec") or ""
            if not (has_a and not has_v and (ac.startswith("mp4a") or f.get("ext") == "m4a")):
                continue
        out.append(f)
    out.sort(key=lambda f: (f.get("abr") or f.get("tbr") or 0) if want == "audio"
             else ((f.get("height") or 0), (f.get("tbr") or 0)))
    return out[-1] if out else None


def _headers(info, f):
    h = {"User-Agent": UA}
    if isinstance(info.get("http_headers"), dict):
        h.update(info["http_headers"])
    if isinstance(f.get("http_headers"), dict):
        h.update(f["http_headers"])
    return h


def resolve(ref):
    vid = video_id(ref)
    if not vid:
        raise ValueError("no youtube video id")
    ckey = "yt:%s" % vid
    cached = CACHE.get(ckey)
    if cached is not None:
        return cached
    url = "https://www.youtube.com/watch?v=%s" % vid
    with _LOCK, _ydl() as ydl:
        info = ydl.extract_info(url, download=False)
    fmts = info.get("formats") or []
    # itag -> fresh direct URL for every format served straight over https (the DASH ladder 133-137 etc. and audio
    # 139/140), skipping HLS. The app keeps the sidx byte ranges it already has per itag and swaps in these URLs.
    formats = {}
    audio_pick = {}   # base itag -> (score, url): for dubbed videos keep only the original/default track
    for f in fmts:
        u = f.get("url")
        if not u or (f.get("protocol") or "") not in ("https", "http"):
            continue
        fid = str(f.get("format_id") or "")
        base = fid.split("-")[0]   # multi-language audio comes as "140-0".."140-19"
        if not base.isdigit():
            continue
        is_audio = f.get("acodec") not in (None, "none") and f.get("vcodec") in (None, "none")
        if is_audio and "-" in fid:
            score = f.get("language_preference") or -1
            note = (f.get("format_note") or "").lower()
            if "default" in note or "original" in note:
                score += 1000
            if base not in audio_pick or score > audio_pick[base][0]:
                audio_pick[base] = (score, u)
        else:
            formats[base] = u
    for base, (score, u) in audio_pick.items():
        formats.setdefault(base, u)
    prog = _pick(fmts, "prog")
    out = {
        "id": vid,
        "title": info.get("title") or "",
        "duration": info.get("duration") or 0,
        "isLive": bool(info.get("is_live")),
        "formats": formats,
    }
    if prog:
        out["playUrl"] = prog.get("url")
        out["playHeight"] = prog.get("height") or 0
        out["playItag"] = str(prog.get("format_id") or "")
    CACHE.put(ckey, out, 3600)   # googlevideo URLs last ~6 h; refresh well before that
    return out


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "ytresolve/1.0"

    def _json(self, obj, status=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _ok_key(self, q):
        return not KEY or q.get("k", [""])[0] == KEY or self.headers.get("X-Ytresolve-Key", "") == KEY

    def log_message(self, fmt, *args):
        sys.stderr.write("ytresolve %s - %s\n" % (self.address_string(), fmt % args))

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        q = urllib.parse.parse_qs(parsed.query)
        if path in ("/health", "/"):
            return self._json({"ok": True, "ytdlp": getattr(yt_dlp.version, "__version__", "?")})
        if not self._ok_key(q):
            return self._json({"error": "unauthorized"}, 401)
        try:
            if path == "/resolve":
                return self._json(resolve(q.get("id", [""])[0] or q.get("url", [""])[0]))
        except ValueError as e:
            return self._json({"error": str(e)}, 400)
        except Exception as e:
            sys.stderr.write("ytresolve error on %s: %s\n" % (path, e))
            return self._json({"error": "upstream failed", "detail": str(e)[:200]}, 502)
        return self._json({"error": "not found"}, 404)


def main():
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    sys.stderr.write("ytresolve listening on :%d (key %s)\n" % (PORT, "set" if KEY else "off"))
    srv.serve_forever()


if __name__ == "__main__":
    main()
