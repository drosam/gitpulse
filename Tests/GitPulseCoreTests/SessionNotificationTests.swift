import Foundation
import Testing
@testable import GitPulseCore

@MainActor
struct SessionNotificationTests {
    private let prA1 = makePR(
        "A",
        checkState: .pending,
        isInMergeQueue: true,
        mergeQueueState: "QUEUED",
        activity: [comment(by: "hubot", at: "2026-01-02T00:00:00Z")]
    )
    private let prA2 = makePR(
        "A",
        checkState: .success,
        activity: [
            comment(by: "hubot", at: "2026-01-02T00:00:00Z"),
            comment(by: "hubot", at: "2026-01-03T00:00:00Z"),
            comment(by: "octocat", at: "2026-01-04T00:00:00Z"),
        ],
        updatedAt: "2026-01-04T00:00:00Z"
    )
    private let prC = makePR("C", author: "hubot")
    private let prD = makePR("D", author: "hubot")
    private let prM = makePR("M", isMerged: true, updatedAt: "2026-01-05T00:00:00Z")

    @Test func firstRefreshSeedsSilently() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [prA1], reviews: [prC], merged: [prM]))

        #expect(harness.notifier.posts.isEmpty)
        #expect(!harness.session.hasUnread)
    }

    @Test func secondRefreshPostsEachNewEventOnce() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [prA1], reviews: [prC]))
        await harness.load(makeDashboard(mine: [prA2], reviews: [prC, prD], merged: [prM]))

        let posts = harness.notifier.posts
        #expect(posts.contains(.check("A", passed: true)))
        #expect(posts.contains(.activity("A", author: "hubot")))
        #expect(!posts.contains(.activity("A", author: "octocat")))
        #expect(posts.contains(.queueExit("A")))
        #expect(posts.contains(.reviewRequest("D")))
        #expect(posts.contains(.merged("M")))
        #expect(posts.count == 5)
        #expect(harness.session.unreadPRURLs == [prA2.url, prD.url, prM.url])
        #expect(harness.session.hasUnread)

        harness.notifier.reset()
        await harness.session.refresh()
        #expect(harness.notifier.posts.isEmpty)
    }

    @Test func participatingWithoutRequestDoesNotPostReviewRequest() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(reviews: [prC]))
        await harness.load(makeDashboard(reviews: [prC, prD], requested: [prC]))

        #expect(harness.notifier.posts.isEmpty)
        #expect(!harness.session.hasUnread)
    }

    @Test func reviewRequestedOnParticipatedPullRequestPosts() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(reviews: [prD], requested: []))
        await harness.load(makeDashboard(reviews: [prD]))

        #expect(harness.notifier.posts == [.reviewRequest("D")])
    }

    @Test func widenedRepositoryScopeSeedsSilently() async {
        let harness = SessionHarness()
        harness.settings.repositoryScope = .selected
        harness.settings.selectedRepositoriesText = "acme/web"
        await harness.load(makeDashboard(reviews: [prC]))

        harness.settings.repositoryScope = .all
        let other = makePR("E", repository: "acme/api", author: "hubot")
        let otherMerged = makePR("N", repository: "acme/api", isMerged: true)
        await harness.load(makeDashboard(reviews: [prC, other], merged: [prM, otherMerged]))

        #expect(harness.notifier.posts.isEmpty)
        #expect(!harness.session.hasUnread)

        await harness.load(makeDashboard(reviews: [prC, other, prD], merged: [prM, otherMerged]))
        #expect(harness.notifier.posts == [.reviewRequest("D")])
    }

    @Test func firstActivityOnQuietPullRequestPosts() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [makePR("A")]))
        await harness.load(makeDashboard(mine: [makePR("A", activity: [comment(by: "hubot", at: "2026-01-03T00:00:00Z")])]))

        #expect(harness.notifier.posts == [.activity("A", author: "hubot")])
        #expect(harness.session.unreadPRURLs == [makePR("A").url])
    }

    @Test func checkFailurePostsFailedResult() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [makePR("A", checkState: .pending)]))
        await harness.load(makeDashboard(mine: [makePR("A", checkState: .failure)]))

        #expect(harness.notifier.posts == [.check("A", passed: false)])
    }

    @Test func pullRequestEnteringWithFinishedChecksDoesNotPostCheckResult() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [makePR("A", checkState: .pending)]))
        await harness.load(makeDashboard(mine: [makePR("A", checkState: .pending), makePR("D", checkState: .success)]))

        #expect(harness.notifier.posts == [])
    }

    @Test func checksFinishingAfterNoChecksPostResult() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [makePR("A", checkState: .pending)]))
        await harness.load(makeDashboard(mine: [makePR("A", checkState: .pending), makePR("D")]))
        await harness.load(makeDashboard(mine: [makePR("A", checkState: .pending), makePR("D", checkState: .success)]))

        #expect(harness.notifier.posts == [.check("D", passed: true)])
    }

    @Test func unreadSummaryDescribesActivity() async throws {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [makePR("A", activity: prA1.activity)]))
        await harness.load(makeDashboard(mine: [makePR("A", activity: prA1.activity + [
            .init(kind: .review(state: "CHANGES_REQUESTED"), author: "monalisa", createdAt: date("2026-01-03T00:00:00Z")),
        ])]))

        let notifications = try #require(harness.session.unreadNotificationsByURL[prA1.url])
        #expect(notifications.map(\.subtitle) == ["@monalisa requested changes"])
    }

    @Test func hiddenPullRequestRecordsRowUnreadWithoutBannerOrBadge() async {
        let harness = SessionHarness()
        let seen = comment(by: "hubot", at: "2026-01-02T00:00:00Z")
        await harness.load(makeDashboard(reviews: [makePR("C", author: "hubot", activity: [seen])]))
        harness.session.hide(prC)

        let updated = makePR("C", author: "hubot", activity: [seen, comment(by: "hubot", at: "2026-01-03T00:00:00Z")])
        await harness.load(makeDashboard(reviews: [updated]))

        #expect(harness.notifier.posts.isEmpty)
        #expect(harness.session.unreadPRURLs.contains(prC.url))
        #expect(!harness.session.hasUnread)
    }

    @Test func activityCursorPersistsAcrossLaunches() async {
        let defaults = makeDefaults()
        let first = SessionHarness(defaults: defaults)
        await first.load(makeDashboard(mine: [prA1]))

        let relaunched = SessionHarness(defaults: defaults)
        await relaunched.load(makeDashboard(mine: [prA2]))

        #expect(relaunched.notifier.posts.contains(.activity("A", author: "hubot")))
    }

    @Test func mergeSeenWhileClosedPostsOnNextLaunch() async {
        let defaults = makeDefaults()
        let first = SessionHarness(defaults: defaults)
        await first.load(makeDashboard(mine: [prA1]))

        let relaunched = SessionHarness(defaults: defaults)
        await relaunched.load(makeDashboard(merged: [prM]))

        #expect(relaunched.notifier.posts == [.merged("M")])
    }
}
