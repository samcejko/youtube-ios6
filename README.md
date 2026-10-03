# Tubie

**A YouTube client for jailbroken iOS 6.** The YouTube that shipped with iOS 6 stopped working years ago and the
website no longer loads in its Safari; Tubie brings the content back in the look of the system itself.

![Tubie](https://github.com/samcejko/youtube-ios6/releases) <!-- screenshots live on the Releases page -->

## Features

- Videos as adaptive HLS up to 1080p (what the device decodes; the iPad 2 does 1080p30), quality and speed choice,
  resume where you left off, background sound, keep-screen-on
- Shorts: a vertical player (swipe for the next one), the shorts of the channels you follow
- Live streams
- Channels (videos, shorts, live, playlists), playlists with continuous play, related videos
- Search with suggestions and filters, recent searches
- Comments and replies
- Subscriptions, watch history and "watch later" - kept on the device, no Google account needed
- SponsorBlock (skips sponsor segments and more; categories configurable), captions (also auto-generated),
  Return YouTube Dislike counts
- Light and dark theme in the iOS 6 style, English and Czech
- Own TLS 1.2 stack (Mbed TLS) and HTTP client: YouTube's servers only accept ciphers iOS 6 never had

Tested on an iPad 2 (iPad2,2) with iOS 6.1.3. The iPhone layout is implemented but has not been tried on a real iPhone yet.

## How it works

YouTube's InnerTube API is used the way YouTube's own apps use it, without an account: the web client for browsing
and search, the iOS client for the streams of videos (HLS with H.264 video and a separate AAC sound track), the
Android client for live streams and the plain MP4 of shorts. The media player of iOS 6 receives everything through a
small local HTTP proxy, because it cannot speak modern TLS itself. There is no login: Google closed its device login
to third parties, so subscriptions live on the device and are followed through the channels' RSS feeds.

## Installing on the device

1. Cydia: **AppSync Unified** (repo `https://cydia.akemi.ai/`) and **IPA Installer Console** (BigBoss),
   plus OpenSSH for the helper scripts.
2. Download the `.ipa` or `.deb` of the latest [release](https://github.com/samcejko/youtube-ios6/releases)
   (both carry the same build; the checksums are in the release notes).
3. Copy the `.ipa` to the device and run `ipainstaller -f Tubie-<version>.ipa`, or use iFunBox / 3uTools.
   The `.deb` works too (`dpkg -i`, then `su mobile -c uicache`) and installs into `/Applications`; do not keep
   both installed at once.

## Building (GitHub Actions)

No Mac needed. Every push runs `.github/workflows/build.yml` on Ubuntu with Theos, the iOS 9.3 SDK
(deployment target 6.0) and Mbed TLS. Artifacts: `Tubie-<version>.ipa` and a `.deb`.

Helper scripts (Windows PowerShell, see `tools/`): `gh-push.ps1` pushes the working tree through the GitHub API,
`gh-build.ps1` waits for the build and installs it on the device over SSH, `gh-release.ps1` publishes a release,
`ipad.ps1` holds the SSH helpers, `check-strings.ps1` lists untranslated texts.

URL scheme (other apps, or `uiopen` over SSH): `tubie:watch/<id>`, `tubie:short/<id>`, `tubie:channel/<id or @handle>`,
`tubie:playlist/<id>`, `tubie:search?q=<text>`, `tubie:open?url=<youtube link>`.

Debugging over SSH: with a file named `debug` in the app's Documents folder (`Enable-TubieDebug` in `tools/ipad.ps1`),
`uiopen tubie:snapshot` draws the app's windows and `tubie:screen` grabs the real screen (video included) into the
app's `tmp/screen.png` (`Get-IPadScreen`), `tubie:press?n=0` presses a button of the alert or sheet on screen,
`tubie:press?title=<text>` a button, segment, switch row or list row with that text, `tubie:tab?n=1` switches tabs,
`tubie:back` pops the navigation stack, `tubie:seek?t=120` moves the open video and `tubie:stats` logs the memory in
use. `/var/log/syslog` carries the app's log lines (`[Tubie]`, `Get-TubieLog`).

## Project layout

- `src/Net` - TLS socket, HTTP/1.1 client, connection pool, image loader, the local media proxy
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
