# Tubie

**A YouTube client for jailbroken iOS 6.** The YouTube that shipped with iOS 6 stopped working years ago and the
website no longer loads in its Safari; Tubie brings the content back in the look of the system itself.

![Tubie](https://github.com/samcejko/youtube-ios6/releases) <!-- screenshots live on the Releases page -->

## Features

- Videos with quality and speed choice, resume where you left off, background sound, keep-screen-on. Where YouTube
  still offers an HLS stream the player switches between renditions up to 1080p (the iPad 2 decodes 1080p30);
  everything else plays as the 360p MP4 - see "Quality" below
- Shorts: a vertical player (swipe for the next one) in 720p, the shorts of the channels you follow
- Live streams, adaptive up to 720p60
- Channels (videos, shorts, live, playlists), playlists with continuous play, related videos
- Search with suggestions and filters, recent searches
- Comments and replies
- Subscriptions, watch history and "watch later" - kept on the device, no Google account needed
- Optional Google account (signed in with a code at google.com/device, as a TV does): the account's subscriptions,
  likes and playlists through the YouTube Data API - see "Account" below
- SponsorBlock (skips sponsor segments and more; categories configurable), captions (also auto-generated),
  Return YouTube Dislike counts
- Light and dark theme in the iOS 6 style, English and Czech
- Own TLS 1.2 stack (Mbed TLS) and HTTP client: YouTube's servers only accept ciphers iOS 6 never had

Tested on an iPad 2 (iPad2,2) with iOS 6.1.3. The iPhone layout is implemented but has not been tried on a real iPhone yet.

## How it works

YouTube's InnerTube API is used the way YouTube's own apps use it, without an account: the web client for browsing
and search, the iOS client for the streams of videos, the Android client for live streams and the plain MP4. The
media player of iOS 6 receives everything through a small local HTTP proxy, because it cannot speak modern TLS
itself. There is no login: Google closed its device login to third parties, so subscriptions live on the device and
are followed through the channels' RSS feeds.

### Quality

YouTube keeps every video as separate "adaptive" MP4 files per quality (DASH), a format the 2012 player does not
know, and since 2025 it hands them to clients without a Google account for roughly the first minute of a video only
(the rest needs a "PO token" that only Google's own apps can produce). Tubie therefore plays:

- the adaptive **HLS** stream when YouTube offers one (H.264 video plus a separate AAC sound track; rare for new
  uploads) - renditions up to 1080p, chosen automatically or by hand,
- **shorts and clips up to a minute** through the proxy's own converter, which turns the adaptive MP4 fragments into
  MPEG-TS and packed AAC on the fly - 720p (1080p is there too),
- **longer videos as the 360p MP4** that YouTube still serves in full,
- **live streams** as the Android client's HLS.

The converter (`src/Net/TBRemux.m`) would serve every video in full HD the moment the first-minute limit is lifted or
a PO token can be supplied; nothing else in the app would change.

### Account (optional)

Google's sign-in page does not run on the iOS 6 engine, so Tubie signs in the way a TV does: an OAuth client of the
"TVs and Limited Input devices" kind and the **YouTube Data API v3**. Settings → Account shows a code, you confirm it
at google.com/device on any other device, and the tokens stay in the device's keychain. With the account:
subscriptions (synced both ways), likes and dislikes, liked videos and your own playlists. Not with it: the watch
history, "watch later" and the personalised home page, which the Data API does not expose - those stay local and work
without any account.

Tubie does **not** impersonate YouTube's own app, so it cannot offer one shared, ready-made login: a third-party
YouTube client cannot pass Google's OAuth verification, and embedding Google's first-party credentials would be
impersonating their app. Instead **you use your own Google client** (free, about five minutes, one time):

1. [Google Cloud Console](https://console.cloud.google.com/) → create a project (or pick one).
2. **APIs & Services → Library** → enable **YouTube Data API v3**.
3. **APIs & Services → OAuth consent screen** → User type **External** → fill the name/e-mail → **Save**. Leave the
   publishing status at **Testing** and add your own Google account under **Test users**. (Testing is all a personal
   app needs; "production" is what would require Google's verification.)
4. **APIs & Services → Credentials → Create credentials → OAuth client ID** → application type **TVs and Limited Input
   devices**. Copy the **client ID** and **client secret**.
5. In Tubie: Settings → Account → paste the **client ID** and the **client secret**, then **Sign in with Google**.

The client secret lives only in your device's keychain, never in this repository or the build. (A build may carry a
default client baked in from a CI secret, but only that project's own test users can sign in with it - everyone else
uses their own as above.) The API has a daily quota of 10 000 units per project (plenty for one person); a test-mode
refresh token lasts 7 days, after which Tubie asks you to sign in again.

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
`tubie:press?title=<text>` a button, segment, switch row or list row with that text (URL-encoded), `tubie:tab?n=1`
switches tabs, `tubie:back` pops the navigation stack, `tubie:scroll?y=600` (or `y=end`) scrolls the list on screen,
`tubie:seek?t=120` moves the open video, `tubie:stats` logs the memory in use, what the proxy served by content type
and the player's state (tracks, buffered ranges), and `tubie:proxylog` makes the proxy log every request of the
player. `/var/log/syslog` carries the app's log lines (`[Tubie]`, `Get-TubieLog`).

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
