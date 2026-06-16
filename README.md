# GitPulse

A small native macOS app that tracks your work on GitHub in one window:

- **My pull requests** — open PRs you authored or are assigned to
- **Review requested** — open PRs waiting for your review

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue) ![Swift 6](https://img.shields.io/badge/Swift-6-orange)

## Features

- Two-pane dashboard, refreshed automatically every 60 seconds (`⌘R` to refresh manually)
- Click a row or press Return to open the selected PR in your browser
- Keyboard navigation: arrow keys move between rows/panes, Space clears an unread dot, `⌘C` copies the selected PR URL, `H` hides/restores the selected PR, `⌘H` toggles showing hidden PRs
- Each row shows draft state, CI status (✓ / ✗ / running), head branch, labels, comment count, age, author, and review decision
- **Notifications** — GitPulse detects useful PR activity from the dashboard:
  - macOS banners for new review requests, new comments/reviews, CI completion, merge-queue exits, and newly merged PRs
  - Optional sound
  - Optional blue unread dots in rows and the menu bar
  - Optional Dock badge count while anything is unread
- **Settings** (`⌘,` or menu bar icon → **Settings…**):
  - Show/hide notification banners
  - Turn notification sounds on/off
  - Show/hide Dock badge count
  - Show/hide unread dots
  - Check all matching repositories or only selected `owner/repo` repositories
  - Show hidden pull requests in lists
  - Restore hidden pull requests
- Lives in the menu bar: closing the window hides the Dock icon, the app keeps polling in the background

## Hiding pull requests

- Select a PR and press `H`, or right-click it and choose **Hide Pull Request**.
- Press `H` on a hidden PR, or right-click it and choose **Restore Pull Request**, to restore it.
- Press `⌘H`, or use **Settings… → Hidden Pull Requests → Show hidden pull requests in lists**, to show/hide hidden PRs in the dashboard.
- When shown, hidden PRs move to the bottom of each list, keep their relative order, and are dimmed and marked **Hidden**.
- Hidden PRs can still show a row-level blue unread dot, but they do not drive the menu bar dot, Dock badge, notification banners, or sounds.
- Restore one or all hidden PRs from **Settings… → Hidden Pull Requests**.

## Install

```sh
make install
open -a GitPulse
```

This builds a release binary, generates the app icon, and installs `/Applications/GitPulse.app` (ad-hoc signed). Remove with `make uninstall`.

### Requirements

- macOS 15+
- Swift 6 toolchain (Xcode 16+)

For development, `swift run` works too (macOS banners are disabled there — they need a real app bundle).

## Authentication

GitPulse resolves a GitHub token in this order:

1. `GITHUB_TOKEN` environment variable
2. macOS Keychain (saved by a previous sign-in)
3. `gh auth token` (if the GitHub CLI is installed and logged in)
4. OAuth device flow — click **Sign in with GitHub**, enter the code shown

The device flow uses a registered OAuth app (client ID in `Sources/GitPulse/GitHub/DeviceFlow.swift`). No client secret is needed or shipped; tokens are stored only in the Keychain.

The token needs the `repo` scope (covers private-repo search) and `read:org` (lets search see org PRs).
