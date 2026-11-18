import Foundation
import Synchronization
import Testing
@testable import GitPulseCore

/// Holds a request until `open()`.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// Device flow where code N is "dcN"; "dc1" polls wait on `firstPoll` then expire, later codes succeed.
private final class SignInScript: Sendable {
    let firstPoll = Gate()
    private let codeRequests = Mutex(0)

    var flow: DeviceFlow {
        DeviceFlow(
            transport: { request in
                let body: String
                if request.url!.path.hasSuffix("device/code") {
                    let n = self.codeRequests.withLock { $0 += 1; return $0 }
                    body = #"{"device_code":"dc\#(n)","user_code":"CODE-\#(n)","verification_uri":"https://github.com/login/device","interval":5,"expires_in":900}"#
                } else if String(data: request.httpBody ?? Data(), encoding: .utf8)!.contains("\"dc1\"") {
                    await self.firstPoll.wait()
                    body = #"{"error":"expired_token"}"#
                } else {
                    body = #"{"access_token":"gho_new"}"#
                }
                return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            sleep: { _ in }
        )
    }
}

@MainActor
struct SessionSignInTests {
    /// A `gh` CLI token survives `clear()`, like the real provider.
    private let cliTokens = TokenProvider(
        resolve: { ResolvedToken(token: "cli-token", source: .githubCLI) },
        save: { _ in },
        clear: {}
    )

    @Test func startReportsTokenSource() async {
        let harness = SessionHarness(tokens: cliTokens)
        await harness.load(makeDashboard())

        #expect(harness.session.tokenSource == .githubCLI)
        #expect(harness.dashboard?.viewer == "octocat")
    }

    @Test func signOutSticksWhenTokenComesFromOutsideGitPulse() async {
        let defaults = makeDefaults()
        let harness = SessionHarness(defaults: defaults, tokens: cliTokens)
        await harness.load(makeDashboard())
        harness.session.signOut()
        let callsAfterSignOut = await harness.source.trackedIDsPerCall.count

        await harness.session.start()
        let relaunched = SessionHarness(defaults: defaults, tokens: cliTokens)
        await relaunched.session.start()

        if case .signedOut = harness.session.state {} else { Issue.record("Expected signed-out state") }
        if case .signedOut = relaunched.session.state {} else { Issue.record("Expected signed-out state after relaunch") }
        #expect(await harness.source.trackedIDsPerCall.count == callsAfterSignOut)
        #expect(await relaunched.source.trackedIDsPerCall.isEmpty)
        #expect(harness.session.tokenSource == nil)
        #expect(harness.session.externalTokenSource == .githubCLI)
    }

    private func waitForCode(_ code: String, in session: Session) async {
        while true {
            if case .authorizing(let authorization) = session.state, authorization.userCode == code { return }
            await Task.yield()
        }
    }

    private func noToken() -> TokenProvider {
        TokenProvider(resolve: { nil }, save: { _ in }, clear: {})
    }

    @Test func supersededSignInExpiringLaterKeepsTheDashboard() async {
        let script = SignInScript()
        let harness = SessionHarness(tokens: noToken(), deviceFlow: script.flow)
        await harness.source.enqueue(makeDashboard())
        let first = Task { await harness.session.signIn() }
        await waitForCode("CODE-1", in: harness.session)

        await harness.session.start()
        if case .authorizing = harness.session.state {} else { Issue.record("Reopening the window left the code screen") }

        await harness.session.signIn()
        #expect(harness.dashboard?.viewer == "octocat")
        await script.firstPoll.open()
        await first.value

        #expect(harness.dashboard?.viewer == "octocat")
    }

    @Test func cancelledSignInReturnsToSignInScreen() async {
        let script = SignInScript()
        let harness = SessionHarness(tokens: noToken(), deviceFlow: script.flow)
        let signIn = Task { await harness.session.signIn() }
        await waitForCode("CODE-1", in: harness.session)

        harness.session.cancelSignIn()
        await script.firstPoll.open()
        await signIn.value

        if case .signedOut = harness.session.state {} else { Issue.record("Expected signed-out state") }
    }

    @Test func usingTheExternalTokenSignsBackIn() async {
        let defaults = makeDefaults()
        let harness = SessionHarness(defaults: defaults, tokens: cliTokens)
        await harness.load(makeDashboard())
        harness.session.signOut()

        await harness.session.useExternalToken()

        #expect(harness.dashboard?.viewer == "octocat")
        #expect(harness.session.tokenSource == .githubCLI)
        let relaunched = SessionHarness(defaults: defaults, tokens: cliTokens)
        await relaunched.load(makeDashboard())
        #expect(relaunched.dashboard != nil)
    }
}
