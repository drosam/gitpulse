# Changelog

All notable changes to GitPulse are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

Each release's GitHub notes are taken from its section below, so add an entry before tagging.

## [Unreleased]

### Changed

- Show hidden pull requests moved from `⌘H` to `⇧⌘H` (**View → Show Hidden Pull Requests**), so `⌘H` hides GitPulse again like other apps.
- Letter shortcuts (`H`, `V`) follow your keyboard layout instead of the physical key position.
- Automatic refresh runs every 2 minutes instead of every minute, and each refresh uses about half the GitHub API budget it did, so GitPulse takes roughly a quarter of your hourly GraphQL rate limit instead of most of it. Inline review replies are now read from the 10 most recent threads per pull request instead of 20.
- When GitHub's rate limit runs out, automatic refresh pauses until it resets, and a manual refresh says when it will retry.

### Fixed

- Typing in Settings no longer triggers dashboard shortcuts: `H`, `V`, Space, Return and arrow keys reach the text field, and `⌘C` copies the selected text instead of a pull request URL.
- A pull request that GitHub can no longer resolve (deleted repository, lost access) no longer makes every refresh fail until you sign out.
- The first comment or review on a pull request with no earlier activity now shows a banner and an unread dot.
- A pull request you approved comes back to **Review requested** when the author requests your review again.
- A pull request that newly appears with finished checks (for example, a new review request on a green pull request) no longer shows an extra "Checks passed/failed" banner.
- Commenting on or reviewing someone else's pull request no longer shows a "Review requested" banner for it; the banner now appears only when GitHub requests your review, including a new request on a pull request you already reviewed.
- A comment-only review after approving no longer puts the pull request back in **Review requested**, and an approval stays remembered on pull requests with many reviews.
- Changing the repository filter no longer shows a burst of "Review requested" and "Merged" banners and unread rows for pull requests that were already there.
- A pull request that merged long ago no longer shows a "Merged" banner and unread row when someone comments on it or changes it.
- A review request that arrives while GitPulse is closed now shows a banner and an unread dot on the next launch.
- Opening a pull request from its banner now clears its unread dot, the Dock badge count, and its merged row, like opening the row does.
- Changing **Pull request order** in Settings reorders the lists right away instead of at the next refresh.
- A failed refresh no longer replaces the dashboard with an error screen: the last pull requests stay visible with the error shown above them. Restoring a hidden pull request and showing hidden pull requests work offline and no longer refetch from GitHub.
- Automatic refreshes that fail now show the same error above the dashboard instead of silently leaving stale data. A revoked or expired GitHub sign-in returns to the sign-in screen with an explanation and keeps unread and hidden pull requests.
- **Only selected repositories** with no valid entry now shows no pull requests instead of every repository, and Settings lists the ignored lines. GitHub repository URLs are accepted as entries.
- Overlapping refreshes no longer apply an older response over a newer one, and a refresh finishing after sign-out no longer brings the dashboard back.
- A pull request's icon no longer turns into a magenta square after it enters the merge queue or merges while GitPulse is open.

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
