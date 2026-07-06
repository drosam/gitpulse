# GitPulse

A small native macOS app that tracks your work on GitHub in one window:

- **My pull requests** — open PRs you authored or are assigned to, plus unread merged PRs until opened
- **Review requested** — open PRs waiting for your review, plus PRs you commented on or reviewed until you approve them; PRs already in **My pull requests** stay only there

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue) ![Swift 6](https://img.shields.io/badge/Swift-6-orange)

## Features

- Two-pane dashboard, refreshed automatically every 60 seconds (`⌘R` to refresh manually)
- Click a row or press Return to open the selected PR in your browser
- Keyboard navigation: arrow keys move between rows/panes, `V` shows unread notification details for the selected PR, Space clears an unread dot, `⌘C` copies the selected PR URL, `H` hides/restores the selected PR, `⌘H` toggles showing hidden PRs
- Each row shows draft state, merged/merge-queue status, CI status (✓ / ✗ / running), head branch, labels, comment count, age, author, and review decision
- **Notifications** — GitPulse detects useful PR activity from the dashboard:
  - macOS banners for new review requests, new top-level comments, inline review-thread replies, submitted reviews, CI completion, merge-queue exits, and newly merged PRs you authored or were assigned to
  - Newly merged authored/assigned PRs stay in **My pull requests** with a purple merged icon and unread dot until you open them or press Space to dismiss
  - Optional sound
  - Optional blue unread dots in rows and the menu bar
  - Optional Dock badge count while anything is unread
- **Settings** (`⌘,` or menu bar icon → **Settings…**):
  - Show/hide notification banners
  - Turn notification sounds on/off
  - Show/hide Dock badge count
  - Show/hide unread dots
  - Start GitPulse automatically when you log in
  - Check all matching repositories or only selected `owner/repo` repositories
  - Show hidden pull requests in lists
  - Restore hidden pull requests
- Lives in the menu bar: closing the window hides the Dock icon, the app keeps polling in the background

## Review requests

- **Review requested** includes open PRs where GitHub is requesting your review.
- If you leave comments or request changes, GitPulse keeps the PR in the list until you approve it or the PR closes/merges.
- PRs you authored or are assigned to stay only in **My pull requests**, even if you commented on them.
- Approved PRs are removed from **Review requested** unless GitHub requests your review again.

## Merged pull requests

- When a PR you authored or are assigned to merges, GitPulse keeps it temporarily in **My pull requests**.
- Merged rows use GitHub's purple merge icon, show a **Merged** pill, and drive the row dot, menu bar dot, and Dock badge like other unread items.
- Open the row or press Space to clear it. Once cleared, the merged row is removed from the list.
- Merged PRs are never added to **Review requested**.

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
