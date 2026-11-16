import Foundation
import Testing
@testable import GitPulseCore

struct DashboardDecodingTests {
    private func decode() throws -> Dashboard {
        try GitHubClient.decodeDashboard(fixture("dashboard"))
    }

    @Test func decodesViewer() throws {
        #expect(try decode().viewer == "octocat")
    }

    @Test func myPullRequestsDedupeAuthoredAndAssignedNewestFirst() throws {
        let dashboard = try decode()
        #expect(dashboard.myPRs.map(\.id) == ["PR_B", "PR_A"])
    }

    @Test func mapsPullRequestFields() throws {
        let pr = try #require(try decode().myPRs.first { $0.id == "PR_A" })
        #expect(pr.number == 101)
        #expect(pr.title == "Add dark mode toggle")
        #expect(pr.url == URL(string: "https://github.com/acme/web/pull/101"))
        #expect(pr.repository == "acme/web")
        #expect(pr.author == "octocat")
        #expect(pr.headBranch == "feature/dark-mode")
        #expect(pr.isDraft == false)
        #expect(pr.isMerged == false)
        #expect(pr.reviewDecision == .approved)
        #expect(pr.checkState == .success)
        #expect(pr.labels == [PullRequest.Label(name: "ui", color: "1d76db")])
        #expect(pr.commentCount == 4)
        #expect(pr.additions == 120)
        #expect(pr.deletions == 8)
        #expect(pr.createdAt == date("2026-01-10T09:00:00Z"))
        #expect(pr.updatedAt == date("2026-01-12T10:00:00Z"))
    }

    @Test func mapsDraftMergeQueueAndCreatedAtFallback() throws {
        let pr = try #require(try decode().myPRs.first { $0.id == "PR_B" })
        #expect(pr.isDraft)
        #expect(pr.isInMergeQueue)
        #expect(pr.mergeQueueState == "QUEUED")
        #expect(pr.checkState == .pending)
        #expect(pr.author == "ghost")
        #expect(pr.createdAt == pr.updatedAt)
    }

    @Test func activityMergesCommentsReviewsAndInlineThreadsOldestFirst() throws {
        let pr = try #require(try decode().myPRs.first { $0.id == "PR_A" })
        #expect(pr.activity == [
            .init(kind: .comment, author: "hubot", createdAt: date("2026-01-11T08:00:00Z")),
            .init(kind: .comment, author: "monalisa", createdAt: date("2026-01-11T12:00:00Z")),
            .init(kind: .review(state: "APPROVED"), author: "monalisa", createdAt: date("2026-01-12T09:00:00Z")),
        ])
    }

    @Test func reviewRequestsApplyPaneRules() throws {
        // PR_C: requested + commented (deduped). PR_E: viewer's latest review is CHANGES_REQUESTED.
        // PR_D: viewer's latest review is APPROVED. PR_A: already in My pull requests.
        #expect(try decode().reviewRequests.map(\.id) == ["PR_E", "PR_C"])
    }

    @Test func recentlyMergedCombinesSearchesAndTrackedMergedNodes() throws {
        let merged = try decode().recentlyMerged
        #expect(merged.map(\.id) == ["PR_M2", "PR_M1"])
        #expect(merged.allSatisfy { $0.isMerged })
    }

    @Test func graphQLErrorsThrow() throws {
        let data = Data(#"{"data": null, "errors": [{"message": "Something broke"}]}"#.utf8)
        #expect(throws: GitHubError.graphQL(["Something broke"])) {
            try GitHubClient.decodeDashboard(data)
        }
    }

    @Test func emptyPayloadThrows() throws {
        #expect(throws: GitHubError.graphQL(["empty response"])) {
            try GitHubClient.decodeDashboard(Data(#"{"data": null}"#.utf8))
        }
    }
}

struct GitHubErrorTests {
    @Test func usesGitHubMessageWhenPresent() {
        let error = GitHubError.http(status: 401, body: Data(#"{"message": "Bad credentials"}"#.utf8))
        #expect(error.localizedDescription == "GitHub returned HTTP 401: Bad credentials")
    }

    @Test func omitsNonJSONBodies() {
        let error = GitHubError.http(status: 502, body: Data("<html>secret upstream page</html>".utf8))
        #expect(error.localizedDescription == "GitHub returned HTTP 502")
    }
}
