# AGENTS.md

Guidance for coding agents working in this repository.

## Project

GitPulse is a native macOS SwiftUI menu bar app that tracks GitHub pull requests.

## Commands

- Build debug: `swift build`
- Build release/install app: `make install`
- Uninstall app: `make uninstall`
- Launch installed app: `open -a GitPulse`

## Workflow

- Read code before editing.
- Prefer small, focused changes.
- Preserve existing SwiftUI/AppKit patterns.
- Run `swift build` after code changes when feasible.
- Do not add dependencies without explicit approval.
- Do not commit unless asked.
- Do not kill/relaunch/install unless asked.

## Code notes

- Settings live in `Sources/GitPulse/AppSettings.swift`, including launch-at-login via `SMAppService.mainApp`.
- Runtime state and notification detection live in `Sources/GitPulse/Session.swift`.
- GitHub GraphQL fetching/decoding lives in `Sources/GitPulse/GitHub/GitHubClient.swift`.
- Main dashboard UI lives in `Sources/GitPulse/Views/ContentView.swift` and `Sources/GitPulse/Views/PRListView.swift`.
- Merged authored/assigned PRs are kept as temporary unread rows in **My pull requests** until opened or dismissed; see `pendingMergedPullRequests` in `Session.swift`.
- Activity notifications include top-level PR comments, submitted reviews, and inline review-thread comments fetched in `GitHubClient.swift`.
- Unread blue dots are backed by `Session.unreadNotifications`; clicking the dot or pressing `V` shows the same summary as the macOS banner, not comment bodies.
- **Review requested** combines `review-requested:@me`, `reviewed-by:@me`, and `commenter:@me`, excludes PRs already in **My pull requests**, then filters out PRs where the viewer's latest review state is `APPROVED`.
- README should stay current when user-facing behavior changes.

## Git safety

- `git status`, `git diff`, and `git log` are safe.
- Avoid destructive git commands unless explicitly requested.
- Keep unrelated worktree changes untouched.
