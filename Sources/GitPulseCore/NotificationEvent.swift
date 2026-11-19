import Foundation

/// One change on a pull request that GitPulse announces: it owns the banner
/// subtitle, the unread-row identifier and the icon kind, so `Session`,
/// `Notifier` and the views can't disagree.
enum NotificationEvent: Equatable, Sendable {
    case checksFinished(PullRequest.CheckState)
    case activity(PullRequest.ActivityEvent)
    case reviewRequested
    case leftMergeQueue
    case merged

    /// What happened, persisted with unread rows so icons don't depend on wording.
    enum Kind: String, Codable, Sendable, CaseIterable {
        case checksPassed, checksFailed
        case commented, approved, changesRequested, reviewDismissed, reviewed
        case reviewRequested, leftMergeQueue, merged

        /// The text after `@login` in an activity subtitle, or the whole subtitle.
        var action: String {
            switch self {
            case .checksPassed: "Checks passed"
            case .checksFailed: "Checks failed"
            case .commented: "commented"
            case .approved: "approved"
            case .changesRequested: "requested changes"
            case .reviewDismissed: "dismissed a review"
            case .reviewed: "reviewed"
            case .reviewRequested: "Review requested"
            case .leftMergeQueue: "Removed from the merge queue"
            case .merged: "Merged"
            }
        }

        /// Recovers the kind of an unread row saved before kinds were stored.
        init?(legacySubtitle subtitle: String) {
            var action = Substring(subtitle)
            if action.hasPrefix("@"), let space = action.firstIndex(of: " ") {
                action = action[action.index(after: space)...]
            }
            guard let kind = Self.allCases.first(where: { $0.action == action }) else { return nil }
            self = kind
        }
    }

    var kind: Kind {
        switch self {
        case .checksFinished(let state): state == .success ? .checksPassed : .checksFailed
        case .activity(let event):
            switch event.kind {
            case .comment: .commented
            case .review(state: "APPROVED"): .approved
            case .review(state: "CHANGES_REQUESTED"): .changesRequested
            case .review(state: "DISMISSED"): .reviewDismissed
            case .review: .reviewed
            }
        case .reviewRequested: .reviewRequested
        case .leftMergeQueue: .leftMergeQueue
        case .merged: .merged
        }
    }

    var subtitle: String {
        if case .activity(let event) = self { return "\(event.author.githubMention) \(kind.action)" }
        return kind.action
    }

    /// Stable per occurrence; dedupes unread rows and replaces repeated banners.
    func identifier(for pullRequest: PullRequest) -> String {
        switch self {
        case .checksFinished(let state): "ci-\(pullRequest.id)-\(state.rawValue)"
        case .activity(let event): "activity-\(pullRequest.id)-\(event.createdAt.timeIntervalSince1970)"
        case .reviewRequested: "review-request-\(pullRequest.id)"
        case .leftMergeQueue: "queue-exit-\(pullRequest.id)-\(pullRequest.updatedAt.timeIntervalSince1970)"
        case .merged: "merged-\(pullRequest.id)"
        }
    }

    /// When the change happened, as far as the dashboard knows.
    func date(for pullRequest: PullRequest, now: Date = Date()) -> Date {
        switch self {
        case .activity(let event): event.createdAt
        case .leftMergeQueue, .merged: pullRequest.updatedAt
        case .checksFinished, .reviewRequested: now
        }
    }
}
