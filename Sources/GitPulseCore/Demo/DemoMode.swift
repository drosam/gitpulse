import Foundation

/// `--demo` launch mode: fictional data, no network, no Keychain, no notifications,
/// and preferences isolated from the real app.
public enum DemoMode {
    public static var isEnabled: Bool {
        CommandLine.arguments.contains("--demo")
    }

    static let defaultsSuite = "dev.davidrosa.gitpulse.demo"

    @MainActor
    /// `defaults` lets tests keep out of the real demo preferences.
    public static func makeSessionAndSettings(now: Date = Date(), defaults: UserDefaults? = nil) -> (Session, AppSettings) {
        let defaults = defaults ?? UserDefaults(suiteName: defaultsSuite)!
        defaults.removePersistentDomain(forName: defaultsSuite)
        seed(defaults, now: now)

        let settings = AppSettings(defaults: defaults)
        let session = Session(
            settings: settings,
            defaults: defaults,
            dependencies: Session.Dependencies(
                notifier: SilentNotifier(),
                dashboardSource: DemoDashboardSource(dashboard: DemoData.dashboard(now: now)),
                tokens: TokenProvider(resolve: { ResolvedToken(token: "demo", source: .keychain) }, save: { _ in true }, clear: { true }),
                deviceFlow: DeviceFlow(transport: { _ in throw SignInUnavailable() }),
                setDockBadge: { _ in }
            )
        )
        return (session, settings)
    }

    @MainActor
    private static func seed(_ defaults: UserDefaults, now: Date) {
        let notifications = DemoData.unreadNotifications(now: now)
        let encoder = JSONEncoder()
        let pending = DemoData.pendingMerged(now: now)
        let values: [String: Data?] = [
            Session.unreadKey: try? encoder.encode(Set(notifications.keys)),
            Session.unreadNotificationsKey: try? encoder.encode(Dictionary(uniqueKeysWithValues: notifications.map { ($0.key.absoluteString, $0.value) })),
            Session.pendingMergedPullRequestsKey: try? encoder.encode(pending),
            Session.mergedKey: try? encoder.encode(Set(pending.map(\.id))),
        ]
        for case let (key, data?) in values {
            defaults.set(data, forKey: key)
        }
    }
}

/// Keeps demo mode offline if someone signs out and tries to sign in.
struct SignInUnavailable: LocalizedError {
    var errorDescription: String? { "Sign-in isn't available in demo mode. Relaunch GitPulse without --demo." }
}

struct DemoDashboardSource: DashboardSource {
    var dashboard: Dashboard

    func fetchDashboard(token: String, repositories: [String], trackedPullRequestIDs: [PullRequest.ID]) async throws -> Dashboard {
        dashboard
    }
}

@MainActor
final class SilentNotifier: NotificationPosting {
    var onOpenPullRequest: (@MainActor (URL) -> Void)?
    func postCheckResult(for pullRequest: PullRequest, passed: Bool) {}
    func postActivity(for pullRequest: PullRequest, event: PullRequest.ActivityEvent) {}
    func postMerged(for pullRequest: PullRequest) {}
    func postMergeQueueExit(for pullRequest: PullRequest) {}
    func postReviewRequest(for pullRequest: PullRequest) {}
}
