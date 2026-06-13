import AppKit
import UserNotifications

/// Posts macOS notifications for new GitHub activity; clicking one opens
/// the pull request in the browser.
///
/// UNUserNotificationCenter requires a real bundle, so this is inert under
/// `swift run` (bare executable) and active in the installed .app.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private let available = Bundle.main.bundleIdentifier != nil

    func setUp() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
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
