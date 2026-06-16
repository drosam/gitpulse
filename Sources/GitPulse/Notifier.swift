import AppKit
import Observation
import UserNotifications

/// Posts macOS notifications for new GitHub activity; clicking one opens
/// the pull request in the browser.
///
/// UNUserNotificationCenter requires a real bundle, so this is inert under
/// `swift run` (bare executable) and active in the installed .app.
@Observable
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    @ObservationIgnored private let available = Bundle.main.bundleIdentifier != nil
    @ObservationIgnored private let settings = AppSettings.shared

    /// True when the user has denied notification permission, so banners are
    /// silently dropped by the system. Surfaced in the UI so it isn't a mystery.
    private(set) var authorizationDenied = false

    func setUp() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, _ in
            Task { @MainActor in self?.refreshAuthorizationStatus() }
        }
    }

    /// Re-reads the system authorization status; call on launch and whenever
    /// the app reactivates (the user may have flipped it in System Settings).
    func refreshAuthorizationStatus() {
        guard available else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let denied = settings.authorizationStatus == .denied
            Task { @MainActor in self?.authorizationDenied = denied }
        }
    }

    /// Banner for a PR whose checks just finished. Scoped to dashboard PRs by
    /// the caller; not a GitHub notification thread, so it doesn't touch the
    /// unread dot/badge.
    func postCheckResult(for pullRequest: PullRequest, passed: Bool) {
        guard available, settings.showNotificationBanners else { return }
        let content = UNMutableNotificationContent()
        content.title = pullRequest.repository
        content.subtitle = passed ? "Checks passed" : "Checks failed"
        content.body = pullRequest.title
        content.sound = settings.playNotificationSounds ? .default : nil
        content.userInfo = ["url": pullRequest.url.absoluteString]
        let request = UNNotificationRequest(
            identifier: "ci-\(pullRequest.id)-\(passed)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Banner for a new comment or review on a dashboard PR. Derived locally
    /// from the dashboard's activity, so it works regardless of the user's
    /// GitHub notification routing.
    func postActivity(for pullRequest: PullRequest, event: PullRequest.ActivityEvent) {
        guard available, settings.showNotificationBanners else { return }
        let action: String
        switch event.kind {
        case .comment:
            action = "commented"
        case .review(let state):
            switch state {
            case "APPROVED": action = "approved"
            case "CHANGES_REQUESTED": action = "requested changes"
            case "DISMISSED": action = "dismissed a review"
            default: action = "reviewed"
            }
        }
        let content = UNMutableNotificationContent()
        content.title = pullRequest.repository
        content.subtitle = "\(event.author.githubMention) \(action)"
        content.body = pullRequest.title
        content.sound = settings.playNotificationSounds ? .default : nil
        content.userInfo = ["url": pullRequest.url.absoluteString]
        let request = UNNotificationRequest(
            identifier: "activity-\(pullRequest.id)-\(event.createdAt.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Banner for one of your PRs that just merged. Derived from the merged
    /// search, not the inbox; the PR has left the open panes by now.
    func postMerged(for pullRequest: PullRequest) {
        guard available, settings.showNotificationBanners else { return }
        let content = UNMutableNotificationContent()
        content.title = pullRequest.repository
        content.subtitle = "Merged"
        content.body = pullRequest.title
        content.sound = settings.playNotificationSounds ? .default : nil
        content.userInfo = ["url": pullRequest.url.absoluteString]
        let request = UNNotificationRequest(
            identifier: "merged-\(pullRequest.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Banner for a PR that dropped out of the merge queue while still open
    /// (kicked for a conflict, failed required check, base moved, manual remove).
    func postMergeQueueExit(for pullRequest: PullRequest) {
        guard available, settings.showNotificationBanners else { return }
        let content = UNMutableNotificationContent()
        content.title = pullRequest.repository
        content.subtitle = "Removed from the merge queue"
        content.body = pullRequest.title
        content.sound = settings.playNotificationSounds ? .default : nil
        content.userInfo = ["url": pullRequest.url.absoluteString]
        let request = UNNotificationRequest(
            identifier: "queue-exit-\(pullRequest.id)-\(pullRequest.updatedAt.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Banner for a PR you were just asked to review. Derived from the review
    /// pane entering the dashboard, not the notification inbox.
    func postReviewRequest(for pullRequest: PullRequest) {
        guard available, settings.showNotificationBanners else { return }
        let content = UNMutableNotificationContent()
        content.title = pullRequest.repository
        content.subtitle = "Review requested"
        content.body = pullRequest.title
        content.sound = settings.playNotificationSounds ? .default : nil
        content.userInfo = ["url": pullRequest.url.absoluteString]
        let request = UNNotificationRequest(
            identifier: "review-request-\(pullRequest.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run {
            var options: UNNotificationPresentationOptions = []
            if settings.showNotificationBanners { options.insert(.banner) }
            if settings.playNotificationSounds { options.insert(.sound) }
            return options
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let string = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: string) else { return }
        _ = await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }
}
