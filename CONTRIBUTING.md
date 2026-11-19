# Contributing to GitPulse

Thanks for helping. Bug reports, docs fixes, and focused pull requests are all welcome. For larger changes, please open an issue first so we can agree on the approach.

## Setup

- macOS 15+
- Full Xcode 16 or later, selected as the active developer directory:

  ```sh
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept
  ```

  Command Line Tools alone are not enough. In SDK 27, SwiftUI's `@State` is a macro whose `SwiftUIMacros` plugin ships only with Xcode, and SwiftPM finds the Swift Testing macros reliably only through Xcode. CI uses Xcode on `macos-26` runners.

```sh
git clone https://github.com/drosam/gitpulse.git
cd gitpulse
swift build
```

## Project layout

| Path | What lives there |
| --- | --- |
| `Sources/GitPulse/GitPulseApp.swift` | `@main` app, scenes, menu bar icon, app delegate |
| `Sources/GitPulseCore/` | Everything else: models, GitHub client, session logic, settings, notifications, views, demo data |
| `Tests/GitPulseCoreTests/` | Swift Testing suites and JSON fixtures |
| `Scripts/build-app.sh` | Builds and ad-hoc signs `GitPulse.app` (used by `make app`/`dev`/`install` and CI) |
| `Scripts/changelog-section.sh` | Extracts a version's release notes from `CHANGELOG.md` |
| `packaging/homebrew/gitpulse.rb` | Reference copy of the Homebrew cask |

## Common tasks

```sh
swift build          # debug build
make test            # swift test
make dev             # build .build/app/GitPulse.app and open it in place
make demo            # same, launched with fictional data (--demo)
make install         # build and copy to /Applications (refused if installed via Homebrew)
make uninstall
```

`swift run` works too, but macOS banners are disabled there because they need a real app bundle.

### Developing with the Homebrew version installed

Use `make dev` / `make demo`, not `make install`: installing over `/Applications/GitPulse.app` would desync the cask, so the Makefile refuses. Quit the installed GitPulse first; both copies share the bundle ID, settings, and Keychain token.

### Tests

Tests use [Swift Testing](https://developer.apple.com/documentation/testing) (`import Testing`). They cover:

- GraphQL decoding and pane rules (fixtures in `Tests/GitPulseCoreTests/Fixtures`)
- session list rules and notification detection, driven through `Session.refresh()` with a stub dashboard source
- the OAuth device flow with a scripted transport
- URL validation, version display, and render-smoke checks of the main views

Never call real GitHub from tests. Inject a `DashboardSource`, `TokenProvider`, or `DeviceFlow` transport instead.

### Demo mode and screenshots

`make demo` (or `open .build/app/GitPulse.app --args --demo`) loads `DemoData` (fictional `acme/*` and `globex/*` repositories). It does no network, Keychain, or notification work and uses a separate preferences domain. Use it for README screenshots (`screencapture -w docs/screenshot.png`) so no private repository names leak.

## Pull requests

- Keep each PR focused on one change.
- Run `swift build` and `swift test` before pushing. CI runs both on every PR.
- Update `README.md` when user-facing behavior changes, and add a line under `## [Unreleased]` in `CHANGELOG.md`.
- Don't add dependencies without discussing them in an issue first.

## Releasing (maintainers)

1. Move the `[Unreleased]` entries in `CHANGELOG.md` into a new `## [X.Y.Z] - YYYY-MM-DD` section and update the compare links.
2. Merge to `main`, then tag and push:

   ```sh
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

3. `.github/workflows/release.yml` runs two jobs:
   - **build** (macOS): runs the tests, builds a universal app stamped with the version, and packages the ZIP, DMG, and `SHA256SUMS.txt`.
   - **publish** (Ubuntu, `release` environment): runs only after you approve the deployment in GitHub Actions. It attests build provenance, creates the GitHub release with the CHANGELOG section as notes, and bumps `Casks/gitpulse.rb` in `drosam/homebrew-tap`.
4. Update locally: `brew update && brew upgrade --cask gitpulse`.

Tags `vX.Y.Z-(alpha|beta|rc)[.N]` are published as prereleases and don't touch the cask. Re-run a failed release with **Re-run failed jobs** in the Actions tab within 7 days; it reuses the built artifact. A full rebuild of a tag whose release already exists stops before the cask bump if its checksums differ from the published `SHA256SUMS.txt`, and a draft release blocks publishing until you publish or delete it. Re-running an older tag never lowers the cask version.

### One-time release setup

- A `release` environment in this repository with you as required reviewer.
- A GitHub App installed on `drosam/homebrew-tap` with **Contents: read and write**. Store its client ID as the `TAP_APP_CLIENT_ID` variable and its private key as the `TAP_APP_PRIVATE_KEY` secret, in the `release` environment or at repository level.
- `Casks/gitpulse.rb` present in the tap. A reference copy is in `packaging/homebrew/gitpulse.rb`.
