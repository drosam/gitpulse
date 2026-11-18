import Foundation

/// Supplies dashboard snapshots to `Session`.
protocol DashboardSource: Sendable {
    func fetchDashboard(token: String, repositories: [String], trackedPullRequestIDs: [PullRequest.ID]) async throws -> Dashboard
}

struct GitHubDashboardSource: DashboardSource {
    func fetchDashboard(token: String, repositories: [String], trackedPullRequestIDs: [PullRequest.ID]) async throws -> Dashboard {
        try await GitHubClient(
            token: token,
            repositories: repositories,
            trackedPullRequestIDs: trackedPullRequestIDs
        ).fetchDashboard()
    }
}

enum TokenSource: Sendable, Equatable {
    case environment
    case keychain
    case githubCLI

    var label: String {
        switch self {
        case .environment: "GITHUB_TOKEN environment variable"
        case .keychain: "Keychain (Sign in with GitHub)"
        case .githubCLI: "GitHub CLI (gh auth token)"
        }
    }
}

struct ResolvedToken: Sendable {
    var token: String
    var source: TokenSource
}

/// Where `Session` reads, saves, and clears the GitHub token.
struct TokenProvider: Sendable {
    var resolve: @Sendable () -> ResolvedToken?
    var save: @Sendable (String) -> Void
    var clear: @Sendable () -> Void

    static let keychain = TokenProvider(
        resolve: { TokenStore.resolve() },
        save: { TokenStore.save($0) },
        clear: { TokenStore.clear() }
    )
}
