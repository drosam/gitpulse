# GHPulse

A small native macOS app that tracks your work on GitHub in one window:

- **My pull requests** — open PRs you authored or are assigned to
- **Review requested** — open PRs waiting for your review

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue) ![Swift 6](https://img.shields.io/badge/Swift-6-orange)

## Features

- Two-pane dashboard, refreshed automatically every 60 seconds (`⌘R` to refresh manually)
- Click a row to open the PR in your browser
- Each row shows draft state, CI status (✓ / ✗ / running), head branch, labels, comment count, age, author, and review decision
- **Notifications** — GHPulse polls GitHub's notification inbox (cheap ETag conditional requests):
  - macOS banner for each new PR notification; click it to open the PR
  - Blue dot on rows with unread notifications
  - Menubar circle fills when anything is unread; Dock icon shows the unread count
  - Opening a PR marks its notifications read on GitHub, and reading on github.com clears them here — both stay in sync
- Lives in the menubar: closing the window hides the Dock icon, the app keeps polling in the background

## Install

```sh
make install
open -a GHPulse
```

This builds a release binary, generates the app icon, and installs `/Applications/GHPulse.app` (ad-hoc signed). Remove with `make uninstall`.

### Requirements

- macOS 15+
- Swift 6 toolchain (Xcode 16+)

For development, `swift run` works too (macOS banners are disabled there — they need a real app bundle).

## Authentication

GHPulse resolves a GitHub token in this order:

1. `GITHUB_TOKEN` environment variable
2. macOS Keychain (saved by a previous sign-in)
3. `gh auth token` (if the GitHub CLI is installed and logged in)
4. OAuth device flow — click **Sign in with GitHub**, enter the code shown

The device flow uses a registered OAuth app (client ID in `Sources/GHPulse/GitHub/DeviceFlow.swift`). No client secret is needed or shipped; tokens are stored only in the Keychain.

The token needs the `repo` scope (covers private-repo search and the notifications API) and `read:org` (lets search see org PRs).
