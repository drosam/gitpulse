import Foundation
import Testing
@testable import GitPulseCore

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
