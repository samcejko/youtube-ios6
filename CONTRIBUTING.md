# Contributing

Pull requests are welcome: bug fixes, new features, translations, support for more devices.

## Building without a Mac

1. Fork the repository and enable GitHub Actions in your fork (Actions tab).
2. Push to any branch. The workflow builds the app and attaches `Tubie-<version>.ipa` and a `.deb`
   to the run as the `Tubie-packages` artifact.
3. Install it on a jailbroken iOS 6 device (see the README) and try your change.

Opening a pull request runs the same build here, so it is visible whether the change compiles.
`tools/check-gql.ps1` runs every GraphQL query of the app against the live API; run it after touching `TBGQL.m`.

## Ground rules

- **iOS 6.0 is the target.** Do not use APIs introduced after iOS 6 without a runtime check; for the
  files in `src/` such a call is a compile error (see the pragma in `src/TBCommon.h`). No Swift,
  no `NSURLSession`, no storyboards or xibs.
- Objective-C with ARC, UI built in code with frames and autoresizing masks, like the existing screens.
- Network requests go through `TBHTTP` / `TBHTTPRequest` / `TBTLSSocket`; the player gets its media through
  `TBMediaProxy`. The system networking stack cannot negotiate TLS with today's servers on iOS 6.
- User-visible strings go through `L(@"English text")`; add the Czech translation to
  `Resources/cs.lproj/Localizable.strings` (other languages are welcome as new `.lproj` folders).
- Never commit keys or tokens. `tools/local.json` is ignored for that reason.
- Keep a change focused, and add a line to `CHANGELOG.md` when it is visible to users.

## In the pull request

Say what you changed and how you tested it: device, iOS version, or "not tested on a device" if you
could only build it. Only an iPad 2 on iOS 6.1.3 is available to the maintainer, so reports from
iPhones and other iOS 6 devices are especially useful.

## License and credit

The project is MIT licensed. By opening a pull request you agree that your contribution is licensed
under the same terms. Forks and reuse are fine as long as the copyright notice in `LICENSE` stays in
place; a link back to this repository is appreciated.
