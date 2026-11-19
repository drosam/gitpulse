import Foundation
import Synchronization
import Testing
@testable import GitPulseCore

/// Records the request and answers with a canned response.
private final class ClientScript: Sendable {
    private let status: Int
    private let headers: [String: String]
    private let body: Data
    private let recorded = Mutex<URLRequest?>(nil)

    init(status: Int, headers: [String: String] = [:], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    var request: URLRequest? { recorded.withLock { $0 } }

    var sentJSON: [String: Any] {
        guard let data = request?.httpBody,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    var query: String { sentJSON["query"] as? String ?? "" }
    var variables: [String: Any] { sentJSON["variables"] as? [String: Any] ?? [:] }

    func client(repositories: [String] = [], tracked: [PullRequest.ID] = []) -> GitHubClient {
        GitHubClient(token: "gho_test", repositories: repositories, trackedPullRequestIDs: tracked, transport: { request in
            self.recorded.withLock { $0 = request }
            let response = HTTPURLResponse(url: request.url!, statusCode: self.status, httpVersion: nil, headerFields: self.headers)!
            return (self.body, response)
        })
    }
}

struct GitHubClientTests {
    @Test func fetchSendsTokenFiltersAndTrackedIDs() async throws {
        let script = ClientScript(status: 200, body: try fixture("dashboard"))

        let dashboard = try await script.client(repositories: ["acme/web"], tracked: ["PR_tracked"]).fetchDashboard()

        #expect(!dashboard.viewer.isEmpty)
        #expect(script.request?.url == URL(string: "https://api.github.com/graphql"))
        #expect(script.request?.value(forHTTPHeaderField: "Authorization") == "Bearer gho_test")
        #expect(script.variables["mine"] as? String == "is:pr is:open author:@me archived:false sort:updated-desc repo:acme/web")
        for search in ["mine", "assigned", "reviews", "reviewed", "commented"] {
            #expect((script.variables[search] as? String)?.contains("sort:updated-desc") == true)
        }
        #expect(script.query.components(separatedBy: "issueCount").count - 1 == 5)
        #expect(script.variables["tracked"] as? [String] == ["PR_tracked"])
        #expect(!script.query.contains("acme/web"))
        #expect(!script.query.contains("PR_tracked"))
    }

    @Test func nonOKStatusThrowsHTTPError() async {
        let script = ClientScript(status: 502, body: Data("<html>bad gateway</html>".utf8))
        do {
            _ = try await script.client().fetchDashboard()
            Issue.record("Expected an error")
        } catch GitHubError.http(let status, _) {
            #expect(status == 502)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func exhaustedRateLimitThrowsRateLimited() async {
        let script = ClientScript(
            status: 403,
            headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1800000000"],
            body: Data(#"{"message":"API rate limit exceeded"}"#.utf8)
        )
        await #expect(throws: GitHubError.rateLimited(until: Date(timeIntervalSince1970: 1_800_000_000))) {
            try await script.client().fetchDashboard()
        }
    }
}
