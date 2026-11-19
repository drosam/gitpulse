import Foundation
import Testing
@testable import GitPulseCore

/// `UserDefaults` that keeps values in memory, so tests never write a plist to
/// `~/Library/Preferences` (cfprefsd can recreate deleted files after the run).
final class InMemoryDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]

    init() {
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? { lock.withLock { storage[defaultName] } }
    override func set(_ value: Any?, forKey defaultName: String) { lock.withLock { storage[defaultName] = value } }
    override func set(_ value: Bool, forKey defaultName: String) { set(value as Any?, forKey: defaultName) }
    override func set(_ value: Int, forKey defaultName: String) { set(value as Any?, forKey: defaultName) }
    override func set(_ value: Double, forKey defaultName: String) { set(value as Any?, forKey: defaultName) }
    override func set(_ value: Float, forKey defaultName: String) { set(value as Any?, forKey: defaultName) }
    override func set(_ url: URL?, forKey defaultName: String) { set(url as Any?, forKey: defaultName) }
    override func removeObject(forKey defaultName: String) { lock.withLock { storage[defaultName] = nil } }
    override func removePersistentDomain(forName domainName: String) { lock.withLock { storage = [:] } }
    override func data(forKey defaultName: String) -> Data? { object(forKey: defaultName) as? Data }
    override func string(forKey defaultName: String) -> String? { object(forKey: defaultName) as? String }
    override func array(forKey defaultName: String) -> [Any]? { object(forKey: defaultName) as? [Any] }
    override func stringArray(forKey defaultName: String) -> [String]? { object(forKey: defaultName) as? [String] }
    override func dictionary(forKey defaultName: String) -> [String: Any]? { object(forKey: defaultName) as? [String: Any] }
    override func bool(forKey defaultName: String) -> Bool { (object(forKey: defaultName) as? Bool) ?? false }
    override func integer(forKey defaultName: String) -> Int { (object(forKey: defaultName) as? Int) ?? 0 }
    override func double(forKey defaultName: String) -> Double { (object(forKey: defaultName) as? Double) ?? 0 }
    override func float(forKey defaultName: String) -> Float { (object(forKey: defaultName) as? Float) ?? 0 }
    override func url(forKey defaultName: String) -> URL? { object(forKey: defaultName) as? URL }
    override func dictionaryRepresentation() -> [String: Any] { lock.withLock { storage } }
}

/// Fresh, isolated defaults per test so suites can run in parallel.
func makeDefaults() -> UserDefaults {
    InMemoryDefaults()
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

    func post(_ event: NotificationEvent, for pullRequest: PullRequest) {
        let id = pullRequest.id
        switch event {
        case .checksFinished(let state): posts.append(.check(id, passed: state == .success))
        case .activity(let activity): posts.append(.activity(id, author: activity.author))
        case .merged: posts.append(.merged(id))
        case .leftMergeQueue: posts.append(.queueExit(id))
        case .reviewRequested: posts.append(.reviewRequest(id))
        }
    }

    func reset() { posts = [] }
}

/// Returns queued dashboards in order, then keeps returning the last one.
actor StubDashboardSource: DashboardSource {
    private var queue: [Dashboard]
    private var last: Dashboard?
    private(set) var trackedIDsPerCall: [[PullRequest.ID]] = []
    private var nextError: Error?
    private var callsToHold = 0
    private var held: [CheckedContinuation<Void, Never>] = []
    var heldCount: Int { held.count }

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

    /// Suspends the next `count` fetches (after picking their dashboards) until `release(_:)`.
    func holdNext(_ count: Int) {
        callsToHold = count
    }

    /// Resumes the held fetch at `index`, in call order.
    func release(_ index: Int) {
        held[index].resume()
    }

    func fetchDashboard(token: String, repositories: [String], trackedPullRequestIDs: [PullRequest.ID]) async throws -> Dashboard {
        trackedIDsPerCall.append(trackedPullRequestIDs.sorted())
        if let error = nextError {
            nextError = nil
            throw error
        }
        if !queue.isEmpty { last = queue.removeFirst() }
        guard let result = last else { throw GitHubError.http(500, nil) }
        if callsToHold > 0 {
            callsToHold -= 1
            await withCheckedContinuation { held.append($0) }
        }
        return result
    }

    /// Waits until `count` fetches are suspended by `holdNext(_:)`.
    func waitForHeld(_ count: Int) async {
        while held.count < count { await Task.yield() }
    }
}

@MainActor
final class BadgeRecorder {
    private(set) var values: [String?] = []
    var last: String? { values.last ?? nil }
    func record(_ value: String?) { values.append(value) }
}

@MainActor
struct SessionHarness {
    let defaults: UserDefaults
    let badge = BadgeRecorder()
    let settings: AppSettings
    let notifier: RecordingNotifier
    let source: StubDashboardSource
    let session: Session

    init(
        defaults: UserDefaults = makeDefaults(),
        dashboards: [Dashboard] = [],
        tokens: TokenProvider = TokenProvider(resolve: { ResolvedToken(token: "test-token", source: .keychain) }, save: { _ in true }, clear: { true }),
        deviceFlow: DeviceFlow = DeviceFlow(transport: { _ in throw URLError(.notConnectedToInternet) })
    ) {
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
                tokens: tokens,
                deviceFlow: deviceFlow,
                setDockBadge: { [badge] in badge.record($0) }
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
