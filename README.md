# Scout

A small macOS app that tracks your work on GitHub: open pull requests you created, and pull requests waiting for your review — side by side in one window.

## Requirements

- macOS 15+
- Swift 6 toolchain (Xcode 16+)

## Run

```sh
swift run
```

## Authentication

Scout resolves a GitHub token in this order:

1. `GITHUB_TOKEN` environment variable
2. macOS Keychain (saved by a previous sign-in)
3. `gh auth token` (if the GitHub CLI is installed and logged in)
4. OAuth device flow — click **Sign in with GitHub**, enter the code shown

The device flow requires a registered OAuth app (client ID in `Sources/Scout/GitHub/DeviceFlow.swift`). No client secret is needed or shipped; tokens are stored only in the Keychain.

## Keyboard

- `⌘R` — refresh
- Double-click a row — open the PR on GitHub
