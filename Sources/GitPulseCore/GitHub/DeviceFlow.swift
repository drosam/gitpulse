import Foundation

/// GitHub OAuth device flow (RFC 8628).
///
/// Requires a registered OAuth app with "Device flow" enabled
/// (github.com/settings/developers). The client ID is public by design;
/// device flow needs no client secret.
struct DeviceFlow: Sendable {
    typealias Transport = HTTP.Transport

    static let clientID = "Ov23liJSAbMeX2jhuqpd"

    var transport: Transport = HTTP.live
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    var now: @Sendable () -> Date = { Date() }

    /// `repo` covers private-repo PR search; `read:org` lets search see org PRs.
    static let scopes = "repo read:org"

    struct Authorization: Decodable, Sendable {
        var deviceCode: String
        var userCode: String
        var verificationUri: URL
        var interval: Int
        var expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationUri = "verification_uri"
            case interval
            case expiresIn = "expires_in"
        }
    }

    enum FlowError: LocalizedError, Equatable {
        case denied
        case expired
        case unexpected(String)

        var errorDescription: String? {
            switch self {
            case .denied: return "Authorization was denied on GitHub."
            case .expired: return "The device code expired. Try signing in again."
            case .unexpected(let detail): return "Sign-in failed: \(detail)"
            }
        }
    }

    /// Step 1: request a user code to display.
    func requestCode() async throws -> Authorization {
        let authorization = try await post(
            url: URL(string: "https://github.com/login/device/code")!,
            body: ["client_id": Self.clientID, "scope": Self.scopes],
            as: Authorization.self
        )
        guard SafeURL.isAllowed(authorization.verificationUri) else {
            throw FlowError.unexpected("unexpected verification URL")
        }
        return authorization
    }

    /// Step 2: poll until the user approves in the browser. Returns the access token.
    func pollForToken(_ authorization: Authorization) async throws -> String {
        struct PollResponse: Decodable {
            var accessToken: String?
            var error: String?
            var interval: Int?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case error, interval
            }
        }

        var interval = max(authorization.interval, 5)
        let deadline = now().addingTimeInterval(TimeInterval(authorization.expiresIn))

        while now() < deadline {
            try await sleep(.seconds(interval))
            try Task.checkCancellation()

            let response: PollResponse
            do {
                response = try await post(
                    url: URL(string: "https://github.com/login/oauth/access_token")!,
                    body: [
                        "client_id": Self.clientID,
                        "device_code": authorization.deviceCode,
                        "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                    ],
                    as: PollResponse.self,
                    retryingServerErrors: true
                )
            } catch is URLError where !Task.isCancelled {
                continue
            } catch is ServerError {
                continue
            }

            if let token = response.accessToken {
                return token
            }
            switch response.error {
            case "authorization_pending":
                continue
            case "slow_down":
                interval = response.interval ?? interval + 5
            case "access_denied":
                throw FlowError.denied
            case "expired_token":
                throw FlowError.expired
            case let other?:
                throw FlowError.unexpected(other)
            case nil:
                throw FlowError.unexpected("no token and no error in response")
            }
        }
        throw FlowError.expired
    }

    private struct OAuthError: Decodable {
        var error: String?
        var errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    /// A 5xx while polling; the code stays valid, so polling carries on.
    private struct ServerError: Error {}

    private func post<T: Decodable>(url: URL, body: [String: String], as type: T.Type, retryingServerErrors: Bool = false) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await transport(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if retryingServerErrors, status >= 500 { throw ServerError() }
            let parsed = try? JSONDecoder().decode(OAuthError.self, from: data)
            if let detail = parsed?.errorDescription ?? parsed?.error {
                throw FlowError.unexpected("HTTP \(status): \(detail)")
            }
            throw FlowError.unexpected("HTTP \(status)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
