import Foundation

struct Dashboard: Sendable {
    var viewer: String
    var myPRs: [PullRequest]
    var reviewRequests: [PullRequest]
}

enum GitHubError: LocalizedError {
    case http(Int, String)
    case graphQL([String])

    var errorDescription: String? {
        switch self {
        case .http(let status, let body):
            return "GitHub returned HTTP \(status): \(body)"
        case .graphQL(let messages):
            return "GraphQL error: \(messages.joined(separator: "; "))"
        }
    }
}

struct GitHubClient: Sendable {
    var token: String

    private static let endpoint = URL(string: "https://api.github.com/graphql")!

    private static let dashboardQuery = """
    query Dashboard {
      viewer { login }
      mine: search(query: "is:pr is:open author:@me archived:false", type: ISSUE, first: 50) {
        nodes { ...prFields }
      }
      assigned: search(query: "is:pr is:open assignee:@me archived:false", type: ISSUE, first: 50) {
        nodes { ...prFields }
      }
      reviews: search(query: "is:pr is:open review-requested:@me archived:false", type: ISSUE, first: 50) {
        nodes { ...prFields }
      }
    }
    fragment prFields on PullRequest {
      id number title url isDraft reviewDecision additions deletions createdAt updatedAt
      headRefName
      totalCommentsCount
      repository { nameWithOwner }
      author { login }
      labels(first: 10) { nodes { name color } }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
    }
    """

    func fetchDashboard() async throws -> Dashboard {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["query": Self.dashboardQuery])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw GitHubError.http(status, String(decoding: data, as: UTF8.self))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(Envelope.self, from: data)
        if let errors = envelope.errors, !errors.isEmpty {
            throw GitHubError.graphQL(errors.map(\.message))
        }
        guard let payload = envelope.data else {
            throw GitHubError.graphQL(["empty response"])
        }

        // "My pull requests" = authored + assigned, deduplicated (you can be both).
        let authored = payload.mine.nodes.compactMap { $0?.pullRequest }
        let assigned = payload.assigned.nodes.compactMap { $0?.pullRequest }
        var seen = Set(authored.map(\.id))
        let myPRs = (authored + assigned.filter { seen.insert($0.id).inserted })
            .sorted { $0.updatedAt > $1.updatedAt }

        return Dashboard(
            viewer: payload.viewer.login,
            myPRs: myPRs,
            reviewRequests: payload.reviews.nodes.compactMap { $0?.pullRequest }
        )
    }
}

// MARK: - Response decoding

private struct Envelope: Decodable {
    var data: Payload?
    var errors: [GraphQLError]?
}

private struct GraphQLError: Decodable {
    var message: String
}

private struct Payload: Decodable {
    var viewer: Viewer
    var mine: SearchResult
    var assigned: SearchResult
    var reviews: SearchResult
}

private struct Viewer: Decodable {
    var login: String
}

private struct SearchResult: Decodable {
    var nodes: [PRNode?]
}

/// Search nodes can be non-PR types in theory; decode leniently and drop misses.
private struct PRNode: Decodable {
    var id: String?
    var number: Int?
    var title: String?
    var url: URL?
    var isDraft: Bool?
    var headRefName: String?
    var reviewDecision: PullRequest.ReviewDecision?
    var additions: Int?
    var deletions: Int?
    var createdAt: Date?
    var updatedAt: Date?
    var totalCommentsCount: Int?
    var repository: Repository?
    var author: Author?
    var labels: LabelConnection?
    var commits: CommitConnection?

    struct Repository: Decodable { var nameWithOwner: String }
    struct Author: Decodable { var login: String }
    struct LabelConnection: Decodable { var nodes: [PullRequest.Label?] }
    struct CommitConnection: Decodable {
        var nodes: [Node?]
        struct Node: Decodable { var commit: Commit }
        struct Commit: Decodable { var statusCheckRollup: Rollup? }
        struct Rollup: Decodable { var state: PullRequest.CheckState? }
    }

    var pullRequest: PullRequest? {
        guard let id, let number, let title, let url, let updatedAt, let repository else {
            return nil
        }
        return PullRequest(
            id: id,
            number: number,
            title: title,
            url: url,
            repository: repository.nameWithOwner,
            author: author?.login ?? "ghost",
            headBranch: headRefName ?? "",
            isDraft: isDraft ?? false,
            reviewDecision: reviewDecision,
            checkState: commits?.nodes.first??.commit.statusCheckRollup?.state,
            labels: labels?.nodes.compactMap { $0 } ?? [],
            commentCount: totalCommentsCount ?? 0,
            additions: additions ?? 0,
            deletions: deletions ?? 0,
            createdAt: createdAt ?? updatedAt,
            updatedAt: updatedAt
        )
    }
}
