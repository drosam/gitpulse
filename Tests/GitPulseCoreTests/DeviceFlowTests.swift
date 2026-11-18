import Foundation
import Synchronization
import Testing
@testable import GitPulseCore

/// Scripted HTTP responses plus recorded sleeps for `DeviceFlow`.
private final class FlowScript: Sendable {
    private let responses: Mutex<[(Int, String)]>
    private let sleeps = Mutex<[Duration]>([])
    private let clock: Mutex<Date>
    private let tick: TimeInterval

    init(_ responses: [(Int, String)], tick: TimeInterval = 0) {
        self.responses = Mutex(responses)
        clock = Mutex(Date(timeIntervalSince1970: 0))
        self.tick = tick
    }

    var recordedSleeps: [Duration] { sleeps.withLock { $0 } }

    var flow: DeviceFlow {
        DeviceFlow(
            transport: { request in
                let (status, body) = self.responses.withLock { $0.isEmpty ? (500, "{}") : $0.removeFirst() }
                if status == 0 { throw URLError(.notConnectedToInternet) }
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                return (Data(body.utf8), response)
            },
            sleep: { duration in self.sleeps.withLock { $0.append(duration) } },
            now: { self.clock.withLock { now in
                defer { now = now.addingTimeInterval(self.tick) }
                return now
            } }
        )
    }
}

private let authorization = DeviceFlow.Authorization(
    deviceCode: "device",
    userCode: "ABCD-1234",
    verificationUri: URL(string: "https://github.com/login/device")!,
    interval: 5,
    expiresIn: 900
)

struct DeviceFlowTests {
    @Test func requestCodeDecodesAuthorization() async throws {
        let script = FlowScript([(200, #"{"device_code":"dc","user_code":"WXYZ-0000","verification_uri":"https://github.com/login/device","interval":5,"expires_in":900}"#)])
        let auth = try await script.flow.requestCode()
        #expect(auth.userCode == "WXYZ-0000")
        #expect(auth.deviceCode == "dc")
        #expect(auth.verificationUri == URL(string: "https://github.com/login/device"))
    }

    @Test func pollsUntilTokenArrives() async throws {
        let script = FlowScript([
            (200, #"{"error":"authorization_pending"}"#),
            (200, #"{"error":"authorization_pending"}"#),
            (200, #"{"access_token":"gho_test"}"#),
        ])
        let token = try await script.flow.pollForToken(authorization)
        #expect(token == "gho_test")
        #expect(script.recordedSleeps == [.seconds(5), .seconds(5), .seconds(5)])
    }

    @Test func slowDownUsesServerInterval() async throws {
        let script = FlowScript([
            (200, #"{"error":"slow_down","interval":10}"#),
            (200, #"{"error":"slow_down"}"#),
            (200, #"{"access_token":"gho_test"}"#),
        ])
        _ = try await script.flow.pollForToken(authorization)
        #expect(script.recordedSleeps == [.seconds(5), .seconds(10), .seconds(15)])
    }

    @Test func pollingRetriesNetworkAndServerErrors() async throws {
        let script = FlowScript([
            (0, ""),
            (502, "<html>bad gateway</html>"),
            (200, #"{"access_token":"gho_test"}"#),
        ])
        let token = try await script.flow.pollForToken(authorization)
        #expect(token == "gho_test")
    }

    @Test func pollingStillFailsOnClientErrors() async {
        let script = FlowScript([(400, #"{"error":"bad_request"}"#)])
        await #expect(throws: DeviceFlow.FlowError.unexpected("HTTP 400: bad_request")) {
            try await script.flow.pollForToken(authorization)
        }
    }

    @Test func accessDeniedThrows() async {
        let script = FlowScript([(200, #"{"error":"access_denied"}"#)])
        await #expect(throws: DeviceFlow.FlowError.denied) {
            try await script.flow.pollForToken(authorization)
        }
    }

    @Test func expiredTokenThrows() async {
        let script = FlowScript([(200, #"{"error":"expired_token"}"#)])
        await #expect(throws: DeviceFlow.FlowError.expired) {
            try await script.flow.pollForToken(authorization)
        }
    }

    @Test func deadlinePassingThrowsExpired() async {
        let pending = Array(repeating: (200, #"{"error":"authorization_pending"}"#), count: 10)
        let script = FlowScript(pending, tick: 400)
        await #expect(throws: DeviceFlow.FlowError.expired) {
            try await script.flow.pollForToken(authorization)
        }
    }

    @Test func unknownErrorIsReported() async {
        let script = FlowScript([(200, #"{"error":"incorrect_client_credentials"}"#)])
        await #expect(throws: DeviceFlow.FlowError.unexpected("incorrect_client_credentials")) {
            try await script.flow.pollForToken(authorization)
        }
    }

    @Test func httpErrorsDoNotEchoRawBodies() async {
        let html = FlowScript([(503, "<html>internal upstream detail</html>")])
        await #expect(throws: DeviceFlow.FlowError.unexpected("HTTP 503")) {
            try await html.flow.requestCode()
        }

        let json = FlowScript([(400, #"{"error":"bad_request","error_description":"Bad client id"}"#)])
        await #expect(throws: DeviceFlow.FlowError.unexpected("HTTP 400: Bad client id")) {
            try await json.flow.requestCode()
        }
    }
}
