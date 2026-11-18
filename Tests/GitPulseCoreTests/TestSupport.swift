import Foundation
import Testing
@testable import GitPulseCore

/// Fresh, isolated defaults per test so suites can run in parallel.
func makeDefaults() -> UserDefaults {
    let name = "gitpulse.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

func date(_ iso: String) -> Date {
    try! Date(iso, strategy: .iso8601)
}

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func makePR(
    _ id: String,
    repository: String = "acme/web",
    number: Int? = nil,
    author: String = "octocat",
    isMerged: Bool = false,
    checkState: PullRequest.CheckState? = nil,
    isInMergeQueue: Bool = false,
    mergeQueueState: String? = nil,
    activity: [PullRequest.ActivityEvent] = [],
    createdAt: String = "2026-01-01T00:00:00Z",
    updatedAt: String = "2026-01-02T00:00:00Z",
    mergedAt: Date? = nil
) -> PullRequest {
    PullRequest(
        id: id,
        number: number ?? 1,
        title: "PR \(id)",
        url: URL(string: "https://github.com/\(repository)/pull/\(id)")!,
        repository: repository,
        author: author,
        headBranch: "branch-\(id)",
        isDraft: false,
        isMerged: isMerged,
        reviewDecision: nil,
        checkState: checkState,
        isInMergeQueue: isInMergeQueue,
        mergeQueueState: mergeQueueState,
        labels: [],
        activity: activity,
        commentCount: activity.count,
        additions: 1,
        deletions: 1,
        createdAt: date(createdAt),
        updatedAt: date(updatedAt),
        mergedAt: mergedAt
    )
}

func comment(by author: String, at iso: String) -> PullRequest.ActivityEvent {
    .init(kind: .comment, author: author, createdAt: date(iso))
}

func makeDashboard(
    viewer: String = "octocat",
    mine: [PullRequest] = [],
    reviews: [PullRequest] = [],
    requested: [PullRequest]? = nil,
    merged: [PullRequest] = []
) -> Dashboard {
    Dashboard(
        viewer: viewer,
        myPRs: mine,
        reviewRequests: reviews,
        requestedReviewIDs: Set((requested ?? reviews).map(\.id)),
        recentlyMerged: merged
    )
}

@MainActor
final class RecordingNotifier: NotificationPosting {
    enum Post: Equatable {
        case check(String, passed: Bool)
        case activity(String, author: String)
        case merged(String)
        case queueExit(String)
        case reviewRequest(String)
    }

    private(set) var posts: [Post] = []
    var onOpenPullRequest: (@MainActor (URL) -> Void)?

    func postCheckResult(for pullRequest: PullRequest, passed: Bool) { posts.append(.check(pullRequest.id, passed: passed)) }
    func postActivity(for pullRequest: PullRequest, event: PullRequest.ActivityEvent) { posts.append(.activity(pullRequest.id, author: event.author)) }
    func postMerged(for pullRequest: PullRequest) { posts.append(.merged(pullRequest.id)) }
    func postMergeQueueExit(for pullRequest: PullRequest) { posts.append(.queueExit(pullRequest.id)) }
    func postReviewRequest(for pullRequest: PullRequest) { posts.append(.reviewRequest(pullRequest.id)) }

    func reset() { posts = [] }
}

/// Returns queued dashboards in order, then keeps returning the last one.
actor StubDashboardSource: DashboardSource {
    private var queue: [Dashboard]
    private var last: Dashboard?
    private(set) var trackedIDsPerCall: [[PullRequest.ID]] = []
    private var nextError: Error?

    init(_ dashboards: [Dashboard] = []) {
        queue = dashboards
    }

    func enqueue(_ dashboard: Dashboard) {
        queue.append(dashboard)
    }

    /// Makes the next fetch throw `error` instead of returning a dashboard.
    func failNext(with error: Error) {
        nextError = error
    }

    func fetchDashboard(token: String, repositories: [String], trackedPullRequestIDs: [PullRequest.ID]) async throws -> Dashboard {
        trackedIDsPerCall.append(trackedPullRequestIDs.sorted())
        if let error = nextError {
            nextError = nil
            throw error
        }
        if !queue.isEmpty { last = queue.removeFirst() }
        guard let last else { throw GitHubError.http(500, nil) }
        return last
    }
}

@MainActor
struct SessionHarness {
    let defaults: UserDefaults
    let settings: AppSettings
    let notifier: RecordingNotifier
    let source: StubDashboardSource
    let session: Session

    init(defaults: UserDefaults = makeDefaults(), dashboards: [Dashboard] = []) {
        self.defaults = defaults
        settings = AppSettings(defaults: defaults)
        notifier = RecordingNotifier()
        source = StubDashboardSource(dashboards)
        session = Session(
            settings: settings,
            defaults: defaults,
            dependencies: Session.Dependencies(
                notifier: notifier,
                dashboardSource: source,
                tokens: TokenProvider(resolve: { "test-token" }, save: { _ in }, clear: {}),
                deviceFlow: DeviceFlow(),
                setDockBadge: { _ in }
            )
        )
    }

    var dashboard: Dashboard? {
        if case .ready(let dashboard) = session.state { return dashboard }
        return nil
    }

    /// Feeds one dashboard through a full refresh (`start` resolves the stub token first).
    func load(_ dashboard: Dashboard) async {
        await source.enqueue(dashboard)
        await session.start()
    }
}
