import Foundation

struct Dashboard: Sendable {
    var viewer: String
    var myPRs: [PullRequest]
    /// Open PRs where your review is requested, or where you participated and have not approved.
    var reviewRequests: [PullRequest]
    /// `reviewRequests` IDs from `review-requested:@me`; only these announce a review request.
    var requestedReviewIDs: Set<PullRequest.ID>
    /// Recently merged PRs you authored or were assigned to. Not shown in any
    /// pane — used only to banner a merge once, since merged PRs drop out of the
    /// open searches.
    var recentlyMerged: [PullRequest]
}

enum GitHubError: LocalizedError, Equatable {
    /// HTTP status plus GitHub's JSON `message`, when the body has one.
    case http(Int, String?)
    case graphQL([String])
    /// GitHub's rate limit is used up; requests should wait until `until`.
    case rateLimited(until: Date)

    /// Builds an `.http` error without echoing raw response bodies into the UI.
    static func http(status: Int, body: Data) -> GitHubError {
        struct Message: Decodable { var message: String }
        let message = (try? JSONDecoder().decode(Message.self, from: body))?.message
        return .http(status, message)
    }

    var errorDescription: String? {
        switch self {
        case .http(let status, let message?):
            return "GitHub returned HTTP \(status): \(message)"
        case .http(let status, nil):
            return "GitHub returned HTTP \(status)"
        case .graphQL(let messages):
            return "GraphQL error: \(messages.joined(separator: "; "))"
        case .rateLimited(let until):
            return "GitHub rate limit reached. GitPulse refreshes again at \(until.formatted(date: .omitted, time: .shortened))."
        }
    }
}

struct GitHubClient: Sendable {
    var token: String
    var repositories: [String] = []
    var trackedPullRequestIDs: [PullRequest.ID] = []
    var transport: HTTP.Transport = HTTP.live

    private static let endpoint = URL(string: "https://api.github.com/graphql")!

    private var dashboardQuery: String {
        let repoFilter = repositories
            .map { "repo:\($0)" }
            .joined(separator: " ")
        let scoped: (String) -> String = { query in
            repoFilter.isEmpty ? query : "\(query) \(repoFilter)"
        }

        let trackedIDs = trackedPullRequestIDs
            .prefix(100)
            .map { "\"\($0)\"" }
            .joined(separator: ", ")

        return """
        query Dashboard {
          viewer { login }
          mine: search(query: "\(scoped("is:pr is:open author:@me archived:false"))", type: ISSUE, first: 50) {
            nodes { ...prFields }
          }
          assigned: search(query: "\(scoped("is:pr is:open assignee:@me archived:false"))", type: ISSUE, first: 50) {
            nodes { ...prFields }
          }
          reviews: search(query: "\(scoped("is:pr is:open review-requested:@me archived:false"))", type: ISSUE, first: 50) {
            nodes { ...prFields }
          }
          reviewed: search(query: "\(scoped("is:pr is:open reviewed-by:@me archived:false"))", type: ISSUE, first: 50) {
            nodes { ...prFields }
          }
          commented: search(query: "\(scoped("is:pr is:open commenter:@me archived:false"))", type: ISSUE, first: 50) {
            nodes { ...prFields }
          }
          mergedAuthored: search(query: "\(scoped("is:pr is:merged author:@me archived:false sort:updated-desc"))", type: ISSUE, first: 20) {
            nodes { ...prSummary }
          }
          mergedAssigned: search(query: "\(scoped("is:pr is:merged assignee:@me archived:false sort:updated-desc"))", type: ISSUE, first: 20) {
            nodes { ...prSummary }
          }
          tracked: nodes(ids: [\(trackedIDs)]) {
            ... on PullRequest { ...prSummary }
          }
        }
        fragment prSummary on PullRequest {
          id number title url state isDraft isInMergeQueue reviewDecision additions deletions createdAt updatedAt mergedAt
          headRefName
          totalCommentsCount
          repository { nameWithOwner }
          author { login }
          mergeQueueEntry { state }
          labels(first: 10) { nodes { name color } }
          commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
        }
        fragment prFields on PullRequest {
          ...prSummary
          comments(last: 10) { nodes { author { login } createdAt } }
          reviews(last: 30) { nodes { author { login } state submittedAt } }
          latestOpinionatedReviews(first: 100) { nodes { author { login } state submittedAt } }
          reviewThreads(last: 10) { nodes { comments(last: 10) { nodes { author { login } createdAt } } } }
        }
        """
    }

    func fetchDashboard() async throws -> Dashboard {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["query": dashboardQuery])

        let (data, response) = try await transport(request)
        let http = response as? HTTPURLResponse
        let resume = http.flatMap { Self.rateLimitResume(from: $0, now: Date()) }
        do {
            guard http?.statusCode == 200 else {
                throw GitHubError.http(status: http?.statusCode ?? 0, body: data)
            }
            return try Self.decodeDashboard(data)
        } catch {
            if let resume { throw GitHubError.rateLimited(until: resume) }
            throw error
        }
    }

    /// When GitHub allows the next request, if this response reports an exhausted rate limit.
    static func rateLimitResume(from response: HTTPURLResponse, now: Date) -> Date? {
        if response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0",
           let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init) {
            return Date(timeIntervalSince1970: reset)
        }
        if let delay = response.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init) {
            return now.addingTimeInterval(delay)
        }
        return nil
    }

    /// Decodes a GraphQL dashboard response and applies the pane rules.
    static func decodeDashboard(_ data: Data) throws -> Dashboard {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(Envelope.self, from: data)
        // A tracked PR that no longer resolves (deleted repo, lost access) comes back null with an
        // error; ignore those so one dead ID cannot fail every refresh.
        let errors = (envelope.errors ?? []).filter { envelope.data == nil || $0.field != "tracked" }
        if !errors.isEmpty {
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

        let mergedAuthored = payload.mergedAuthored.nodes.compactMap { $0?.pullRequest }
        let mergedAssigned = payload.mergedAssigned.nodes.compactMap { $0?.pullRequest }
        let trackedMerged = payload.tracked?.compactMap { node -> PullRequest? in
            guard node?.state == "MERGED" else { return nil }
            return node?.pullRequest
        } ?? []
        seen = []
        let recentlyMerged = (mergedAuthored + mergedAssigned + trackedMerged)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.updatedAt > $1.updatedAt }

        let viewer = payload.viewer.login
        seen = []
        let myPRIDs = Set(myPRs.map(\.id))
        // A pending request wins over an earlier approval; participation alone ends at approval.
        let participated = (payload.reviewed.nodes + payload.commented.nodes)
            .compactMap { $0 }
            .filter { $0.latestReviewState(by: viewer) != "APPROVED" }
        let reviewRequests = (payload.reviews.nodes.compactMap { $0 } + participated)
            .compactMap { $0.pullRequest }
            .filter { !myPRIDs.contains($0.id) }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.updatedAt > $1.updatedAt }

        return Dashboard(
            viewer: viewer,
            myPRs: myPRs,
            reviewRequests: reviewRequests,
            requestedReviewIDs: Set(payload.reviews.nodes.compactMap { $0?.pullRequest?.id }).subtracting(myPRIDs),
            recentlyMerged: recentlyMerged
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
    /// Top-level response field the error belongs to, from the first `path` element.
    var field: String?

    private enum CodingKeys: String, CodingKey { case message, path }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        if var path = try? container.nestedUnkeyedContainer(forKey: .path) {
            field = try? path.decode(String.self)
        }
    }
}

private struct Payload: Decodable {
    var viewer: Viewer
    var mine: SearchResult
    var assigned: SearchResult
    var reviews: SearchResult
    var reviewed: SearchResult
    var commented: SearchResult
    var mergedAuthored: SearchResult
    var mergedAssigned: SearchResult
    var tracked: [PRNode?]?
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
    var state: String?
    var isDraft: Bool?
    var isInMergeQueue: Bool?
    var headRefName: String?
    /// Raw strings so a value GitHub adds later maps to nil instead of failing the whole decode.
    var reviewDecision: String?
    var additions: Int?
    var deletions: Int?
    var createdAt: Date?
    var updatedAt: Date?
    var mergedAt: Date?
    var totalCommentsCount: Int?
    var repository: Repository?
    var author: Author?
    var mergeQueueEntry: MergeQueueEntry?
    var labels: LabelConnection?
    var commits: CommitConnection?
    var comments: CommentConnection?
    var reviews: ReviewConnection?
    /// Latest approval / change request per user, even when older than `reviews(last: 30)`.
    var latestOpinionatedReviews: ReviewConnection?
    var reviewThreads: ReviewThreadConnection?

    struct Repository: Decodable { var nameWithOwner: String }
    struct Author: Decodable { var login: String }
    struct MergeQueueEntry: Decodable { var state: String? }
    struct LabelConnection: Decodable { var nodes: [PullRequest.Label?] }
    struct CommitConnection: Decodable {
        var nodes: [Node?]
        struct Node: Decodable { var commit: Commit }
        struct Commit: Decodable { var statusCheckRollup: Rollup? }
        struct Rollup: Decodable { var state: String? }
    }
    struct CommentConnection: Decodable {
        var nodes: [Node?]
        struct Node: Decodable { var author: Author?; var createdAt: Date? }
    }
    struct ReviewConnection: Decodable {
        var nodes: [Node?]
        struct Node: Decodable { var author: Author?; var state: String?; var submittedAt: Date? }
    }
    struct ReviewThreadConnection: Decodable {
        var nodes: [Node?]
        struct Node: Decodable { var comments: CommentConnection? }
    }

    /// The viewer's newest review that changes their verdict; comment-only and pending reviews don't.
    func latestReviewState(by login: String) -> String? {
        ((reviews?.nodes ?? []) + (latestOpinionatedReviews?.nodes ?? []))
            .compactMap { node -> (state: String, submittedAt: Date)? in
                guard let node,
                      node.author?.login == login,
                      let state = node.state,
                      state != "COMMENTED", state != "PENDING",
                      let submittedAt = node.submittedAt else { return nil }
                return (state, submittedAt)
            }
            .max { $0.submittedAt < $1.submittedAt }?
            .state
    }

    /// Comments + reviews flattened into activity events, sorted newest-last.
    private var activityEvents: [PullRequest.ActivityEvent] {
        var events: [PullRequest.ActivityEvent] = []
        for node in comments?.nodes ?? [] {
            guard let node, let login = node.author?.login, let at = node.createdAt else { continue }
            events.append(.init(kind: .comment, author: login, createdAt: at))
        }
        for node in reviews?.nodes ?? [] {
            guard let node, let login = node.author?.login, let at = node.submittedAt else { continue }
            events.append(.init(kind: .review(state: node.state ?? ""), author: login, createdAt: at))
        }
        for thread in reviewThreads?.nodes ?? [] {
            for comment in thread?.comments?.nodes ?? [] {
                guard let comment, let login = comment.author?.login, let at = comment.createdAt else { continue }
                events.append(.init(kind: .comment, author: login, createdAt: at))
            }
        }
        return events.sorted { $0.createdAt < $1.createdAt }
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
            isMerged: state == "MERGED",
            reviewDecision: reviewDecision.flatMap(PullRequest.ReviewDecision.init(rawValue:)),
            checkState: commits?.nodes.first??.commit.statusCheckRollup?.state.flatMap(PullRequest.CheckState.init(rawValue:)),
            isInMergeQueue: isInMergeQueue ?? false,
            mergeQueueState: mergeQueueEntry?.state,
            labels: labels?.nodes.compactMap { $0 } ?? [],
            activity: activityEvents,
            commentCount: totalCommentsCount ?? 0,
            additions: additions ?? 0,
            deletions: deletions ?? 0,
            createdAt: createdAt ?? updatedAt,
            updatedAt: updatedAt,
            mergedAt: mergedAt
        )
    }
}
