# AGENTS.md

Guidance for coding agents working in this repository.

## Project

GitPulse is a native macOS SwiftUI menu bar app that tracks GitHub pull requests.

## Commands

- Requires full Xcode selected via `xcode-select` (Command Line Tools 27 lack SwiftUI's `SwiftUIMacros` plugin).
- Build debug: `swift build`
- Test: `swift test` (or `make test`)
- Build app bundle only: `make app` (`Scripts/build-app.sh`, output `.build/app/GitPulse.app`)
- Build and run the app in place (no install): `make dev`
- Same with fictional data: `make demo` (`--demo`)
- Build release/install app: `make install` (refuses when installed via Homebrew cask)
- Uninstall app: `make uninstall`
- Launch installed app: `open -a GitPulse`

## Workflow

- Read code before editing.
- Prefer small, focused changes.
- Preserve existing SwiftUI/AppKit patterns.
- Run `swift build` and `swift test` after code changes when feasible.
- Tests use Swift Testing; never hit real GitHub in tests (inject `DashboardSource`, `TokenProvider`, `DeviceFlow` transport).
- Do not add dependencies without explicit approval.
- Do not commit unless asked.
- Do not kill/relaunch/install unless asked.

## Code notes

- `Sources/GitPulse/GitPulseApp.swift` is the thin `@main` executable; everything else lives in the `GitPulseCore` library (`Sources/GitPulseCore/`). Only symbols the app target uses are `public`.
- Settings live in `Sources/GitPulseCore/AppSettings.swift`, including launch-at-login via `SMAppService.mainApp`.
- Runtime state and notification detection live in `Sources/GitPulseCore/Session.swift`. External effects are injected via `Session.Dependencies` (`.live` in the app).
- GitHub GraphQL fetching lives in `Sources/GitPulseCore/GitHub/GitHubClient.swift`; `GitHubClient.decodeDashboard` is the pure decoding + pane-rules step.
- Main dashboard UI lives in `Sources/GitPulseCore/Views/ContentView.swift` and `Sources/GitPulseCore/Views/PRListView.swift`; the menu bar menu (with version) is `Views/MenuBarMenu.swift`.
- Open URLs only after `SafeURL.isAllowed` (https + github.com).
- Demo mode (`Sources/GitPulseCore/Demo/`) uses fictional data and a separate defaults suite; keep it free of real repository names.
- Version shown in the menu comes from `CFBundleShortVersionString`; release CI stamps it from the git tag, local builds show `dev (<sha>)`.
- Releases: add a `CHANGELOG.md` section, push tag `vX.Y.Z`; `.github/workflows/release.yml` builds on macOS, then a `release`-environment-gated job attests, publishes, and bumps the cask in `drosam/homebrew-tap` via the tap GitHub App token.
- Merged authored/assigned PRs are kept as temporary unread rows in **My pull requests** until opened or dismissed; see `pendingMergedPullRequests` in `Session.swift`.
- Activity notifications include top-level PR comments, submitted reviews, and inline review-thread comments fetched in `GitHubClient.swift`.
- Unread blue dots are backed by `Session.unreadNotifications`; clicking the dot or pressing `V` shows the same summary as the macOS banner, not comment bodies.
- Pull request list order is controlled by `AppSettings.pullRequestSort`; default is created newest-to-oldest, with an updated newest-to-oldest option.
- **Review requested** combines `review-requested:@me`, `reviewed-by:@me`, and `commenter:@me`, excludes PRs already in **My pull requests**, and drops reviewed/commented PRs where the viewer's latest non-comment review state is `APPROVED` (from `reviews` plus `latestOpinionatedReviews`; a pending review request keeps the PR even after an approval).
- README and `CHANGELOG.md` (`[Unreleased]`) should stay current when user-facing behavior changes.

## Git safety

- `git status`, `git diff`, and `git log` are safe.
- Avoid destructive git commands unless explicitly requested.
- Keep unrelated worktree changes untouched.
