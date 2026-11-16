# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through [GitHub private vulnerability reporting](https://github.com/drosam/gitpulse/security/advisories/new). Do not open a public issue.

Include the GitPulse version (shown in the menu bar menu), your macOS version, steps to reproduce, and the impact you expect. You should get a reply within a week.

## Supported versions

Only the latest release receives fixes.

## How GitPulse handles your token

- The token comes from `GITHUB_TOKEN`, the macOS Keychain, `gh auth token`, or GitHub's OAuth device flow.
- Device-flow tokens are stored only in your login Keychain (service `dev.davidrosa.gitpulse.github-token`).
- The token is sent only to `api.github.com`. The device flow talks only to `github.com`.
- GitPulse has no servers, analytics, or telemetry.
- Remove the Keychain item with `security delete-generic-password -s dev.davidrosa.gitpulse.github-token`.
