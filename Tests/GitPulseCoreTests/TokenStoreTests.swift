import Foundation
import Testing
@testable import GitPulseCore

struct TokenStoreTests {
    @Test func commandOutputTrimsStdout() {
        #expect(TokenStore.commandOutput("/bin/sh", ["-c", "echo ' gho_test '; echo noise >&2"], timeout: 5) == "gho_test")
    }

    @Test func commandOutputGivesUpOnSlowCommands() {
        let started = Date()
        #expect(TokenStore.commandOutput("/bin/sleep", ["5"], timeout: 0.2) == nil)
        #expect(Date().timeIntervalSince(started) < 2)
    }

    @Test func commandOutputIgnoresFailures() {
        #expect(TokenStore.commandOutput("/bin/sh", ["-c", "echo gho_test; exit 1"], timeout: 5) == nil)
    }
}
