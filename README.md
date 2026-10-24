# Tubie

**A YouTube client for jailbroken iOS 5–10.** The YouTube that shipped with iOS 6 stopped working years ago and the
website no longer loads in its Safari; Tubie brings the content back in the look of the system itself. A second
build of the same sources runs on **64-bit devices with iOS 14–17** (iPhone X and newer: rootless jailbreaks and
TrollStore), with the same iOS 6 look.

![Tubie](https://github.com/samcejko/youtube-ios6/releases) <!-- screenshots live on the Releases page -->

## Features

- Videos with quality and speed choice (0.5×–2×, remembered; hold a finger on the picture for 2×; iOS 6 can change
  the speed of an MP4 only, so there another speed plays the 360p MP4), resume where you left off, background sound,
  keep-screen-on. Where YouTube
  still offers an HLS stream the player switches between renditions up to 1080p (the iPad 2 decodes 1080p30);
  the configured resolver can also supply adaptive H.264/AAC tracks - see "Quality and speed" below
- Shorts: a vertical player (swipe for the next one) in 720p, the shorts of the channels you follow
- Live streams, adaptive up to 720p60
- Channels (videos, shorts, live, playlists), playlists with continuous play, related videos
- Search with suggestions and filters, recent searches
- Comments and replies
- Links in descriptions, comments and on channel pages can be tapped: YouTube links open in Tubie, links to Twitch,
  Kick and TikTok in the sister apps (Twitcher, Kicker, TikTak) when installed, the rest in Safari or (iOS 6) Surfari
- Subscriptions, watch history and "watch later" - kept on the device, no Google account needed
- Optional Google account (signed in with a code at google.com/device, as a TV does): the account's subscriptions,
  likes and playlists through the YouTube Data API - see "Account" below
- SponsorBlock (skips sponsor segments and more; categories configurable), captions (also auto-generated),
  Return YouTube Dislike counts
- Studio channel dashboard with real 7/28/90-day reports, daily views and top videos
- Light and dark theme in the iOS 6 style, English and Czech
- Own TLS 1.2 stack (Mbed TLS) and HTTP client: YouTube's servers only accept ciphers iOS 6 never had

Hardware tested on an iPad 2 with iOS 6.1.3 and an iPhone X with iOS 16.7.16. The ARMv7 build targets iOS 5.0–10.x; iOS 5 and iOS 7–10 have not yet been tested on physical hardware.

iOS 5 uses the bundled PSTCollectionView grid and a pull-to-refresh fallback. Earlier table-cell reuse, image stretching and rotation APIs keep the same layout and classic iOS 6 artwork.

## How it works

Browsing uses YouTube's InnerTube API. Playback first requests native streams, then tries the configured resolver when YouTube does not provide a usable source. The default resolver is `https://ytdlp.samcejko.eu/yt`; it receives video IDs, not your Google account token. You can change or disable it in Settings.

The local media proxy provides modern TLS and converts H.264/AAC adaptive MP4 fragments into streams the iOS 6 player can decode. Rich resolver metadata can provide complete tracks even after a native bot-check response. Playback still depends on YouTube allowing the server to access that video; account sign-in alone does not guarantee that every playback check will pass.

### Quality and speed

The player offers compatible H.264 qualities up to the device's decoder limits. Auto selects up to 720p; 1080p30 is available on compatible hardware. Native HLS and live streams are also supported. Without a working resolver, fallback availability depends on the formats YouTube supplies.

On iOS 6, changing HLS speed requires a progressive MP4 fallback, when available; it can reload the stream and reduce quality. Modern devices change playback speed directly.

### Account and Studio

The built-in sign-in uses a device code/QR code. A custom Google TV client can be configured in Account settings. Tokens and custom client credentials stay in the device keychain. Existing sign-ins are retained across updates.

Library → Studio shows read-only channel information and Analytics for 7, 28 or 90 days, daily views and top videos. Top videos open their own Analytics dashboard. More reports includes countries, devices, operating systems, traffic sources, content types and playback locations. The daily graph switches between views, watch minutes and net subscribers; tap a bar for exact values. Period comparison uses matching available days rather than comparing incomplete recent data with a full earlier period. Detailed reports and comparisons can be exported to CSV locally. These additions use the existing sign-in and need no new server or Google Cloud configuration. It uses actual Google API responses. Channel data requires YouTube Data API v3; reports require YouTube Analytics access. These can succeed or fail independently. A missing permission or disabled API is displayed rather than replaced with invented statistics.

The limited-input device flow supports YouTube scopes but does not grant the dedicated Analytics scope to every custom client. Studio therefore depends on the permissions of your existing sign-in; a custom TV client alone does not guarantee Analytics access. No uploads, edits or account changes are made by Studio.

Subscriptions, history and watch-later remain available locally without signing in.

## Installing on the device

The easy way: add the repository `http://repo.samcejko.eu/` in Cydia (Sources → Edit → Add), Sileo, Zebra or Installer
and install Tubie from there; updates then come through the package manager. The app is free; if it is useful to you, you can support the development
at [ko-fi.com/samcejko](https://ko-fi.com/samcejko). By hand:

1. Cydia: **AppSync Unified** (repo `https://cydia.akemi.ai/`) and **IPA Installer Console** (BigBoss),
   plus OpenSSH for the helper scripts.
2. Download the `.ipa` or `.deb` of the latest [release](https://github.com/samcejko/youtube-ios6/releases)
   (both carry the same build; the checksums are in the release notes).
3. Copy the `.ipa` to the device and run `ipainstaller -f Tubie-<version>.ipa`, or use iFunBox / 3uTools.
   The `.deb` works too (`dpkg -i`, then `su mobile -c uicache`) and installs into `/Applications`; do not keep
   both installed at once.

On iOS 14–17 (64-bit): with a rootless jailbreak add the same repository in Sileo or Zebra, or install the
`iphoneos-arm64` `.deb` with `dpkg -i` (it goes into `/var/jb/Applications`); without a jailbreak open
`Tubie-<version>-arm64.ipa` in [TrollStore](https://github.com/opa334/TrollStore). The same app, the same iOS 6 look.

## Building (GitHub Actions)

No Mac needed. Every push runs `.github/workflows/build.yml` on Ubuntu with Theos and Mbed TLS, twice from the
same sources:

- `ios5-armv7`: the iOS 9.3 SDK, deployment target 5.0 → `Tubie-<version>.ipa` and the `iphoneos-arm` `.deb`;
- `ios14-arm64`: `make package THEOS_PACKAGE_SCHEME=rootless`, the iOS 16.5 SDK, deployment target 14.0 →
  `Tubie-<version>-arm64.ipa` (TrollStore) and the `iphoneos-arm64` `.deb` (rootless, `/var/jb`).

The differences live in `src/Util/TBModern.m` (safe areas, the iOS 6 look of the bars on iOS 7 and newer,
full-screen modals) and in `tools/modern_bundle.py` (the arm64 bundle's Info.plist and launch screen).

Helper scripts (Windows PowerShell, see `tools/`): `gh-push.ps1` pushes the working tree through the GitHub API,
`gh-build.ps1` waits for the build, fetches both packages and installs them on the iPad (`-Install`) or the arm64 `.deb`
on the iPhone (`-InstallIPhone`), `gh-release.ps1` publishes a release, `ipad.ps1` and `iphone.ps1` hold the SSH
helpers, `check-strings.ps1` lists untranslated texts.

URL scheme (other apps, or `uiopen` over SSH): `tubie:watch/<id>`, `tubie:short/<id>`, `tubie:channel/<id or @handle>`,
`tubie:playlist/<id>`, `tubie:search?q=<text>`, `tubie:open?url=<youtube link>`.

Debugging over SSH: with a file named `debug` in the app's Documents folder (`Enable-TubieDebug` in `tools/ipad.ps1`),
`uiopen tubie:snapshot` draws the app's windows and `tubie:screen` grabs the real screen (video included) into the
app's `tmp/screen.png` (`Get-IPadScreen`), `tubie:press?n=0` presses a button of the alert or sheet on screen,
`tubie:press?title=<text>` a button, segment, switch row or list row with that text (URL-encoded), `tubie:tab?n=1`
switches tabs, `tubie:back` pops the navigation stack, `tubie:scroll?y=600` (or `y=end`) scrolls the list on screen,
`tubie:seek?t=120` moves the open video, `tubie:link?url=<percent-encoded address>` does what a tap on that link in a
description would (YouTube addresses open inside, others reach the chooser or Safari), `tubie:stats` logs the memory
in use, what the proxy served by content type and the player's state (tracks, buffered ranges), and `tubie:proxylog`
makes the proxy log every request of the player. `/var/log/syslog` carries the app's log lines (`[Tubie]`, `Get-TubieLog`).

## Project layout

- `src/Net` - TLS socket, HTTP/1.1 client, connection pool, image loader, the local media proxy and its
  MP4-to-MPEG-TS converter
- `src/YouTube` - the InnerTube client and parsers, playback sources, the local library (subscriptions, history,
  watch later, RSS feeds), SponsorBlock / Return YouTube Dislike / captions
- `src/UI` - the screens; `TBTheme` draws the iOS 6 artwork in code
- `vendor` - the Mbed TLS configuration and glue (the library itself is fetched at build time)
- `tools` - build, install and release helpers, the icon

## Privacy

Tubie sends YouTube only what a visitor without an account sends: the requests for the pages and videos you open.
Subscriptions, history and "watch later" never leave the device. SponsorBlock receives the ids of the videos you
watch (for its segments), Return YouTube Dislike as well; both can be turned off in Settings.

## License

MIT - see `LICENSE`. Third-party components and services: `THIRD-PARTY-NOTICES.md`.
