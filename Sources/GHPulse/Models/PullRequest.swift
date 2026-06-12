import Foundation

struct PullRequest: Identifiable, Hashable, Decodable, Sendable {
    enum ReviewDecision: String, Decodable, Sendable {
        case approved = "APPROVED"
        case changesRequested = "CHANGES_REQUESTED"
        case reviewRequired = "REVIEW_REQUIRED"
    }

    /// `statusCheckRollup.state` of the head commit; nil when the PR has no checks.
    enum CheckState: String, Decodable, Sendable {
        case success = "SUCCESS"
        case failure = "FAILURE"
        case error = "ERROR"
        case pending = "PENDING"
        case expected = "EXPECTED"
    }

    struct Label: Hashable, Decodable, Sendable {
        var name: String
        /// 6-digit hex without "#", as returned by the API (e.g. "d73a4a").
        var color: String
    }

    var id: String
    var number: Int
    var title: String
    var url: URL
    var repository: String
    var author: String
    var headBranch: String
    var isDraft: Bool
    var reviewDecision: ReviewDecision?
    var checkState: CheckState?
    var labels: [Label]
    var commentCount: Int
    var additions: Int
    var deletions: Int
    var createdAt: Date
    var updatedAt: Date
}
