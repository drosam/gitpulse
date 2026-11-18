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

    @Test func requestedReviewIDsComeOnlyFromReviewRequestedSearch() throws {
        // PR_C is requested; PR_A is requested but already in My pull requests; PR_E is only reviewed.
        #expect(try decode().requestedReviewIDs == ["PR_C"])
    }

    @Test func approvedPullRequestReturnsWhenReviewIsRequestedAgain() throws {
        var envelope = try #require(try JSONSerialization.jsonObject(with: fixture("dashboard")) as? [String: Any])
        var data = try #require(envelope["data"] as? [String: Any])
        let reviewed = try #require(data["reviewed"] as? [String: Any])
        let approved = try #require((reviewed["nodes"] as? [[String: Any]])?.first { $0["id"] as? String == "PR_D" })
        var requested = try #require(data["reviews"] as? [String: Any])
        requested["nodes"] = (requested["nodes"] as? [Any] ?? []) + [approved]
        data["reviews"] = requested
        envelope["data"] = data

        let dashboard = try GitHubClient.decodeDashboard(JSONSerialization.data(withJSONObject: envelope))
        #expect(dashboard.reviewRequests.map(\.id).sorted() == ["PR_C", "PR_D", "PR_E"])
    }

    @Test func recentlyMergedCombinesSearchesAndTrackedMergedNodes() throws {
        let merged = try decode().recentlyMerged
        #expect(merged.map(\.id) == ["PR_M2", "PR_M1"])
        #expect(merged.allSatisfy { $0.isMerged })
    }

    /// The dashboard fixture with `tracked` replaced and the given GraphQL errors added.
    private func partialResponse(tracked: [Any], errors: [[String: Any]]) throws -> Data {
        var envelope = try #require(try JSONSerialization.jsonObject(with: fixture("dashboard")) as? [String: Any])
        var data = try #require(envelope["data"] as? [String: Any])
        data["tracked"] = tracked
        envelope["data"] = data
        envelope["errors"] = errors
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    @Test func unresolvableTrackedPullRequestIsIgnored() throws {
        let data = try partialResponse(tracked: [NSNull()], errors: [[
            "type": "NOT_FOUND",
            "path": ["tracked", 0],
            "message": "Could not resolve to a node with the global id of 'PR_GONE'",
        ]])
        let dashboard = try GitHubClient.decodeDashboard(data)
        #expect(dashboard.myPRs.map(\.id) == ["PR_B", "PR_A"])
    }

    @Test func partialErrorsOutsideTrackedStillThrow() throws {
        let data = try partialResponse(tracked: [], errors: [[
            "path": ["mine"],
            "message": "Search failed",
        ]])
        #expect(throws: GitHubError.graphQL(["Search failed"])) {
            try GitHubClient.decodeDashboard(data)
        }
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

    private func response(_ headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.github.com/graphql")!, statusCode: 200, httpVersion: nil, headerFields: headers)!
    }

    @Test func exhaustedBudgetResumesAtReset() {
        let now = Date(timeIntervalSince1970: 1_000)
        let headers = ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "4600"]
        #expect(GitHubClient.rateLimitResume(from: response(headers), now: now) == Date(timeIntervalSince1970: 4_600))
    }

    @Test func retryAfterResumesAfterDelay() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(GitHubClient.rateLimitResume(from: response(["retry-after": "60"]), now: now) == Date(timeIntervalSince1970: 1_060))
    }

    @Test func remainingBudgetIsNotRateLimited() {
        let headers = ["x-ratelimit-remaining": "12", "x-ratelimit-reset": "4600"]
        #expect(GitHubClient.rateLimitResume(from: response(headers), now: Date()) == nil)
    }
}
