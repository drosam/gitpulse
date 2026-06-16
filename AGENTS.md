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

- Settings live in `Sources/GitPulse/AppSettings.swift`.
- Runtime state and notification detection live in `Sources/GitPulse/Session.swift`.
- GitHub GraphQL fetching/decoding lives in `Sources/GitPulse/GitHub/GitHubClient.swift`.
- Main dashboard UI lives in `Sources/GitPulse/Views/ContentView.swift` and `Sources/GitPulse/Views/PRListView.swift`.
- README should stay current when user-facing behavior changes.

## Git safety

- `git status`, `git diff`, and `git log` are safe.
- Avoid destructive git commands unless explicitly requested.
- Keep unrelated worktree changes untouched.
