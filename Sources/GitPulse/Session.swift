import AppKit
import SwiftUI

@Observable
@MainActor
final class Session {
    enum State {
        case signedOut
        case authorizing(DeviceFlow.Authorization)
        case loading
        case ready(Dashboard)
        case failed(String)
    }

    private(set) var state: State = .signedOut
    private(set) var isRefreshing = false
    /// Unread PR notifications from GitHub's notifications API.
    private(set) var notifications: [PRNotification] = []
    private var token: String?
    private var autoRefreshTask: Task<Void, Never>?
    private var notificationPollTask: Task<Void, Never>?
    private var notificationsETag: String?
    private var seenNotifications: [String: Date] = [:]
    private var hasSeededNotifications = false
    /// Last seen head-commit check state per PR, to detect CI finishing.
    private var lastCheckState: [PullRequest.ID: PullRequest.CheckState] = [:]
    private var hasSeededChecks = false

    private static let autoRefreshInterval: Duration = .seconds(60)
    private static let seenKey = "seenNotifications"
    private static let seededKey = "hasSeededNotifications"

    init() {
        hasSeededNotifications = UserDefaults.standard.bool(forKey: Self.seededKey)
        if let data = UserDefaults.standard.data(forKey: Self.seenKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            seenNotifications = decoded
        }
    }

    var hasUnread: Bool { !notifications.isEmpty }

    /// PR html URLs with a pending notification, for the per-row dot.
    var unreadPRURLs: Set<URL> { Set(notifications.map(\.prURL)) }

    func start() async {
        guard let resolved = TokenStore.resolve() else {
            state = .signedOut
            return
        }
        token = resolved
        startNotificationPolling()
        await refresh()
        startAutoRefresh()
    }

    func refresh() async {
        guard let token else { return }
        if case .ready = state {} else { state = .loading }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let dashboard = try await GitHubClient(token: token).fetchDashboard()
            detectFinishedChecks(in: dashboard)
            state = .ready(dashboard)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func signIn() async {
        do {
            let authorization = try await DeviceFlow.requestCode()
            state = .authorizing(authorization)
            let newToken = try await DeviceFlow.pollForToken(authorization)
            TokenStore.save(newToken)
            token = newToken
            startNotificationPolling()
            await refresh()
            startAutoRefresh()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func signOut() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        notificationPollTask?.cancel()
        notificationPollTask = nil
        notificationsETag = nil
        seenNotifications = [:]
        hasSeededNotifications = false
        UserDefaults.standard.removeObject(forKey: Self.seenKey)
        UserDefaults.standard.removeObject(forKey: Self.seededKey)
        notifications = []
        updateDockBadge()
        TokenStore.clear()
        token = nil
        state = .signedOut
    }

    /// Called when the user opens a PR: clear its dot immediately and tell
    /// GitHub the threads are read (best-effort; the next poll re-syncs).
    func markRead(prURL: URL) {
        let matching = notifications.filter { $0.prURL == prURL }
        guard !matching.isEmpty, let token else { return }
        notifications.removeAll { $0.prURL == prURL }
        updateDockBadge()
        let client = NotificationsClient(token: token)
        Task {
            for notification in matching {
                await client.markRead(threadID: notification.id)
            }
        }
    }

    // MARK: - Auto-refresh

    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Session.autoRefreshInterval)
                guard !Task.isCancelled else { return }
                await self?.backgroundRefresh()
            }
        }
    }

    /// Unlike `refresh()`, keeps the current dashboard if the fetch fails,
    /// so a transient network error never replaces data with an error screen.
    private func backgroundRefresh() async {
        guard let token else { return }
        if let dashboard = try? await GitHubClient(token: token).fetchDashboard() {
            detectFinishedChecks(in: dashboard)
            state = .ready(dashboard)
        }
    }

    /// Posts a banner when a dashboard PR's checks transition to a finished
    /// state (passed / failed). Scoped to the PRs shown in the app — your PRs
    /// and review requests — never the whole-repo CI firehose. The first pass
    /// after launch seeds silently so we don't blast banners for old results.
    private func detectFinishedChecks(in dashboard: Dashboard) {
        let prs = dashboard.myPRs + dashboard.reviewRequests
        for pr in prs {
            guard let state = pr.checkState else { continue }
            let previous = lastCheckState[pr.id]
            lastCheckState[pr.id] = state
            let finished = state == .success || state == .failure || state == .error
            guard hasSeededChecks, finished, state != previous else { continue }
            Notifier.shared.postCheckResult(for: pr, passed: state == .success)
        }
        hasSeededChecks = true
    }

    // MARK: - Notifications

    private func startNotificationPolling() {
        notificationPollTask?.cancel()
        notificationPollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = await self?.pollNotifications() ?? 60
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// One poll; returns how many seconds to wait before the next one.
    private func pollNotifications() async -> Int {
        guard let token else { return 60 }
        do {
            let result = try await NotificationsClient(token: token).fetch(etag: notificationsETag)
            notificationsETag = result.etag
            if let fetched = result.notifications {
                apply(fetched)
            }
            return max(result.pollInterval, 60)
        } catch {
            return 60 // transient failure: keep showing what we had
        }
    }

    private func apply(_ fetched: [PRNotification]) {
        let fresh = fetched.filter { notification in
            guard let seenAt = seenNotifications[notification.id] else { return true }
            return notification.updatedAt > seenAt
        }
        // The first poll seeds silently — don't blast banners for old unread.
        if hasSeededNotifications {
            for notification in fresh {
                Notifier.shared.post(notification)
            }
        }
        hasSeededNotifications = true
        for notification in fetched {
            seenNotifications[notification.id] = notification.updatedAt
        }
        notifications = fetched
        updateDockBadge()
        saveNotificationState()
    }

    private func saveNotificationState() {
        UserDefaults.standard.set(hasSeededNotifications, forKey: Self.seededKey)
        if let data = try? JSONEncoder().encode(seenNotifications) {
            UserDefaults.standard.set(data, forKey: Self.seenKey)
        }
    }

    private func updateDockBadge() {
        NSApp.dockTile.badgeLabel = notifications.isEmpty ? nil : "\(notifications.count)"
    }
}
