import Foundation
import Testing
@testable import GitPulseCore

struct SafeURLTests {
    @Test(arguments: [
        "https://github.com/acme/web/pull/1",
        "https://GitHub.com/acme/web/pull/1",
    ])
    func allowsGitHubHTTPS(_ string: String) throws {
        #expect(SafeURL.isAllowed(try #require(URL(string: string))))
    }

    @Test(arguments: [
        "http://github.com/acme/web/pull/1",
        "https://github.com.evil.example/acme/web/pull/1",
        "https://gist.github.com/acme/1",
        "https://evil.example/?u=https://github.com",
        "file:///etc/passwd",
        "javascript:alert(1)",
        "x-apple.systempreferences:com.apple.preference.notifications",
    ])
    func rejectsEverythingElse(_ string: String) throws {
        #expect(!SafeURL.isAllowed(try #require(URL(string: string))))
    }
}
