# Changelog

All notable changes to GitPulse are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

Each release's GitHub notes are taken from its section below, so add an entry before tagging.

## [Unreleased]

### Added

- **Settings… → Account** shows the signed-in login and where the token comes from, with **Sign Out** and a pointer to revoking GitPulse on GitHub.

### Changed

- The app is signed with the hardened runtime, so libraries injected into GitPulse can't read its Keychain token.
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
- Switching GitHub accounts (another token, `gh auth switch`, or signing in after a revoked token) no longer carries hidden pull requests, unread rows, and notification history across accounts or bursts banners for the new account. Each account keeps its own state; existing state moves to the first account that refreshes.
- Hiding or restoring a pull request with an unread dot updates the Dock badge count right away instead of at the next refresh.
- A review decision or check state that GitHub adds in the future is shown as none instead of failing every refresh.
- Signing out now sticks when the token comes from `GITHUB_TOKEN` or the GitHub CLI, instead of signing straight back in. The sign-in screen offers to use that token again.
- Sign-in runs one device flow at a time and has a **Cancel** button. Reopening the window keeps the code on screen, an abandoned sign-in no longer replaces a working dashboard with "device code expired" later, and a brief network or GitHub error while waiting for approval no longer aborts sign-in.
- Opening the window no longer freezes GitPulse while it looks up your token. The lookup runs in the background, `gh auth token` is stopped after 5 seconds, and reopening the window reuses the token already loaded instead of running `gh` again.
- If the Keychain refuses to save your sign-in, GitPulse now says so instead of silently asking you to sign in again next launch, and if signing out can't delete the saved token, the sign-in screen says how to remove it.
- Sign-in refuses a device-flow verification link that doesn't point to `https://github.com`, like every other link GitPulse opens.
- Unread summaries pick their icon from the event type, so a comment by someone like `@merged-bot` no longer shows the merge icon.
- The GitHub CLI token is read for `github.com` only, so a GitHub Enterprise token from `gh` is never sent to `api.github.com`.
- Repository entries with an empty path part, like `acme//web` or `acme/web/`, are flagged as invalid instead of being searched.
- When a pane's GitHub search matches more than 50 pull requests, GitPulse keeps the 50 most recently updated ones instead of an arbitrary subset, and shows `+` after the pane count.
- A review with inline comments now posts one notification instead of one per comment plus one for the review, and a comment-only review or thread reply reads "commented".
- CI results on a new commit are announced even when the checks finished between two refreshes, so a second failure in a row is no longer missed.
- Two comments or reviews posted in the same second on one pull request now both show as unread instead of one replacing the other.
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
