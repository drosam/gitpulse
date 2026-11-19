import AppKit
import Observation
import UserNotifications

/// Banner sink used by `Session`; `Notifier` is the live implementation.
@MainActor
protocol NotificationPosting: AnyObject {
    /// Shows a banner for `event`; the caller has already recorded the unread row.
    func post(_ event: NotificationEvent, for pullRequest: PullRequest)
    /// Called with the PR URL after the user opens it from a banner.
    var onOpenPullRequest: (@MainActor (URL) -> Void)? { get set }
}

/// Posts macOS notifications for new GitHub activity; clicking one opens
/// the pull request in the browser.
///
/// UNUserNotificationCenter requires a real bundle, so this is inert under
/// `swift run` (bare executable) and active in the installed .app.
@Observable
@MainActor
public final class Notifier: NSObject, UNUserNotificationCenterDelegate, NotificationPosting {
    public static let shared = Notifier()

    @ObservationIgnored private let available = Bundle.main.bundleIdentifier != nil
    @ObservationIgnored private let settings = AppSettings.shared
    @ObservationIgnored var onOpenPullRequest: (@MainActor (URL) -> Void)?

    /// True when the user has denied notification permission, so banners are
    /// silently dropped by the system. Surfaced in the UI so it isn't a mystery.
    private(set) var authorizationDenied = false

    public func setUp() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, _ in
            Task { @MainActor in self?.refreshAuthorizationStatus() }
        }
    }

    /// Re-reads the system authorization status; call on launch and whenever
    /// the app reactivates (the user may have flipped it in System Settings).
    public func refreshAuthorizationStatus() {
        guard available else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let denied = settings.authorizationStatus == .denied
            Task { @MainActor in self?.authorizationDenied = denied }
        }
    }

    func post(_ event: NotificationEvent, for pullRequest: PullRequest) {
        guard available, settings.showNotificationBanners else { return }
        let content = UNMutableNotificationContent()
        content.title = pullRequest.repository
        content.subtitle = event.subtitle
        content.body = pullRequest.title
        content.sound = settings.playNotificationSounds ? .default : nil
        content.userInfo = ["url": pullRequest.url.absoluteString]
        let request = UNNotificationRequest(
            identifier: event.identifier(for: pullRequest),
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    public nonisolated func userNotificationCenter(
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

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let string = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: string),
              SafeURL.isAllowed(url) else { return }
        await MainActor.run {
            NSWorkspace.shared.open(url)
            onOpenPullRequest?(url)
        }
    }
}
