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
        /// Nil for rows saved before kinds were stored; see `resolvedKind`.
        var kind: NotificationEvent.Kind?

        var resolvedKind: NotificationEvent.Kind? { kind ?? NotificationEvent.Kind(legacySubtitle: subtitle) }
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
    /// Why the last refresh failed while a dashboard was showing, or why sign-in expired; cleared by the next success.
    private(set) var refreshError: String?
    /// Last fetched dashboard before hiding, sorting and merged rows; the display is derived from it.
    private var fetchedDashboard: Dashboard?
    /// Bumped by every fetch and by sign-out, so a response that lands late is dropped.
    private var refreshGeneration = 0
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
    private var signInTask: Task<Void, Never>?
    /// Bumped per sign-in, cancel and sign-out, so a superseded device flow's result is ignored.
    private var signInGeneration = 0
    /// Background refresh skips polls until this time after GitHub reports an exhausted rate limit.
    private var rateLimitedUntil: Date?
    /// Last seen head-commit check state per PR, to detect CI finishing.
    private var lastCheckState: [PullRequest.ID: PullRequest.CheckState] = [:]
    /// PRs on the dashboard in the previous pass, with or without checks; only these banner check results.
    private var checkedPullRequestIDs: Set<PullRequest.ID> = []
    private var hasSeededChecks = false
    /// Newest activity timestamp seen per PR, to detect new comments/reviews.
    /// Persisted, so activity that arrives while the app is closed banners once
    /// on the next launch. A PR with no entry yet seeds silently.
    private var lastActivityAt: [PullRequest.ID: Date] = [:]
    /// PRs currently asking for your review, to banner ones that newly appear.
    /// Persisted, so a request that arrives while the app is closed banners on the next launch.
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
    /// When merges were last checked. Persisted; an unseen PR merged before this is old history
    /// that entered the updated-first search window, not a new merge.
    private var lastMergeCheck: Date?
    /// Repository filter of the last successful fetch; a change reseeds the ID baselines silently.
    private var fetchedRepositories: [String]?
    /// GitHub login that owns the loaded state; nil until the first fetch after upgrading from unscoped keys.
    private var stateAccount: String?

    private static let autoRefreshInterval: Duration = .seconds(120)
    private static let activityKey = "lastActivityAt"
    static let unreadKey = "unreadURLs"
    static let unreadNotificationsKey = "unreadNotifications"
    static let mergedKey = "knownMergedIDs"
    private static let reviewRequestsKey = "knownReviewRequestIDs"
    private static let lastMergeCheckKey = "lastMergeCheck"
    /// Slack for clock skew and search indexing lag when comparing `mergedAt` to `lastMergeCheck`.
    private static let mergeCheckMargin: TimeInterval = 3600
    static let pendingMergedPullRequestsKey = "pendingMergedPullRequests"
    private static let lastMyPullRequestIDsKey = "lastMyPullRequestIDs"
    private static let hiddenPullRequestsKey = "hiddenPullRequests"
    private static let stateAccountKey = "stateAccount"
    /// Set by Sign out so `start()` doesn't pick an environment or gh CLI token back up.
    private static let signedOutKey = "signedOut"
    private static let accountStateKeys = [
        activityKey, unreadKey, unreadNotificationsKey, mergedKey, reviewRequestsKey,
        lastMergeCheckKey, pendingMergedPullRequestsKey, lastMyPullRequestIDsKey, hiddenPullRequestsKey,
    ]

    public convenience init() {
        self.init(settings: .shared, defaults: .standard, dependencies: .live)
    }

    init(settings: AppSettings, defaults: UserDefaults, dependencies: Dependencies) {
        self.settings = settings
        self.defaults = defaults
        self.dependencies = dependencies
        stateAccount = defaults.string(forKey: Self.stateAccountKey)
        loadAccountState()
        dependencies.notifier.onOpenPullRequest = { [weak self] url in
            self?.markRead(prURL: url)
        }
    }

    /// Saved state lives under `accounts.<login>.`; unscoped keys predate per-account state.
    private func key(_ base: String) -> String {
        stateAccount.map { "accounts.\($0).\(base)" } ?? base
    }

    private func loadAccountState() {
        if let data = defaults.data(forKey: key(Self.activityKey)),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            lastActivityAt = decoded
        }
        if let data = defaults.data(forKey: key(Self.unreadKey)),
           let decoded = try? JSONDecoder().decode(Set<URL>.self, from: data) {
            unreadURLs = decoded
        }
        if let data = defaults.data(forKey: key(Self.unreadNotificationsKey)),
           let decoded = try? JSONDecoder().decode([String: [UnreadNotification]].self, from: data) {
            unreadNotifications = decoded
        }
        if let data = defaults.data(forKey: key(Self.hiddenPullRequestsKey)),
           let decoded = try? JSONDecoder().decode([HiddenPullRequest].self, from: data) {
            hiddenPullRequests = decoded
        }
        if let data = defaults.data(forKey: key(Self.pendingMergedPullRequestsKey)),
           let decoded = try? JSONDecoder().decode([PullRequest].self, from: data) {
            pendingMergedPullRequests = decoded
        }
        if let data = defaults.data(forKey: key(Self.lastMyPullRequestIDsKey)),
           let decoded = try? JSONDecoder().decode(Set<PullRequest.ID>.self, from: data) {
            lastMyPullRequestIDs = decoded
        }
        // A persisted set means a prior run already seeded; banner anything new
        // on the first refresh. A fresh install seeds silently instead.
        if let data = defaults.data(forKey: key(Self.mergedKey)),
           let decoded = try? JSONDecoder().decode(Set<PullRequest.ID>.self, from: data) {
            knownMergedIDs = decoded
            hasSeededMerged = true
        }
        lastMergeCheck = defaults.object(forKey: key(Self.lastMergeCheckKey)) as? Date
        if let data = defaults.data(forKey: key(Self.reviewRequestsKey)),
           let decoded = try? JSONDecoder().decode(Set<PullRequest.ID>.self, from: data) {
            knownReviewRequestIDs = decoded
            hasSeededReviewRequests = true
        }
    }

    /// Makes `viewer` own the loaded state. Unscoped state moves to the first account seen;
    /// another account's state is swapped out. Returns true when the account changed.
    private func switchAccount(to viewer: String) -> Bool {
        let viewer = viewer.lowercased()
        guard !viewer.isEmpty, viewer != stateAccount else { return false }
        guard stateAccount != nil else {
            for base in Self.accountStateKeys {
                if let value = defaults.object(forKey: base) {
                    defaults.set(value, forKey: "accounts.\(viewer).\(base)")
                    defaults.removeObject(forKey: base)
                }
            }
            stateAccount = viewer
            defaults.set(viewer, forKey: Self.stateAccountKey)
            return false
        }
        stateAccount = viewer
        defaults.set(viewer, forKey: Self.stateAccountKey)
        resetLocalState()
        loadAccountState()
        updateDockBadge()
        return true
    }

    /// Clears in-memory per-account state; persisted state is untouched.
    private func resetLocalState() {
        rateLimitedUntil = nil
        lastActivityAt = [:]
        lastCheckState = [:]
        checkedPullRequestIDs = []
        knownReviewRequestIDs = []
        hasSeededReviewRequests = false
        hasSeededChecks = false
        prsInMergeQueue = []
        hasSeededMergeQueue = false
        knownMergedIDs = []
        hasSeededMerged = false
        lastMergeCheck = nil
        unreadURLs = []
        unreadNotifications = [:]
        hiddenPullRequests = []
        pendingMergedPullRequests = []
        lastMyPullRequestIDs = []
        fetchedRepositories = nil
        fetchedDashboard = nil
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

    /// A Keychain save or delete that failed; kept until the next sign-in or sign-out.
    private(set) var keychainError: String?

    /// Where the signed-in token came from; nil while signed out.
    private(set) var tokenSource: TokenSource?
    /// A token GitPulse can't delete (environment or gh CLI), offered on the sign-in screen after sign-out.
    private(set) var externalTokenSource: TokenSource?
    var viewerLogin: String? { fetchedDashboard?.viewer }

    public func start() async {
        if case .authorizing = state { return }
        if token == nil {
            if defaults.bool(forKey: Self.signedOutKey) {
                state = .signedOut
                await updateExternalTokenSource()
                return
            }
            let resolved = await dependencies.tokens.resolve()
            // Sign-in, sign-out or another start may have run during the lookup.
            if case .authorizing = state { return }
            guard token == nil, !defaults.bool(forKey: Self.signedOutKey) else { return }
            guard let resolved else {
                state = .signedOut
                return
            }
            token = resolved.token
            tokenSource = resolved.source
            externalTokenSource = nil
        }
        await refresh()
        startAutoRefresh()
    }

    private func updateExternalTokenSource() async {
        let source = await dependencies.tokens.resolve()?.source
        if token == nil { externalTokenSource = source }
    }

    /// Abandons the device flow in progress and returns to the sign-in screen.
    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        signInGeneration += 1
        state = .signedOut
    }

    /// Signs in again with the environment or gh CLI token after an explicit sign-out.
    func useExternalToken() async {
        keychainError = nil
        defaults.removeObject(forKey: Self.signedOutKey)
        await start()
    }

    public func refresh() async {
        guard let token else { return }
        if settings.selectsNoRepositories { return showNoRepositories() }
        if case .ready = state {} else { state = .loading }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let dashboard = try await fetchDashboard(token: token)
            processActivity(in: dashboard)
            show(dashboard)
        } catch {
            handleRefreshFailure(error)
        }
    }

    /// Runs one device flow at a time; starting another cancels the previous one.
    func signIn() async {
        signInTask?.cancel()
        signInGeneration += 1
        let generation = signInGeneration
        let task = Task { await runSignIn(generation: generation) }
        signInTask = task
        await task.value
    }

    private func runSignIn(generation: Int) async {
        do {
            let authorization = try await dependencies.deviceFlow.requestCode()
            guard generation == signInGeneration else { return }
            state = .authorizing(authorization)
            let newToken = try await dependencies.deviceFlow.pollForToken(authorization)
            guard generation == signInGeneration else { return }
            signInTask = nil
            keychainError = dependencies.tokens.save(newToken)
                ? nil
                : "Couldn't save your sign-in to the Keychain, so you'll need to sign in again next time GitPulse opens."
            defaults.removeObject(forKey: Self.signedOutKey)
            token = newToken
            tokenSource = .keychain
            externalTokenSource = nil
            await refresh()
            startAutoRefresh()
        } catch {
            guard generation == signInGeneration else { return }
            signInTask = nil
            state = .failed(error.localizedDescription)
        }
    }

    func signOut() {
        signInTask?.cancel()
        signInTask = nil
        signInGeneration += 1
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        resetLocalState()
        refreshError = nil
        refreshGeneration += 1
        for base in Self.accountStateKeys {
            defaults.removeObject(forKey: key(base))
        }
        updateDockBadge()
        keychainError = dependencies.tokens.clear()
            ? nil
            : "Couldn't remove your token from the Keychain. Delete \"dev.davidrosa.gitpulse.github-token\" in Keychain Access."
        defaults.set(true, forKey: Self.signedOutKey)
        token = nil
        tokenSource = nil
        state = .signedOut
        Task { await updateExternalTokenSource() }
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
        updateDisplay()
    }

    func applySettingsChanged(refresh: Bool = false) async {
        updateDockBadge()
        if refresh {
            await self.refresh()
        } else {
            updateDisplay()
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
        updateDockBadge()
        updateDisplay()
    }

    func unhide(_ hiddenPullRequest: HiddenPullRequest) {
        unhide(url: hiddenPullRequest.url)
    }

    func unhide(url: URL) {
        hiddenPullRequests.removeAll { $0.url == url }
        saveHiddenPullRequests()
        updateDockBadge()
        updateDisplay()
    }

    func unhideAll() {
        hiddenPullRequests = []
        saveHiddenPullRequests()
        updateDockBadge()
        updateDisplay()
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

    func backgroundRefresh() async {
        guard let token else { return }
        if settings.selectsNoRepositories { return showNoRepositories() }
        if let rateLimitedUntil, Date() < rateLimitedUntil { return }
        do {
            let dashboard = try await fetchDashboard(token: token)
            processActivity(in: dashboard)
            show(dashboard)
        } catch {
            handleRefreshFailure(error)
        }
    }

    /// Keeps a showing dashboard and reports the error beside it; a 401 returns to sign-in
    /// without wiping local unread and hidden state.
    private func handleRefreshFailure(_ error: Error) {
        if error is CancellationError { return }
        if case GitHubError.http(401, _) = error {
            refreshGeneration += 1
            autoRefreshTask?.cancel()
            autoRefreshTask = nil
            _ = dependencies.tokens.clear()
            token = nil
            tokenSource = nil
            Task { await updateExternalTokenSource() }
            fetchedDashboard = nil
            refreshError = "Your GitHub sign-in expired or was revoked. Sign in again."
            state = .signedOut
        } else if fetchedDashboard == nil {
            state = .failed(error.localizedDescription)
        } else {
            refreshError = error.localizedDescription
        }
    }

    /// Empty lists without fetching or touching notification state; drops any in-flight fetch.
    private func showNoRepositories() {
        refreshGeneration += 1
        show(Dashboard(
            viewer: fetchedDashboard?.viewer ?? "",
            myPRs: [],
            reviewRequests: [],
            requestedReviewIDs: [],
            recentlyMerged: []
        ))
    }

    private func show(_ dashboard: Dashboard) {
        fetchedDashboard = dashboard
        refreshError = nil
        updateDisplay()
    }

    /// Refetches once after an account switch so the request carries that account's tracked IDs.
    private func fetchDashboard(token: String, afterAccountSwitch: Bool = false) async throws -> Dashboard {
        let repositories = settings.activeRepositories
        refreshGeneration += 1
        let generation = refreshGeneration
        let dashboard: Dashboard
        do {
            dashboard = try await dependencies.dashboardSource.fetchDashboard(
                token: token,
                repositories: repositories,
                trackedPullRequestIDs: Array(lastMyPullRequestIDs)
            )
        } catch {
            guard generation == refreshGeneration else { throw CancellationError() }
            if case GitHubError.rateLimited(let until) = error { rateLimitedUntil = until }
            throw error
        }
        guard generation == refreshGeneration else { throw CancellationError() }
        if switchAccount(to: dashboard.viewer), !afterAccountSwitch {
            return try await fetchDashboard(token: token, afterAccountSwitch: true)
        }
        rateLimitedUntil = nil
        if let fetchedRepositories, fetchedRepositories != repositories {
            hasSeededReviewRequests = false
            hasSeededMerged = false
        }
        fetchedRepositories = repositories
        return dashboard
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
    /// state (passed / failed). The first pass after launch, and a PR newly
    /// entering the dashboard, seed silently so we don't banner old results.
    private func detectFinishedChecks(in dashboard: Dashboard) {
        let prs = dashboard.myPRs + dashboard.reviewRequests
        let previouslyShown = checkedPullRequestIDs
        checkedPullRequestIDs = Set(prs.map(\.id))
        for pr in prs {
            guard let state = pr.checkState else { continue }
            let previous = lastCheckState[pr.id]
            lastCheckState[pr.id] = state
            let finished = state == .success || state == .failure || state == .error
            guard hasSeededChecks, previouslyShown.contains(pr.id), finished, state != previous else { continue }
            announce(.checksFinished(state), for: pr)
        }
        hasSeededChecks = true
    }

    /// Posts a banner for each comment or review newer than the last one we saw
    /// on that PR (skipping your own). A PR with no recorded cursor seeds
    /// silently — covers both first launch and a PR newly entering the app.
    /// A PR seen with no activity yet gets a `.distantPast` cursor so its first event notifies.
    private func detectNewActivity(in dashboard: Dashboard) {
        let prs = dashboard.myPRs + dashboard.reviewRequests
        for pr in prs {
            let newest = pr.activity.last?.createdAt ?? .distantPast
            if let cursor = lastActivityAt[pr.id] {
                for event in pr.activity where event.createdAt > cursor && event.author != dashboard.viewer {
                    announce(.activity(event), for: pr)
                }
            }
            lastActivityAt[pr.id] = max(lastActivityAt[pr.id] ?? .distantPast, newest)
        }
    }

    /// Posts a banner when GitHub newly requests your review on a PR, not when a
    /// PR enters the pane only because you commented or reviewed.
    private func detectNewReviewRequests(in dashboard: Dashboard) {
        let ids = dashboard.requestedReviewIDs
        if hasSeededReviewRequests {
            for pr in dashboard.reviewRequests where ids.contains(pr.id) && !knownReviewRequestIDs.contains(pr.id) {
                announce(.reviewRequested, for: pr)
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
                announce(.leftMergeQueue, for: pr)
            }
        }
        prsInMergeQueue = Set(prs.filter { $0.isInMergeQueue || $0.mergeQueueState != nil }.map(\.id))
        hasSeededMergeQueue = true
    }

    /// Posts a banner for each newly merged PR you authored or were assigned to.
    /// Keeps merged PRs as unread rows in My pull requests until opened.
    private func detectMergedPRs(in dashboard: Dashboard) {
        let ids = Set(dashboard.recentlyMerged.map(\.id))
        let cutoff = lastMergeCheck?.addingTimeInterval(-Self.mergeCheckMargin) ?? .distantPast
        if hasSeededMerged {
            for pr in dashboard.recentlyMerged where !knownMergedIDs.contains(pr.id) && !isHidden(pr)
                && (pr.mergedAt ?? .distantFuture) > cutoff {
                pendingMergedPullRequests.removeAll { $0.id == pr.id }
                pendingMergedPullRequests.append(pr)
                announce(.merged, for: pr)
            }
        }
        knownMergedIDs.formUnion(ids)
        lastMyPullRequestIDs = Set(dashboard.myPRs.map(\.id))
        hasSeededMerged = true
        lastMergeCheck = Date()
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

    /// Records the unread row, and posts the banner unless the PR is hidden.
    private func announce(_ event: NotificationEvent, for pullRequest: PullRequest) {
        recordUnread(event, for: pullRequest)
        if !isHidden(pullRequest) {
            dependencies.notifier.post(event, for: pullRequest)
        }
    }

    private func recordUnread(_ event: NotificationEvent, for pullRequest: PullRequest) {
        unreadURLs.insert(pullRequest.url)
        let id = event.identifier(for: pullRequest)
        let notification = UnreadNotification(
            id: id,
            repository: pullRequest.repository,
            subtitle: event.subtitle,
            title: pullRequest.title,
            createdAt: event.date(for: pullRequest),
            kind: event.kind
        )
        let key = pullRequest.url.absoluteString
        var notifications = unreadNotifications[key] ?? []
        notifications.removeAll { $0.id == id }
        notifications.append(notification)
        unreadNotifications[key] = notifications.sorted { $0.createdAt > $1.createdAt }
    }

    private func updateDisplay() {
        guard let fetchedDashboard else { return }
        state = .ready(displayDashboard(fetchedDashboard))
    }

    private func displayDashboard(_ dashboard: Dashboard) -> Dashboard {
        Dashboard(
            viewer: dashboard.viewer,
            myPRs: displayPullRequests(mergedRows(in: dashboard)),
            reviewRequests: displayPullRequests(dashboard.reviewRequests),
            requestedReviewIDs: dashboard.requestedReviewIDs,
            recentlyMerged: dashboard.recentlyMerged,
            myPRsTruncated: dashboard.myPRsTruncated,
            reviewRequestsTruncated: dashboard.reviewRequestsTruncated
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
            defaults.set(data, forKey: key(Self.hiddenPullRequestsKey))
        }
    }

    private func saveNotificationState() {
        if let data = try? JSONEncoder().encode(lastActivityAt) {
            defaults.set(data, forKey: key(Self.activityKey))
        }
        if let data = try? JSONEncoder().encode(unreadURLs) {
            defaults.set(data, forKey: key(Self.unreadKey))
        }
        if let data = try? JSONEncoder().encode(unreadNotifications) {
            defaults.set(data, forKey: key(Self.unreadNotificationsKey))
        }
        if let data = try? JSONEncoder().encode(knownMergedIDs) {
            defaults.set(data, forKey: key(Self.mergedKey))
        }
        defaults.set(lastMergeCheck, forKey: key(Self.lastMergeCheckKey))
        if let data = try? JSONEncoder().encode(knownReviewRequestIDs) {
            defaults.set(data, forKey: key(Self.reviewRequestsKey))
        }
        if let data = try? JSONEncoder().encode(pendingMergedPullRequests) {
            defaults.set(data, forKey: key(Self.pendingMergedPullRequestsKey))
        }
        if let data = try? JSONEncoder().encode(lastMyPullRequestIDs) {
            defaults.set(data, forKey: key(Self.lastMyPullRequestIDsKey))
        }
    }

    private func updateDockBadge() {
        dependencies.setDockBadge(settings.showDockBadge && !visibleUnreadURLs.isEmpty ? "\(visibleUnreadURLs.count)" : nil)
    }
}
