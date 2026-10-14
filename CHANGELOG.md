# Changelog

## 0.4.2 (2026-10-14)

- Playback speed works now. iOS 6's player cannot change the speed of an HLS stream (it silently stayed at 1×, and
  from a pause the video did not start again); on iOS 6 a speed other than 1× now plays the video's 360p MP4, which
  it can speed up, and 1× returns to the full-quality stream at the same spot. iOS 7 and newer change the speed of
  every stream directly.
- A chosen speed no longer falls back to 1× after a pause, after buffering, in the mini player, in the background
  or from the lock screen.
- The speed is remembered for the next videos, and the player shows it as a pill next to the quality (also in full
  screen), so it can be changed without leaving the video. 1.75× was added to 0.5×–2×.
- Hold a finger on the picture to play at 2× while it stays down, as on YouTube; let go and the chosen speed returns
  (on iOS 6 while the MP4 plays, i.e. at a speed other than 1×).
- iOS 7 and newer use the best-quality time stretching for faster or slower speech.
- The iOS 6 package now declares iOS 6.x only; 64-bit devices with iOS 15 and newer use the arm64 package.

## 0.4.1 (2026-10-14)

- Links in video descriptions, comments and replies and on channel pages can be tapped (they show in blue). YouTube
  links - videos, shorts, channels, `@handles`, playlists - open in Tubie itself; links to Twitch, Kick and TikTok
  open in Twitcher, Kicker or TikTak when that sister app is installed.
- Any other link: on iOS 6 a sheet offers Safari or Surfari (when installed); iOS 7 and newer open Safari directly
  and share through the system's share sheet.
- The iOS 6 package now declares iOS 6.0 up to 10.x. 64-bit devices use the arm64 package.

## 0.4.0 (2026-10-14)

- A second build for 64-bit devices with iOS 14–17 (iPhone X and newer), from the same source tree: the `.deb` with
  `iphoneos-arm64` in its name for rootless jailbreaks (palera1n, Dopamine; it installs into `/var/jb`) and
  `Tubie-<version>-arm64.ipa` for TrollStore. Tried on an iPhone X with iOS 16.
- On iOS 7 and newer the app draws the glossy iOS 6 bars, the black glass tab bar, bordered bar buttons and rounded
  grouped tables itself, stays in light mode and opens the players full screen, so it looks the same as on the
  iPad 2. The player's controls, the shorts, the mini player and the grids keep clear of the notch and the home
  indicator.
- The 32-bit build gets the same look on devices with iOS 7–10.

## 0.3.1 (2026-10-14)

- Settings → About has a "Support the development" row that opens the author's Ko-fi page. The app stays free.
- Tubie is in the repository `http://repo.samcejko.eu/` now (Cydia, Sileo, Zebra, Installer): add it as a source to get updates.

## 0.3.0 (2026-10-04)

- Chapters: a video whose description lists timestamps now shows chapter marks on the scrubber, the current chapter's
  name above it, and a "Chapters" row on the watch page that opens the list and jumps to any part.
- Player gestures: double-tap the left or right half of the picture to skip 10 seconds back or forward; drag up and
  down on the left half for screen brightness, on the right half for volume.
- Mini player: a button at the top of the player shrinks the video to a small floating bar, so you can keep browsing
  while it plays on; tap the bar to open the video again, the X to close it. (Not for live streams.)
- Optional stream resolver (experimental): point the app at a yt-dlp helper (on the Pi behind the existing tunnel, or
  `tools/ytresolve.py` on any computer) and the long videos that otherwise fall back to 360p are remuxed at up to
  1080p from fresh, fully-serving stream URLs. Off by default; set the address with the
  `tubie:resolver?url=https://ytdlp.samcejko.eu/yt` debug command (the app appends `/resolve`).

## 0.2.2 (2026-10-03)

- Adaptive videos were stuck at 480p: "Automatic" quality now starts at 720p (iOS 6's player hardly climbs once it
  begins low) and the player drops only if the connection cannot keep up. 1080p stays in the quality menu. (Long
  videos with no adaptive stream are still the 360p MP4 that YouTube serves without a PO token.)

## 0.2.1 (2026-10-03)

- Fixed a crash on the Google sign-in screen (the token polling ran against a freed block).
- The Google **client ID** is now entered in Settings too, so the whole repository can stay public: each person uses
  their own OAuth client (ID + secret from a 5-minute Google Cloud project), nothing shared is baked in. See the
  README; a build may still carry the author's client as a default for its own test users.
- Post comments and replies when signed in (needs the broader `youtube.force-ssl` permission, so sign in again).
- Sharing a video now offers an "Open in..." chooser: copy the link, or open it in Safari or Surfari.

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
