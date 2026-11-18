# Changelog

All notable changes to GitPulse are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

Each release's GitHub notes are taken from its section below, so add an entry before tagging.

## [Unreleased]

### Changed

- Show hidden pull requests moved from `⌘H` to `⇧⌘H` (**View → Show Hidden Pull Requests**), so `⌘H` hides GitPulse again like other apps.
- Letter shortcuts (`H`, `V`) follow your keyboard layout instead of the physical key position.

### Fixed

- Typing in Settings no longer triggers dashboard shortcuts: `H`, `V`, Space, Return and arrow keys reach the text field, and `⌘C` copies the selected text instead of a pull request URL.
- A pull request that GitHub can no longer resolve (deleted repository, lost access) no longer makes every refresh fail until you sign out.
- The first comment or review on a pull request with no earlier activity now shows a banner and an unread dot.

### Security

- GitHub requests no longer use the shared disk cache. v0.1.0 saved every request, including the `Authorization` header with your token, and the responses in `~/Library/Caches/dev.davidrosa.gitpulse`. GitPulse now deletes that folder and `~/Library/HTTPStorages/dev.davidrosa.gitpulse` at launch, and `brew uninstall --zap` removes them. If other software running as your user could have read those files, revoke the token: OAuth tokens (**Sign in with GitHub**, GitHub CLI) at <https://github.com/settings/applications>, personal access tokens at <https://github.com/settings/tokens>.

## [0.1.0] - 2026-11-16

First public release.

### Added

- Two-pane dashboard: **My pull requests** (authored or assigned) and **Review requested** (requested, reviewed, or commented until you approve).
- macOS notifications for review requests, comments, inline review replies, submitted reviews, CI results, merge-queue exits, and merges.
- Unread dots in rows and the menu bar, optional Dock badge, and a summary popover (`V`).
- Merged pull requests stay as unread rows until opened or dismissed.
- Hide and restore pull requests (`H`, `⌘H`).
- Keyboard navigation, copy URL (`⌘C`), and created/updated sort order.
- Repository filter, launch at login, and notification settings.
- App version shown in the menu bar menu.
- `--demo` launch mode with fictional data.
- Homebrew cask (`brew install --cask drosam/tap/gitpulse`) and universal ZIP/DMG releases.

### Security

- Only `https://github.com` links are opened from rows and notifications.
- Error messages no longer include raw HTTP response bodies.

[Unreleased]: https://github.com/drosam/gitpulse/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/drosam/gitpulse/releases/tag/v0.1.0
