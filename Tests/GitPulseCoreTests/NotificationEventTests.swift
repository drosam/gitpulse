import Foundation
import Testing
@testable import GitPulseCore

struct NotificationEventTests {
    private let pr = makePR("PR_1", updatedAt: "2026-01-09T00:00:00Z")

    private static func review(_ state: String, by author: String = "octo") -> PullRequest.ActivityEvent {
        PullRequest.ActivityEvent(kind: .review(state: state), author: author, createdAt: date("2026-01-10T00:00:00Z"))
    }

    @Test(arguments: [
        (NotificationEvent.checksFinished(.success), NotificationEvent.Kind.checksPassed, "Checks passed", "ci-PR_1-SUCCESS"),
        (.checksFinished(.failure), .checksFailed, "Checks failed", "ci-PR_1-FAILURE"),
        (.checksFinished(.error), .checksFailed, "Checks failed", "ci-PR_1-ERROR"),
        (.activity(comment(by: "octo", at: "2026-01-10T00:00:00Z")), .commented, "@octo commented", "activity-PR_1-1768003200.0"),
        (.activity(review("APPROVED")), .approved, "@octo approved", "activity-PR_1-1768003200.0"),
        (.activity(review("CHANGES_REQUESTED")), .changesRequested, "@octo requested changes", "activity-PR_1-1768003200.0"),
        (.activity(review("DISMISSED")), .reviewDismissed, "@octo dismissed a review", "activity-PR_1-1768003200.0"),
        (.activity(review("COMMENTED")), .reviewed, "@octo reviewed", "activity-PR_1-1768003200.0"),
        (.reviewRequested, .reviewRequested, "Review requested", "review-request-PR_1"),
        (.leftMergeQueue, .leftMergeQueue, "Removed from the merge queue", "queue-exit-PR_1-1767916800.0"),
        (.merged, .merged, "Merged", "merged-PR_1"),
    ])
    func eventOwnsKindSubtitleAndIdentifier(_ event: NotificationEvent, kind: NotificationEvent.Kind, subtitle: String, identifier: String) {
        #expect(event.kind == kind)
        #expect(event.subtitle == subtitle)
        #expect(event.identifier(for: pr) == identifier)
        #expect(NotificationEvent.Kind(legacySubtitle: subtitle) == kind)
    }

    @MainActor
    @Test func loginContainingAnotherEventsWordKeepsTheCommentIcon() {
        let event = NotificationEvent.activity(comment(by: "merged-bot", at: "2026-01-10T00:00:00Z"))

        #expect(event.kind == .commented)
        #expect(NotificationEvent.Kind(legacySubtitle: event.subtitle) == .commented)
        #expect(UnreadNotificationsView.iconName(for: event.kind) == "text.bubble.fill")
    }

    @Test func unreadRowsSavedWithoutKindStillDecode() throws {
        let saved = Data(#"[{"id":"merged-PR_1","repository":"acme/web","subtitle":"Merged","title":"Ship it","createdAt":0}]"#.utf8)

        let rows = try JSONDecoder().decode([Session.UnreadNotification].self, from: saved)

        #expect(rows.first?.kind == nil)
        #expect(rows.first?.resolvedKind == .merged)
    }
}
