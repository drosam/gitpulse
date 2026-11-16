import Foundation

/// Fictional dashboard for `--demo` launches, README screenshots, and render tests.
enum DemoData {
    static let viewer = "demo-user"

    static func dashboard(now: Date = Date()) -> Dashboard {
        let mine = [darkMode(now), rateLimit(now), tomlConfig(now)]
        let reviews = [tracing(now), terraform(now), onboarding(now)]
        return Dashboard(viewer: viewer, myPRs: mine, reviewRequests: reviews, recentlyMerged: [flakyTest(now)])
    }

    /// Unread state seeded before the first refresh so dots and the merged row show immediately.
    static func unreadNotifications(now: Date = Date()) -> [URL: [Session.UnreadNotification]] {
        let darkMode = darkMode(now)
        let tracing = tracing(now)
        let merged = flakyTest(now)
        return [
            darkMode.url: [.init(id: "demo-review", repository: darkMode.repository, subtitle: "@river approved", title: darkMode.title, createdAt: now.addingTimeInterval(-25 * 60))],
            tracing.url: [.init(id: "demo-request", repository: tracing.repository, subtitle: "Review requested", title: tracing.title, createdAt: now.addingTimeInterval(-50 * 60))],
            merged.url: [.init(id: "demo-merged", repository: merged.repository, subtitle: "Merged", title: merged.title, createdAt: now.addingTimeInterval(-2 * 3600))],
        ]
    }

    static func pendingMerged(now: Date = Date()) -> [PullRequest] {
        [flakyTest(now)]
    }

    // MARK: - Pull requests

    private static func darkMode(_ now: Date) -> PullRequest {
        make(id: "DEMO_1", repo: "acme/web", number: 482, title: "Add dark mode to the settings panel",
             author: viewer, branch: "feature/settings-dark-mode", review: .approved, checks: .success,
             labels: [.init(name: "ui", color: "1d76db"), .init(name: "enhancement", color: "a2eeef")],
             comments: 6, created: now.addingTimeInterval(-2 * 86400), updated: now.addingTimeInterval(-25 * 60))
    }

    private static func rateLimit(_ now: Date) -> PullRequest {
        make(id: "DEMO_2", repo: "acme/api", number: 219, title: "Rate-limit webhook retries",
             author: viewer, branch: "fix/webhook-retry-storm", review: .approved, checks: .pending,
             inQueue: true, queueState: "QUEUED", labels: [.init(name: "bug", color: "d73a4a")],
             comments: 3, created: now.addingTimeInterval(-26 * 3600), updated: now.addingTimeInterval(-10 * 60))
    }

    private static func tomlConfig(_ now: Date) -> PullRequest {
        make(id: "DEMO_3", repo: "globex/cli", number: 77, title: "Migrate config loader to TOML",
             author: viewer, branch: "refactor/toml-config", draft: true, checks: .failure,
             labels: [.init(name: "refactor", color: "fbca04")],
             comments: 1, created: now.addingTimeInterval(-5 * 3600), updated: now.addingTimeInterval(-3 * 3600))
    }

    private static func flakyTest(_ now: Date) -> PullRequest {
        make(id: "DEMO_4", repo: "acme/web", number: 470, title: "Fix flaky login integration test",
             author: viewer, branch: "fix/flaky-login-test", merged: true, review: .approved, checks: .success,
             comments: 2, created: now.addingTimeInterval(-3 * 86400), updated: now.addingTimeInterval(-2 * 3600))
    }

    private static func tracing(_ now: Date) -> PullRequest {
        make(id: "DEMO_5", repo: "acme/api", number: 225, title: "Add OpenTelemetry tracing to the job runner",
             author: "river", branch: "feat/otel-job-runner", review: .reviewRequired, checks: .success,
             labels: [.init(name: "observability", color: "5319e7")],
             comments: 4, created: now.addingTimeInterval(-50 * 60), updated: now.addingTimeInterval(-50 * 60))
    }

    private static func terraform(_ now: Date) -> PullRequest {
        make(id: "DEMO_6", repo: "globex/infra", number: 31, title: "Bump Terraform AWS provider to 5.x",
             author: "sam-k", branch: "chore/aws-provider-5", review: .changesRequested, checks: .error,
             labels: [.init(name: "dependencies", color: "0366d6")],
             comments: 9, created: now.addingTimeInterval(-4 * 86400), updated: now.addingTimeInterval(-6 * 3600))
    }

    private static func onboarding(_ now: Date) -> PullRequest {
        make(id: "DEMO_7", repo: "acme/web", number: 490, title: "Refine onboarding copy",
             author: "jordan", branch: "copy/onboarding-refresh", review: .reviewRequired,
             created: now.addingTimeInterval(-9 * 3600), updated: now.addingTimeInterval(-8 * 3600))
    }

    private static func make(
        id: String, repo: String, number: Int, title: String, author: String, branch: String,
        draft: Bool = false, merged: Bool = false, review: PullRequest.ReviewDecision? = nil,
        checks: PullRequest.CheckState? = nil, inQueue: Bool = false, queueState: String? = nil,
        labels: [PullRequest.Label] = [], comments: Int = 0, created: Date, updated: Date
    ) -> PullRequest {
        PullRequest(
            id: id, number: number, title: title,
            url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
            repository: repo, author: author, headBranch: branch,
            isDraft: draft, isMerged: merged, reviewDecision: review, checkState: checks,
            isInMergeQueue: inQueue, mergeQueueState: queueState, labels: labels, activity: [],
            commentCount: comments, additions: 42, deletions: 7, createdAt: created, updatedAt: updated
        )
    }
}
