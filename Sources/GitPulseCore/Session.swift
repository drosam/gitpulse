import AppKit
import SwiftUI

@Observable
@MainActor
public final class Session {
    /// External effects `Session` depends on; `.live` in the app, fakes in tests and demo mode.
    struct Dependencies {
        var notifier: any NotificationPosting
        var dashboardSource: any DashboardSource
        var tokens: TokenProvider
        var deviceFlow: DeviceFlow
        var setDockBadge: @MainActor (String?) -> Void

        @MainActor static var live: Dependencies {
            Dependencies(
                notifier: Notifier.shared,
                dashboardSource: GitHubDashboardSource(),
                tokens: .keychain,
                deviceFlow: DeviceFlow(),
                setDockBadge: { NSApp.dockTile.badgeLabel = $0 }
            )
        }
    }

    struct HiddenPullRequest: Identifiable, Codable, Hashable {
        var url: URL
        var title: String
        var repository: String
        var number: Int

        var id: URL { url }
    }

    struct UnreadNotification: Identifiable, Codable, Hashable {
        var id: String
        var repository: String
        var subtitle: String
        var title: String
        var createdAt: Date
    }

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
    private var unreadNotifications: [String: [UnreadNotification]] = [:]
    private(set) var hiddenPullRequests: [HiddenPullRequest] = []
    private var pendingMergedPullRequests: [PullRequest] = []
    private var lastMyPullRequestIDs: Set<PullRequest.ID> = []
    private var token: String?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let dependencies: Dependencies
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
    /// PRs currently sitting in a merge queue, to banner ones that drop out
    /// while still open. Recomputed each pass, so it needs no separate pruning.
    private var prsInMergeQueue: Set<PullRequest.ID> = []
    private var hasSeededMergeQueue = false
    /// IDs of recently merged PRs we've already bannered. Persisted, so a merge
    /// that lands while the app is closed banners once on the next launch.
    private var knownMergedIDs: Set<PullRequest.ID> = []
    private var hasSeededMerged = false

    private static let autoRefreshInterval: Duration = .seconds(60)
    private static let activityKey = "lastActivityAt"
    static let unreadKey = "unreadURLs"
    static let unreadNotificationsKey = "unreadNotifications"
    static let mergedKey = "knownMergedIDs"
    static let pendingMergedPullRequestsKey = "pendingMergedPullRequests"
    private static let lastMyPullRequestIDsKey = "lastMyPullRequestIDs"
    private static let hiddenPullRequestsKey = "hiddenPullRequests"

    public convenience init() {
        self.init(settings: .shared, defaults: .standard, dependencies: .live)
    }

    init(settings: AppSettings, defaults: UserDefaults, dependencies: Dependencies) {
        self.settings = settings
        self.defaults = defaults
        self.dependencies = dependencies
        if let data = defaults.data(forKey: Self.activityKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            lastActivityAt = decoded
        }
        if let data = defaults.data(forKey: Self.unreadKey),
           let decoded = try? JSONDecoder().decode(Set<URL>.self, from: data) {
            unreadURLs = decoded
        }
        if let data = defaults.data(forKey: Self.unreadNotificationsKey),
           let decoded = try? JSONDecoder().decode([String: [UnreadNotification]].self, from: data) {
            unreadNotifications = decoded
        }
        if let data = defaults.data(forKey: Self.hiddenPullRequestsKey),
           let decoded = try? JSONDecoder().decode([HiddenPullRequest].self, from: data) {
            hiddenPullRequests = decoded
        }
        if let data = defaults.data(forKey: Self.pendingMergedPullRequestsKey),
           let decoded = try? JSONDecoder().decode([PullRequest].self, from: data) {
            pendingMergedPullRequests = decoded
        }
        if let data = defaults.data(forKey: Self.lastMyPullRequestIDsKey),
           let decoded = try? JSONDecoder().decode(Set<PullRequest.ID>.self, from: data) {
            lastMyPullRequestIDs = decoded
        }
        // A persisted set means a prior run already seeded; banner anything new
        // on the first refresh. A fresh install seeds silently instead.
        if let data = defaults.data(forKey: Self.mergedKey),
           let decoded = try? JSONDecoder().decode(Set<PullRequest.ID>.self, from: data) {
            knownMergedIDs = decoded
            hasSeededMerged = true
        }
    }

    public var hasUnread: Bool { !visibleUnreadURLs.isEmpty }

    /// PR html URLs with unacknowledged activity, for the per-row dot.
    var unreadPRURLs: Set<URL> { unreadURLs }
    var unreadNotificationsByURL: [URL: [UnreadNotification]] {
        Dictionary(uniqueKeysWithValues: unreadNotifications.compactMap { key, value in
            guard let url = URL(string: key) else { return nil }
            return (url, value)
        })
    }
    var hiddenPRURLs: Set<URL> { Set(hiddenPullRequests.map(\.url)) }

    private var visibleUnreadURLs: Set<URL> {
        unreadURLs.subtracting(hiddenPRURLs)
    }

    public func start() async {
        guard let resolved = dependencies.tokens.resolve() else {
            state = .signedOut
            return
        }
        token = resolved
        await refresh()
        startAutoRefresh()
    }

    public func refresh() async {
        guard let token else { return }
        if case .ready = state {} else { state = .loading }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let dashboard = try await fetchDashboard(token: token)
            processActivity(in: dashboard)
            state = .ready(displayDashboard(dashboard))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func signIn() async {
        do {
            let authorization = try await dependencies.deviceFlow.requestCode()
            state = .authorizing(authorization)
            let newToken = try await dependencies.deviceFlow.pollForToken(authorization)
            dependencies.tokens.save(newToken)
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
        prsInMergeQueue = []
        hasSeededMergeQueue = false
        knownMergedIDs = []
        hasSeededMerged = false
        unreadURLs = []
        unreadNotifications = [:]
        hiddenPullRequests = []
        pendingMergedPullRequests = []
        lastMyPullRequestIDs = []
        defaults.removeObject(forKey: Self.activityKey)
        defaults.removeObject(forKey: Self.unreadKey)
        defaults.removeObject(forKey: Self.unreadNotificationsKey)
        defaults.removeObject(forKey: Self.mergedKey)
        defaults.removeObject(forKey: Self.pendingMergedPullRequestsKey)
        defaults.removeObject(forKey: Self.lastMyPullRequestIDsKey)
        defaults.removeObject(forKey: Self.hiddenPullRequestsKey)
        updateDockBadge()
        dependencies.tokens.clear()
        token = nil
        state = .signedOut
    }

    /// Called when the user opens a PR: clear its unread mark.
    func markRead(prURL: URL) {
        let removedUnread = unreadURLs.remove(prURL) != nil
        unreadNotifications.removeValue(forKey: prURL.absoluteString)
        let removedMerged = pendingMergedPullRequests.contains { $0.url == prURL }
        pendingMergedPullRequests.removeAll { $0.url == prURL }
        guard removedUnread || removedMerged else { return }
        updateDockBadge()
        saveNotificationState()
        if removedMerged, case .ready(let dashboard) = state {
            state = .ready(Dashboard(
                viewer: dashboard.viewer,
                myPRs: dashboard.myPRs.filter { $0.url != prURL },
                reviewRequests: dashboard.reviewRequests,
                recentlyMerged: dashboard.recentlyMerged
            ))
        } else {
            applyHiddenDisplayToCurrentState()
        }
    }

    func applySettingsChanged(refresh: Bool = false) async {
        updateDockBadge()
        if refresh {
            await self.refresh()
        }
    }

    func hide(_ pullRequest: PullRequest) {
        let hidden = HiddenPullRequest(
            url: pullRequest.url,
            title: pullRequest.title,
            repository: pullRequest.repository,
            number: pullRequest.number
        )
        hiddenPullRequests.removeAll { $0.url == pullRequest.url }
        hiddenPullRequests.append(hidden)
        unreadURLs.remove(pullRequest.url)
        unreadNotifications.removeValue(forKey: pullRequest.url.absoluteString)
        saveHiddenPullRequests()
        saveNotificationState()
        applyHiddenDisplayToCurrentState()
    }

    func unhide(_ hiddenPullRequest: HiddenPullRequest) async {
        await unhide(url: hiddenPullRequest.url)
    }

    func unhide(url: URL) async {
        hiddenPullRequests.removeAll { $0.url == url }
        saveHiddenPullRequests()
        await refresh()
    }

    func unhideAll() async {
        hiddenPullRequests = []
        saveHiddenPullRequests()
        await refresh()
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
    func backgroundRefresh() async {
        guard let token else { return }
        if let dashboard = try? await fetchDashboard(token: token) {
            processActivity(in: dashboard)
            state = .ready(displayDashboard(dashboard))
        }
    }

    private func fetchDashboard(token: String) async throws -> Dashboard {
        try await dependencies.dashboardSource.fetchDashboard(
            token: token,
            repositories: settings.activeRepositories,
            trackedPullRequestIDs: Array(lastMyPullRequestIDs)
        )
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
        detectMergeQueueExits(in: dashboard)
        detectMergedPRs(in: dashboard)
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
            recordUnread(pr, subtitle: state == .success ? "Checks passed" : "Checks failed", id: "ci-\(pr.id)-\(state.rawValue)")
            if !isHidden(pr) {
                dependencies.notifier.postCheckResult(for: pr, passed: state == .success)
            }
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
                    recordUnread(pr, subtitle: activitySubtitle(for: event), id: "activity-\(pr.id)-\(event.createdAt.timeIntervalSince1970)", createdAt: event.createdAt)
                    if !isHidden(pr) {
                        dependencies.notifier.postActivity(for: pr, event: event)
                    }
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
                recordUnread(pr, subtitle: "Review requested", id: "review-request-\(pr.id)")
                if !isHidden(pr) {
                    dependencies.notifier.postReviewRequest(for: pr)
                }
            }
        }
        knownReviewRequestIDs = ids
        hasSeededReviewRequests = true
    }

    /// Posts a banner when an open PR drops out of the merge queue (kicked for a
    /// conflict, failed check, moved base, or manual removal). A clean merge
    /// removes the PR from the open searches entirely, so it leaves `myPRs` and
    /// never reaches here — that path is handled by `detectMergedPRs`.
    private func detectMergeQueueExits(in dashboard: Dashboard) {
        let prs = dashboard.myPRs + dashboard.reviewRequests
        if hasSeededMergeQueue {
            for pr in prs where prsInMergeQueue.contains(pr.id) && !pr.isInMergeQueue && pr.mergeQueueState == nil {
                recordUnread(pr, subtitle: "Removed from the merge queue", id: "queue-exit-\(pr.id)-\(pr.updatedAt.timeIntervalSince1970)", createdAt: pr.updatedAt)
                if !isHidden(pr) {
                    dependencies.notifier.postMergeQueueExit(for: pr)
                }
            }
        }
        prsInMergeQueue = Set(prs.filter { $0.isInMergeQueue || $0.mergeQueueState != nil }.map(\.id))
        hasSeededMergeQueue = true
    }

    /// Posts a banner for each newly merged PR you authored or were assigned to.
    /// Keeps merged PRs as unread rows in My pull requests until opened.
    private func detectMergedPRs(in dashboard: Dashboard) {
        let ids = Set(dashboard.recentlyMerged.map(\.id))
        if hasSeededMerged {
            for pr in dashboard.recentlyMerged where !knownMergedIDs.contains(pr.id) && !isHidden(pr) {
                recordUnread(pr, subtitle: "Merged", id: "merged-\(pr.id)", createdAt: pr.updatedAt)
                pendingMergedPullRequests.removeAll { $0.id == pr.id }
                pendingMergedPullRequests.append(pr)
                dependencies.notifier.postMerged(for: pr)
            }
        }
        knownMergedIDs.formUnion(ids)
        lastMyPullRequestIDs = Set(dashboard.myPRs.map(\.id))
        hasSeededMerged = true
    }

    /// Drops per-PR tracking state for PRs no longer shown in the app, so the
    /// maps don't grow without bound as PRs are merged/closed.
    private func pruneState(keeping dashboard: Dashboard) {
        let prs = dashboard.myPRs + dashboard.reviewRequests + pendingMergedPullRequests
        let currentIDs = Set(prs.map(\.id))
        let currentURLs = Set(prs.map(\.url))
        lastCheckState = lastCheckState.filter { currentIDs.contains($0.key) }
        lastActivityAt = lastActivityAt.filter { currentIDs.contains($0.key) }
        unreadURLs = unreadURLs.filter { currentURLs.contains($0) }
        unreadNotifications = unreadNotifications.filter { key, _ in
            guard let url = URL(string: key) else { return false }
            return currentURLs.contains(url)
        }
        updateDockBadge()
    }

    private func isHidden(_ pullRequest: PullRequest) -> Bool {
        hiddenPRURLs.contains(pullRequest.url)
    }

    private func recordUnread(_ pullRequest: PullRequest, subtitle: String, id: String, createdAt: Date = Date()) {
        unreadURLs.insert(pullRequest.url)
        let notification = UnreadNotification(
            id: id,
            repository: pullRequest.repository,
            subtitle: subtitle,
            title: pullRequest.title,
            createdAt: createdAt
        )
        let key = pullRequest.url.absoluteString
        var notifications = unreadNotifications[key] ?? []
        notifications.removeAll { $0.id == id }
        notifications.append(notification)
        unreadNotifications[key] = notifications.sorted { $0.createdAt > $1.createdAt }
    }

    private func activitySubtitle(for event: PullRequest.ActivityEvent) -> String {
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
        return "\(event.author.githubMention) \(action)"
    }

    private func applyHiddenDisplayToCurrentState() {
        guard case .ready(let dashboard) = state else { return }
        state = .ready(displayDashboard(dashboard))
    }

    private func displayDashboard(_ dashboard: Dashboard) -> Dashboard {
        Dashboard(
            viewer: dashboard.viewer,
            myPRs: displayPullRequests(mergedRows(in: dashboard)),
            reviewRequests: displayPullRequests(dashboard.reviewRequests),
            recentlyMerged: dashboard.recentlyMerged
        )
    }

    private func displayPullRequests(_ pullRequests: [PullRequest]) -> [PullRequest] {
        let sorted = sortPullRequests(pullRequests)
        if settings.showHiddenPullRequests {
            return sorted.filter { !isHidden($0) } + sorted.filter { isHidden($0) }
        }
        return sorted.filter { !isHidden($0) }
    }

    private func sortPullRequests(_ pullRequests: [PullRequest]) -> [PullRequest] {
        switch settings.pullRequestSort {
        case .createdAtNewest:
            return pullRequests.sorted { $0.createdAt > $1.createdAt }
        case .updatedAtNewest:
            return pullRequests.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func mergedRows(in dashboard: Dashboard) -> [PullRequest] {
        let openIDs = Set(dashboard.myPRs.map(\.id))
        let pending = pendingMergedPullRequests.filter { !openIDs.contains($0.id) && unreadURLs.contains($0.url) }
        return dashboard.myPRs + pending
    }

    private func saveHiddenPullRequests() {
        if let data = try? JSONEncoder().encode(hiddenPullRequests) {
            defaults.set(data, forKey: Self.hiddenPullRequestsKey)
        }
    }

    private func saveNotificationState() {
        if let data = try? JSONEncoder().encode(lastActivityAt) {
            defaults.set(data, forKey: Self.activityKey)
        }
        if let data = try? JSONEncoder().encode(unreadURLs) {
            defaults.set(data, forKey: Self.unreadKey)
        }
        if let data = try? JSONEncoder().encode(unreadNotifications) {
            defaults.set(data, forKey: Self.unreadNotificationsKey)
        }
        if let data = try? JSONEncoder().encode(knownMergedIDs) {
            defaults.set(data, forKey: Self.mergedKey)
        }
        if let data = try? JSONEncoder().encode(pendingMergedPullRequests) {
            defaults.set(data, forKey: Self.pendingMergedPullRequestsKey)
        }
        if let data = try? JSONEncoder().encode(lastMyPullRequestIDs) {
            defaults.set(data, forKey: Self.lastMyPullRequestIDsKey)
        }
    }

    private func updateDockBadge() {
        dependencies.setDockBadge(settings.showDockBadge && !visibleUnreadURLs.isEmpty ? "\(visibleUnreadURLs.count)" : nil)
    }
}
