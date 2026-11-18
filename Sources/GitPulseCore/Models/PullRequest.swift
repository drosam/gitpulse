import Foundation

struct PullRequest: Identifiable, Hashable, Codable, Sendable {
    enum ReviewDecision: String, Codable, Sendable {
        case approved = "APPROVED"
        case changesRequested = "CHANGES_REQUESTED"
        case reviewRequired = "REVIEW_REQUIRED"
    }

    /// `statusCheckRollup.state` of the head commit; nil when the PR has no checks.
    enum CheckState: String, Codable, Sendable {
        case success = "SUCCESS"
        case failure = "FAILURE"
        case error = "ERROR"
        case pending = "PENDING"
        case expected = "EXPECTED"
    }

    struct Label: Hashable, Codable, Sendable {
        var name: String
        /// 6-digit hex without "#", as returned by the API (e.g. "d73a4a").
        var color: String
    }

    /// A comment or review on the PR, used to derive notifications locally
    /// instead of relying on GitHub's (settings-dependent) notification inbox.
    struct ActivityEvent: Hashable, Codable, Sendable {
        enum Kind: Hashable, Codable, Sendable {
            case comment
            /// Raw review state: APPROVED / CHANGES_REQUESTED / COMMENTED / …
            case review(state: String)
        }
        var kind: Kind
        var author: String
        var createdAt: Date
    }

    var id: String
    var number: Int
    var title: String
    var url: URL
    var repository: String
    var author: String
    var headBranch: String
    var isDraft: Bool
    var isMerged: Bool
    var reviewDecision: ReviewDecision?
    var checkState: CheckState?
    /// GitHub's explicit queue flag. More reliable than inferring from entry state.
    var isInMergeQueue: Bool
    /// Raw `mergeQueueEntry.state` (QUEUED / MERGEABLE / …); nil when the PR is
    /// not sitting in a merge queue. Drives the "left the merge queue" banner.
    var mergeQueueState: String?
    var labels: [Label]
    /// Recent comments + reviews, newest last; drives local notifications.
    var activity: [ActivityEvent]
    var commentCount: Int
    var additions: Int
    var deletions: Int
    var createdAt: Date
    var updatedAt: Date
    /// Nil for open PRs and for merged rows persisted before this field existed.
    var mergedAt: Date? = nil
}

extension String {
    var githubMention: String {
        hasPrefix("@") ? self : "@\(self)"
    }
}
