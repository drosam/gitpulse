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

    func post(_ notification: PRNotification) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = notification.repository
        content.subtitle = notification.reason.replacingOccurrences(of: "_", with: " ")
        content.body = notification.title
        content.sound = .default
        content.userInfo = ["url": notification.prURL.absoluteString]
        // Thread id + timestamp: a re-updated thread notifies again.
        let request = UNNotificationRequest(
            identifier: "\(notification.id)-\(notification.updatedAt.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Banner for a PR whose checks just finished. Scoped to dashboard PRs by
    /// the caller; not a GitHub notification thread, so it doesn't touch the
    /// unread dot/badge.
    func postCheckResult(for pullRequest: PullRequest, passed: Bool) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = pullRequest.repository
        content.subtitle = passed ? "Checks passed" : "Checks failed"
        content.body = pullRequest.title
        content.sound = .default
        content.userInfo = ["url": pullRequest.url.absoluteString]
        let request = UNNotificationRequest(
            identifier: "ci-\(pullRequest.id)-\(passed)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
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
