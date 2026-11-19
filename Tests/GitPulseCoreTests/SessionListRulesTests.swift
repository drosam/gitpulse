import Foundation
import Testing
@testable import GitPulseCore

@MainActor
struct SessionListRulesTests {
    private let older = makePR("old", createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-09T00:00:00Z")
    private let newer = makePR("new", createdAt: "2026-01-05T00:00:00Z", updatedAt: "2026-01-06T00:00:00Z")
    private let third = makePR("third", createdAt: "2026-01-03T00:00:00Z", updatedAt: "2026-01-03T00:00:00Z")

    @Test func sortsByCreatedNewestByDefault() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [older, third, newer]))

        #expect(harness.dashboard?.myPRs.map(\.id) == ["new", "third", "old"])
    }

    @Test func sortsByUpdatedNewestWhenSelected() async {
        let harness = SessionHarness()
        harness.settings.pullRequestSort = .updatedAtNewest
        await harness.load(makeDashboard(mine: [older, third, newer]))

        #expect(harness.dashboard?.myPRs.map(\.id) == ["old", "new", "third"])
    }

    @Test func changingSortReordersWithoutFetching() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [older, third, newer]))
        let fetches = await harness.source.trackedIDsPerCall.count

        harness.settings.pullRequestSort = .updatedAtNewest
        await harness.session.applySettingsChanged()

        #expect(harness.dashboard?.myPRs.map(\.id) == ["old", "new", "third"])
        #expect(await harness.source.trackedIDsPerCall.count == fetches)
    }

    @Test func hiddenPullRequestsAreRemovedByDefault() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [older, third, newer]))
        harness.session.hide(newer)

        #expect(harness.dashboard?.myPRs.map(\.id) == ["third", "old"])
        #expect(harness.session.hiddenPullRequests.map(\.url) == [newer.url])
    }

    @Test func shownHiddenPullRequestsMoveToBottomKeepingOrder() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [older, third, newer]))
        harness.session.hide(newer)
        harness.session.hide(third)
        harness.settings.showHiddenPullRequests = true
        await harness.session.applySettingsChanged(refresh: true)

        #expect(harness.dashboard?.myPRs.map(\.id) == ["old", "new", "third"])
    }

    @Test func unhideRestoresPullRequestWhileOffline() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [older, newer]))
        harness.session.hide(newer)
        await harness.source.failNext(with: GitHubError.http(500, nil))
        harness.session.unhide(url: newer.url)

        #expect(harness.dashboard?.myPRs.map(\.id) == ["new", "old"])
        #expect(harness.session.hiddenPullRequests.isEmpty)
    }

    @Test func showingHiddenPullRequestsWorksWhileOffline() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [older, newer]))
        harness.session.hide(newer)
        await harness.source.failNext(with: GitHubError.http(500, nil))
        harness.settings.showHiddenPullRequests = true
        await harness.session.applySettingsChanged()

        #expect(harness.dashboard?.myPRs.map(\.id) == ["old", "new"])
    }

    @Test func failedManualRefreshKeepsDashboardAndShowsError() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [older]))
        await harness.source.failNext(with: GitHubError.http(500, nil))
        await harness.session.refresh()

        #expect(harness.dashboard?.myPRs.map(\.id) == ["old"])
        #expect(harness.session.refreshError != nil)

        await harness.session.refresh()
        #expect(harness.session.refreshError == nil)
    }

    @Test func pendingMergedRowStaysUntilRead() async {
        let harness = SessionHarness()
        let open = makePR("A")
        let merged = makePR("A", isMerged: true, updatedAt: "2026-01-05T00:00:00Z")
        await harness.load(makeDashboard(mine: [open]))
        await harness.load(makeDashboard(merged: [merged]))

        #expect(harness.dashboard?.myPRs.map(\.id) == ["A"])
        #expect(harness.dashboard?.myPRs.first?.isMerged == true)

        await harness.session.refresh()
        #expect(harness.dashboard?.myPRs.first?.isMerged == true)

        harness.session.markRead(prURL: merged.url)
        #expect(harness.dashboard?.myPRs.isEmpty == true)
        #expect(!harness.session.hasUnread)
    }

    private func saved<T: Decodable>(_ type: T.Type, _ base: String, in harness: SessionHarness) -> T? {
        harness.defaults.data(forKey: "accounts.octocat.\(base)").flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    @Test func mergedPullRequestLeavingTheMergedSearchIsForgotten() async {
        let harness = SessionHarness()
        let merged = makePR("A", isMerged: true, mergedAt: Date())
        await harness.load(makeDashboard(merged: [merged]))
        #expect(saved(Set<String>.self, Session.mergedKey, in: harness) == ["A"])

        await harness.load(makeDashboard(merged: []))

        #expect(saved(Set<String>.self, Session.mergedKey, in: harness) == [])
    }

    @Test func hidingPendingMergedRowForgetsIt() async {
        let harness = SessionHarness()
        let merged = makePR("A", isMerged: true, updatedAt: "2026-01-05T00:00:00Z")
        await harness.load(makeDashboard(mine: [makePR("A")]))
        await harness.load(makeDashboard(merged: [merged]))
        #expect(saved([PullRequest].self, Session.pendingMergedPullRequestsKey, in: harness)?.map(\.id) == ["A"])

        harness.session.hide(merged)

        #expect(saved([PullRequest].self, Session.pendingMergedPullRequestsKey, in: harness)?.isEmpty == true)
    }

    @Test func mergedPullRequestsNeverEnterReviewRequested() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [makePR("A")]))
        await harness.load(makeDashboard(merged: [makePR("A", isMerged: true)]))

        #expect(harness.dashboard?.reviewRequests.isEmpty == true)
    }

    @Test func backgroundRefreshPassesTrackedPullRequestIDs() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [older, newer]))
        await harness.session.backgroundRefresh()

        let calls = await harness.source.trackedIDsPerCall
        #expect(calls.last == ["new", "old"])
    }

    @Test func rateLimitPausesBackgroundRefreshUntilReset() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [older]))
        await harness.source.failNext(with: GitHubError.rateLimited(until: Date().addingTimeInterval(3600)))
        await harness.session.backgroundRefresh()
        let callsAfterLimit = await harness.source.trackedIDsPerCall.count

        await harness.session.backgroundRefresh()

        #expect(await harness.source.trackedIDsPerCall.count == callsAfterLimit)
        #expect(harness.dashboard?.myPRs.map(\.id) == ["old"])
    }

    @Test func backgroundRefreshResumesAfterReset() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [older]))
        await harness.source.failNext(with: GitHubError.rateLimited(until: Date().addingTimeInterval(-1)))
        await harness.session.backgroundRefresh()
        let callsAfterLimit = await harness.source.trackedIDsPerCall.count

        await harness.session.backgroundRefresh()

        #expect(await harness.source.trackedIDsPerCall.count == callsAfterLimit + 1)
    }

    @Test func failedBackgroundRefreshKeepsDashboardAndShowsError() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [older]))
        await harness.source.failNext(with: GitHubError.http(500, nil))
        await harness.session.backgroundRefresh()

        #expect(harness.dashboard?.myPRs.map(\.id) == ["old"])
        #expect(harness.session.refreshError != nil)

        await harness.session.backgroundRefresh()
        #expect(harness.session.refreshError == nil)
    }

    @Test func revokedTokenReturnsToSignInAndKeepsLocalState() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [older, newer]))
        harness.session.hide(newer)
        await harness.source.failNext(with: GitHubError.http(401, "Bad credentials"))
        await harness.session.backgroundRefresh()
        let callsAfterRevoke = await harness.source.trackedIDsPerCall.count

        if case .signedOut = harness.session.state {} else {
            Issue.record("Expected signed-out state")
        }
        #expect(harness.session.refreshError != nil)
        #expect(harness.session.hiddenPullRequests.map(\.url) == [newer.url])

        await harness.session.refresh()
        #expect(await harness.source.trackedIDsPerCall.count == callsAfterRevoke)
    }

    @Test func olderResponseArrivingLastIsDropped() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [older]))
        await harness.source.enqueue(makeDashboard(mine: [older]))
        await harness.source.enqueue(makeDashboard(mine: [older, newer]))
        await harness.source.holdNext(2)

        let first = Task { await harness.session.refresh() }
        await harness.source.waitForHeld(1)
        let second = Task { await harness.session.refresh() }
        await harness.source.waitForHeld(2)
        await harness.source.release(1)
        await second.value
        await harness.source.release(0)
        await first.value

        #expect(harness.dashboard?.myPRs.map(\.id) == ["new", "old"])
    }

    @Test func refreshFinishingAfterSignOutIsDropped() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [older]))
        await harness.source.enqueue(makeDashboard(mine: [older, newer]))
        await harness.source.holdNext(1)

        let refresh = Task { await harness.session.refresh() }
        await harness.source.waitForHeld(1)
        harness.session.signOut()
        await harness.source.release(0)
        await refresh.value

        if case .signedOut = harness.session.state {} else {
            Issue.record("Expected signed-out state")
        }
        #expect(harness.defaults.object(forKey: "accounts.octocat.lastMyPullRequestIDs") == nil)
    }

    @Test func eachAccountKeepsItsOwnState() async {
        let requestA = makePR("req-a", createdAt: "2026-01-02T00:00:00Z", updatedAt: "2026-01-02T00:00:00Z")
        let requestA2 = makePR("req-a2", createdAt: "2026-01-04T00:00:00Z", updatedAt: "2026-01-04T00:00:00Z")
        let requestB = makePR("req-b", createdAt: "2026-01-03T00:00:00Z", updatedAt: "2026-01-03T00:00:00Z")
        let harness = SessionHarness()
        await harness.load(makeDashboard(viewer: "alice", mine: [older], reviews: [requestA]))
        harness.session.hide(older)

        await harness.source.enqueue(makeDashboard(viewer: "bob", mine: [newer], reviews: [requestB]))
        await harness.session.refresh()

        #expect(harness.notifier.posts.isEmpty)
        #expect(harness.session.hiddenPullRequests.isEmpty)
        #expect(await harness.source.trackedIDsPerCall.last == [])
        #expect(harness.dashboard?.myPRs.map(\.id) == ["new"])

        await harness.source.enqueue(makeDashboard(viewer: "alice", mine: [older], reviews: [requestA, requestA2]))
        await harness.session.refresh()

        #expect(harness.session.hiddenPullRequests.map(\.url) == [older.url])
        #expect(harness.notifier.posts == [.reviewRequest("req-a2")])
        #expect(await harness.source.trackedIDsPerCall.last == ["old"])
    }

    @Test func firstAccountAdoptsStateFromBeforeAccounts() async throws {
        let defaults = makeDefaults()
        let hidden = Session.HiddenPullRequest(url: older.url, title: older.title, repository: older.repository, number: older.number)
        defaults.set(try JSONEncoder().encode([hidden]), forKey: "hiddenPullRequests")
        defaults.set(try JSONEncoder().encode(Set(["merged-before"])), forKey: "knownMergedIDs")
        let harness = SessionHarness(defaults: defaults)
        await harness.load(makeDashboard(mine: [older, newer]))

        #expect(harness.session.hiddenPullRequests.map(\.url) == [older.url])
        #expect(harness.dashboard?.myPRs.map(\.id) == ["new"])
        #expect(defaults.object(forKey: "hiddenPullRequests") == nil)
        #expect(defaults.object(forKey: "accounts.octocat.hiddenPullRequests") != nil)
        #expect(defaults.object(forKey: "knownMergedIDs") == nil)
        #expect(defaults.object(forKey: "accounts.octocat.knownMergedIDs") != nil)
    }

    @Test func selectedScopeWithNoValidRepositoryShowsNothingWithoutFetching() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [older], reviews: [newer]))
        let callsBefore = await harness.source.trackedIDsPerCall.count
        harness.settings.selectedRepositoriesText = "not-a-repo"
        harness.settings.repositoryScope = .selected
        await harness.session.applySettingsChanged(refresh: true)
        await harness.session.backgroundRefresh()

        #expect(await harness.source.trackedIDsPerCall.count == callsBefore)
        #expect(harness.dashboard?.myPRs.isEmpty == true)
        #expect(harness.dashboard?.reviewRequests.isEmpty == true)
        #expect(harness.dashboard?.viewer == "octocat")
    }

    @Test func pullRequestLeavingTheDashboardDropsItsUnreadState() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [older]))
        let commented = makePR("old", activity: [comment(by: "hubot", at: "2026-01-10T00:00:00Z")])
        await harness.source.enqueue(makeDashboard(mine: [commented]))
        await harness.session.refresh()
        #expect(harness.badge.last == "1")

        await harness.source.enqueue(makeDashboard(mine: []))
        await harness.session.refresh()

        #expect(harness.session.unreadPRURLs.isEmpty)
        #expect(harness.session.unreadNotificationsByURL.isEmpty)
        #expect(harness.badge.last == nil)
    }

    @Test func hidingAndRestoringUnreadPullRequestUpdatesDockBadge() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [older]))
        let commented = makePR("old", activity: [comment(by: "hubot", at: "2026-01-10T00:00:00Z")])
        await harness.source.enqueue(makeDashboard(mine: [commented]))
        await harness.session.refresh()
        #expect(harness.badge.last == "1")

        harness.session.hide(commented)
        #expect(harness.badge.last == nil)

        let commentedAgain = makePR("old", activity: [
            comment(by: "hubot", at: "2026-01-10T00:00:00Z"),
            comment(by: "hubot", at: "2026-01-11T00:00:00Z"),
        ])
        await harness.source.enqueue(makeDashboard(mine: [commentedAgain]))
        await harness.session.refresh()
        #expect(harness.badge.last == nil)

        harness.session.unhide(url: commentedAgain.url)
        #expect(harness.badge.last == "1")

        harness.session.hide(commentedAgain)
        #expect(harness.badge.last == nil)
        var thirdComment = commentedAgain
        thirdComment.activity.append(comment(by: "hubot", at: "2026-01-12T00:00:00Z"))
        await harness.source.enqueue(makeDashboard(mine: [thirdComment]))
        await harness.session.refresh()
        harness.session.unhideAll()
        #expect(harness.badge.last == "1")
    }

    @Test func signOutClearsPersistedState() async {
        let harness = SessionHarness()
        await harness.load(makeDashboard(mine: [older]))
        harness.session.hide(older)
        harness.session.signOut()

        for key in ["lastActivityAt", "unreadURLs", "unreadNotifications", "knownMergedIDs",
                    "pendingMergedPullRequests", "lastMyPullRequestIDs", "hiddenPullRequests"] {
            #expect(harness.defaults.object(forKey: "accounts.octocat.\(key)") == nil, "\(key) should be cleared")
        }
        if case .signedOut = harness.session.state {} else {
            Issue.record("Expected signed-out state")
        }
    }
}
