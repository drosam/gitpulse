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

/// Where `Session` reads, saves, and clears the GitHub token.
struct TokenProvider: Sendable {
    var resolve: @Sendable () -> String?
    var save: @Sendable (String) -> Void
    var clear: @Sendable () -> Void

    static let keychain = TokenProvider(
        resolve: { TokenStore.resolve() },
        save: { TokenStore.save($0) },
        clear: { TokenStore.clear() }
    )
}
