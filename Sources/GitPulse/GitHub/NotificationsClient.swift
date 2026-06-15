import Foundation

/// One unread GitHub notification about a pull request.
struct PRNotification: Identifiable, Hashable, Sendable {
    var id: String // notification thread id
    var reason: String
    var title: String
    var repository: String
    var prURL: URL
    var updatedAt: Date
}

/// Polls `GET /notifications` (REST) with ETag conditional requests:
/// a 304 answer is free against the rate limit, so this can run forever.
struct NotificationsClient: Sendable {
    var token: String

    struct FetchResult: Sendable {
        /// nil when the server answered 304 Not Modified (nothing changed).
        var notifications: [PRNotification]?
        var etag: String?
        /// Server-requested minimum seconds between polls (X-Poll-Interval).
        var pollInterval: Int
    }

    // `participating=true` excludes watch-noise (e.g. `ci_activity` CheckSuite
    // notifications for repos you merely watch) which otherwise floods the first
    // page and buries review-requested / mention / assignment threads. CI status
    // for the PRs you actually care about is derived locally in Session from the
    // dashboard's check state, so nothing is lost by dropping the firehose here.
    private static let endpoint = URL(string: "https://api.github.com/notifications?participating=true")!

    func fetch(etag: String?) async throws -> FetchResult {
        var request = URLRequest(url: Self.endpoint)
        // URLCache would answer the conditional request itself; we want the raw 304.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        let pollInterval = http?.value(forHTTPHeaderField: "X-Poll-Interval").flatMap(Int.init) ?? 60

        if status == 304 {
            return FetchResult(notifications: nil, etag: etag, pollInterval: pollInterval)
        }
        guard status == 200 else {
            throw GitHubError.http(status, String(decoding: data, as: UTF8.self))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let threads = try decoder.decode([Thread].self, from: data)

        let notifications = threads.compactMap { thread -> PRNotification? in
            guard thread.unread,
                  thread.subject.type == "PullRequest",
                  let prURL = Self.htmlURL(forAPISubject: thread.subject.url) else { return nil }
            return PRNotification(
                id: thread.id,
                reason: thread.reason,
                title: thread.subject.title,
                repository: thread.repository.fullName,
                prURL: prURL,
                updatedAt: thread.updatedAt
            )
        }

        return FetchResult(
            notifications: notifications,
            etag: http?.value(forHTTPHeaderField: "Etag"),
            pollInterval: pollInterval
        )
    }

    /// Marks a notification thread read on GitHub. Best-effort; the next
    /// poll re-syncs either way.
    func markRead(threadID: String) async {
        guard let url = URL(string: "https://api.github.com/notifications/threads/\(threadID)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Subject URLs are API URLs (…/repos/owner/repo/pulls/42); the browser
    /// wants https://github.com/owner/repo/pull/42.
    private static func htmlURL(forAPISubject url: URL?) -> URL? {
        guard let parts = url?.pathComponents,
              parts.count >= 6, parts[1] == "repos", parts[4] == "pulls" else { return nil }
        return URL(string: "https://github.com/\(parts[2])/\(parts[3])/pull/\(parts[5])")
    }

    private struct Thread: Decodable {
        var id: String
        var reason: String
        var unread: Bool
        var updatedAt: Date
        var subject: Subject
        var repository: Repo

        struct Subject: Decodable {
            var title: String
            var url: URL?
            var type: String
        }

        struct Repo: Decodable {
            var fullName: String
        }
    }
}
