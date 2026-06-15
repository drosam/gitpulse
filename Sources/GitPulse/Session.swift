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
    /// PR html URLs with unacknowledged activity (a new comment, review, or
    /// review request). Drives the menubar dot, dock badge, and per-row dot.
    /// Persisted, and cleared for a PR when the user opens it.
    private var unreadURLs: Set<URL> = []
    private var token: String?
    private var autoRefreshTask: Task<Void, Never>?
    /// Last seen head-commit check state per PR, to detect CI finishing.
    private var lastCheckState: [PullRequest.ID: PullRequest.CheckState] = [:]
    private var hasSeededChecks = false
    /// Newest activity timestamp seen per PR, to detect new comments/reviews.
    /// Persisted, so activity that arrives while the app is closed banners once
    /// on the next launch. A PR with no entry yet seeds silently.
    private var lastActivityAt: [PullRequest.ID: Date] = [:]
    /// PRs currently asking for your review, to banner ones that newly appear.
    private var knownReviewRequestIDs: Set<PullRequest.ID> = []
    private var hasSeededReviewRequests = false

    private static let autoRefreshInterval: Duration = .seconds(60)
    private static let activityKey = "lastActivityAt"
    private static let unreadKey = "unreadURLs"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.activityKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            lastActivityAt = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.unreadKey),
           let decoded = try? JSONDecoder().decode(Set<URL>.self, from: data) {
            unreadURLs = decoded
        }
    }

    var hasUnread: Bool { !unreadURLs.isEmpty }

    /// PR html URLs with unacknowledged activity, for the per-row dot.
    var unreadPRURLs: Set<URL> { unreadURLs }

    func start() async {
        guard let resolved = TokenStore.resolve() else {
            state = .signedOut
            return
        }
        token = resolved
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
            processActivity(in: dashboard)
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
            await refresh()
            startAutoRefresh()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func signOut() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        lastActivityAt = [:]
        lastCheckState = [:]
        knownReviewRequestIDs = []
        hasSeededReviewRequests = false
        hasSeededChecks = false
        unreadURLs = []
        UserDefaults.standard.removeObject(forKey: Self.activityKey)
        UserDefaults.standard.removeObject(forKey: Self.unreadKey)
        updateDockBadge()
        TokenStore.clear()
        token = nil
        state = .signedOut
    }

    /// Called when the user opens a PR: clear its unread mark.
    func markRead(prURL: URL) {
        guard unreadURLs.remove(prURL) != nil else { return }
        updateDockBadge()
        saveNotificationState()
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
            processActivity(in: dashboard)
            state = .ready(dashboard)
        }
    }

    /// Derives all local notifications from the dashboard — CI results, new
    /// comments/reviews, and new review requests — then prunes per-PR state for
    /// PRs that have left the dashboard. Scoped to the PRs shown in the app, so
    /// it never touches the whole-repo firehose and works regardless of the
    /// user's GitHub notification routing.
    private func processActivity(in dashboard: Dashboard) {
        detectFinishedChecks(in: dashboard)
        detectNewActivity(in: dashboard)
        detectNewReviewRequests(in: dashboard)
        pruneState(keeping: dashboard)
        saveNotificationState()
    }

    /// Posts a banner when a dashboard PR's checks transition to a finished
    /// state (passed / failed). The first pass after launch seeds silently so
    /// we don't blast banners for old results.
    private func detectFinishedChecks(in dashboard: Dashboard) {
        let prs = dashboard.myPRs + dashboard.reviewRequests
        for pr in prs {
            guard let state = pr.checkState else { continue }
            let previous = lastCheckState[pr.id]
            lastCheckState[pr.id] = state
            let finished = state == .success || state == .failure || state == .error
            guard hasSeededChecks, finished, state != previous else { continue }
            Notifier.shared.postCheckResult(for: pr, passed: state == .success)
            unreadURLs.insert(pr.url)
        }
        hasSeededChecks = true
    }

    /// Posts a banner for each comment or review newer than the last one we saw
    /// on that PR (skipping your own). A PR with no recorded cursor seeds
    /// silently — covers both first launch and a PR newly entering the app.
    private func detectNewActivity(in dashboard: Dashboard) {
        let prs = dashboard.myPRs + dashboard.reviewRequests
        for pr in prs {
            guard let newest = pr.activity.last?.createdAt else { continue }
            if let cursor = lastActivityAt[pr.id] {
                for event in pr.activity where event.createdAt > cursor && event.author != dashboard.viewer {
                    Notifier.shared.postActivity(for: pr, event: event)
                    unreadURLs.insert(pr.url)
                }
            }
            lastActivityAt[pr.id] = max(lastActivityAt[pr.id] ?? .distantPast, newest)
        }
    }

    /// Posts a banner when a PR newly appears in the review-requested pane.
    /// Settings-independent replacement for the inbox review notification.
    private func detectNewReviewRequests(in dashboard: Dashboard) {
        let ids = Set(dashboard.reviewRequests.map(\.id))
        if hasSeededReviewRequests {
            for pr in dashboard.reviewRequests where !knownReviewRequestIDs.contains(pr.id) {
                Notifier.shared.postReviewRequest(for: pr)
                unreadURLs.insert(pr.url)
            }
        }
        knownReviewRequestIDs = ids
        hasSeededReviewRequests = true
    }

    /// Drops per-PR tracking state for PRs no longer shown in the app, so the
    /// maps don't grow without bound as PRs are merged/closed.
    private func pruneState(keeping dashboard: Dashboard) {
        let prs = dashboard.myPRs + dashboard.reviewRequests
        let currentIDs = Set(prs.map(\.id))
        let currentURLs = Set(prs.map(\.url))
        lastCheckState = lastCheckState.filter { currentIDs.contains($0.key) }
        lastActivityAt = lastActivityAt.filter { currentIDs.contains($0.key) }
        unreadURLs = unreadURLs.filter { currentURLs.contains($0) }
        updateDockBadge()
    }

    private func saveNotificationState() {
        if let data = try? JSONEncoder().encode(lastActivityAt) {
            UserDefaults.standard.set(data, forKey: Self.activityKey)
        }
        if let data = try? JSONEncoder().encode(unreadURLs) {
            UserDefaults.standard.set(data, forKey: Self.unreadKey)
        }
    }

    private func updateDockBadge() {
        NSApp.dockTile.badgeLabel = unreadURLs.isEmpty ? nil : "\(unreadURLs.count)"
    }
}
