import Foundation

struct PullRequest: Identifiable, Hashable, Decodable, Sendable {
    enum ReviewDecision: String, Decodable, Sendable {
        case approved = "APPROVED"
        case changesRequested = "CHANGES_REQUESTED"
        case reviewRequired = "REVIEW_REQUIRED"
    }

    var id: String
    var number: Int
    var title: String
    var url: URL
    var repository: String
    var author: String
    var isDraft: Bool
    var reviewDecision: ReviewDecision?
    var additions: Int
    var deletions: Int
    var updatedAt: Date
}
