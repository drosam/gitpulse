import AppKit
import SwiftUI

@Observable
@MainActor
final class Session {
    struct HiddenPullRequest: Identifiable, Codable, Hashable {
        var url: URL
        var title: String
        var repository: String
        var number: Int

        var id: URL { url }
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
    private(set) var hiddenPullRequests: [HiddenPullRequest] = []
    private var token: String?
    private let settings = AppSettings.shared
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
    private static let unreadKey = "unreadURLs"
    private static let mergedKey = "knownMergedIDs"
    private static let hiddenPullRequestsKey = "hiddenPullRequests"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.activityKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            lastActivityAt = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.unreadKey),
           let decoded = try? JSONDecoder().decode(Set<URL>.self, from: data) {
            unreadURLs = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.hiddenPullRequestsKey),
           let decoded = try? JSONDecoder().decode([HiddenPullRequest].self, from: data) {
            hiddenPullRequests = decoded
        }
        // A persisted set means a prior run already seeded; banner anything new
        // on the first refresh. A fresh install seeds silently instead.
        if let data = UserDefaults.standard.data(forKey: Self.mergedKey),
           let decoded = try? JSONDecoder().decode(Set<PullRequest.ID>.self, from: data) {
            knownMergedIDs = decoded
            hasSeededMerged = true
        }
    }

    var hasUnread: Bool { !visibleUnreadURLs.isEmpty }

    /// PR html URLs with unacknowledged activity, for the per-row dot.
    var unreadPRURLs: Set<URL> { unreadURLs }
    var hiddenPRURLs: Set<URL> { Set(hiddenPullRequests.map(\.url)) }

    private var visibleUnreadURLs: Set<URL> {
        unreadURLs.subtracting(hiddenPRURLs)
    }

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
            let dashboard = try await GitHubClient(token: token, repositories: settings.activeRepositories).fetchDashboard()
            processActivity(in: dashboard)
            state = .ready(displayDashboard(dashboard))
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
        prsInMergeQueue = []
        hasSeededMergeQueue = false
        knownMergedIDs = []
        hasSeededMerged = false
        unreadURLs = []
        hiddenPullRequests = []
        UserDefaults.standard.removeObject(forKey: Self.activityKey)
        UserDefaults.standard.removeObject(forKey: Self.unreadKey)
        UserDefaults.standard.removeObject(forKey: Self.mergedKey)
        UserDefaults.standard.removeObject(forKey: Self.hiddenPullRequestsKey)
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
    private func backgroundRefresh() async {
        guard let token else { return }
        if let dashboard = try? await GitHubClient(token: token, repositories: settings.activeRepositories).fetchDashboard() {
            processActivity(in: dashboard)
            state = .ready(displayDashboard(dashboard))
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
            recordUnread(pr)
            if !isHidden(pr) {
                Notifier.shared.postCheckResult(for: pr, passed: state == .success)
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
                    recordUnread(pr)
                    if !isHidden(pr) {
                        Notifier.shared.postActivity(for: pr, event: event)
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
                recordUnread(pr)
                if !isHidden(pr) {
                    Notifier.shared.postReviewRequest(for: pr)
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
                recordUnread(pr)
                if !isHidden(pr) {
                    Notifier.shared.postMergeQueueExit(for: pr)
                }
            }
        }
        prsInMergeQueue = Set(prs.filter { $0.isInMergeQueue || $0.mergeQueueState != nil }.map(\.id))
        hasSeededMergeQueue = true
    }

    /// Posts a banner for each newly merged PR you authored or were assigned to.
    /// Sourced from merged searches since merged PRs leave the open panes; no unread mark
    /// because there's no row to clear. Seeds silently only on a fresh install.
    private func detectMergedPRs(in dashboard: Dashboard) {
        let ids = Set(dashboard.recentlyMerged.map(\.id))
        if hasSeededMerged {
            for pr in dashboard.recentlyMerged where !knownMergedIDs.contains(pr.id) && !isHidden(pr) {
                Notifier.shared.postMerged(for: pr)
            }
        }
        knownMergedIDs = ids
        hasSeededMerged = true
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

    private func isHidden(_ pullRequest: PullRequest) -> Bool {
        hiddenPRURLs.contains(pullRequest.url)
    }

    private func recordUnread(_ pullRequest: PullRequest) {
        unreadURLs.insert(pullRequest.url)
    }

    private func applyHiddenDisplayToCurrentState() {
        guard case .ready(let dashboard) = state else { return }
        state = .ready(displayDashboard(dashboard))
    }

    private func displayDashboard(_ dashboard: Dashboard) -> Dashboard {
        if settings.showHiddenPullRequests {
            return Dashboard(
                viewer: dashboard.viewer,
                myPRs: sortHiddenLast(dashboard.myPRs),
                reviewRequests: sortHiddenLast(dashboard.reviewRequests),
                recentlyMerged: dashboard.recentlyMerged
            )
        }
        return filterHidden(dashboard)
    }

    private func sortHiddenLast(_ pullRequests: [PullRequest]) -> [PullRequest] {
        pullRequests.filter { !isHidden($0) } + pullRequests.filter { isHidden($0) }
    }

    private func filterHidden(_ dashboard: Dashboard) -> Dashboard {
        let hiddenURLs = Set(hiddenPullRequests.map(\.url))
        return Dashboard(
            viewer: dashboard.viewer,
            myPRs: dashboard.myPRs.filter { !hiddenURLs.contains($0.url) },
            reviewRequests: dashboard.reviewRequests.filter { !hiddenURLs.contains($0.url) },
            recentlyMerged: dashboard.recentlyMerged.filter { !hiddenURLs.contains($0.url) }
        )
    }

    private func saveHiddenPullRequests() {
        if let data = try? JSONEncoder().encode(hiddenPullRequests) {
            UserDefaults.standard.set(data, forKey: Self.hiddenPullRequestsKey)
        }
    }

    private func saveNotificationState() {
        if let data = try? JSONEncoder().encode(lastActivityAt) {
            UserDefaults.standard.set(data, forKey: Self.activityKey)
        }
        if let data = try? JSONEncoder().encode(unreadURLs) {
            UserDefaults.standard.set(data, forKey: Self.unreadKey)
        }
        if let data = try? JSONEncoder().encode(knownMergedIDs) {
            UserDefaults.standard.set(data, forKey: Self.mergedKey)
        }
    }

    private func updateDockBadge() {
        NSApp.dockTile.badgeLabel = settings.showDockBadge && !visibleUnreadURLs.isEmpty ? "\(visibleUnreadURLs.count)" : nil
    }
}
