# Changelog

All notable changes to GitPulse are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

Each release's GitHub notes are taken from its section below, so add an entry before tagging.

## [Unreleased]

## [0.1.0] - 2026-11-15

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
