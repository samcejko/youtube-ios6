# Changelog

## 0.2.0 (2026-10-03)

- Google account: sign in with a code at google.com/device (the way a TV does). The account's subscriptions come
  into the app and stay in step (Subscribe buttons act on the account), videos can be liked and disliked, and the
  Library gains "Liked videos" and "My playlists". The watch history and "watch later" remain on the device - the
  YouTube Data API does not offer them. Settings → Account takes your own Google OAuth client ID and secret (a short
  one-time setup, see the README); both stay in the keychain, never in the repository or the build.
- Search showed only shorts, channels and playlists: ordinary videos were dropped by the parser. Fixed; shorts now
  follow the videos in the results (at most six) and carry a "Shorts" badge.
- SponsorBlock skips "non-music" parts of music videos by default as well (the extension's own default); the log
  tells how many segments a video has.

## 0.1.0 (2026-10-03)

First version.

- Videos: YouTube's HLS stream where it exists (renditions up to 1080p, automatic or chosen), otherwise the 360p MP4;
  shorts and clips up to a minute are converted from the adaptive MP4 files to HLS on the device and play in 720p.
  Quality and speed choice, resume positions, background sound, keep-screen-on, autoplay of the next video.
- Shorts tab with a swipe player; the shorts of followed channels. Live streams (adaptive, up to 720p60).
- Home with topic shelves (music, news, sports, live, gaming), "continue watching" and the subscriptions feed.
- Channels (videos, shorts, live, playlists), playlists with continuous play, related videos, comments and replies.
- Search with suggestions, filters (videos, channels, playlists, live) and recent searches.
- Subscriptions (followed through RSS), watch history and "watch later" kept on the device - no Google account.
- SponsorBlock with configurable categories, captions (also auto-generated) in the language of choice, Return YouTube
  Dislike counts.
- Light and dark theme in the iOS 6 style, English and Czech.
- Other apps can open content with the `tubie:` URL scheme (`watch/<id>`, `short/<id>`, `channel/<id or @handle>`,
  `playlist/<id>`, `search?q=`, `open?url=<youtube link>`); `youtube.com` and `youtu.be` links too.

Tested on an iPad 2 with iOS 6.1.3.
