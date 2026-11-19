import Foundation
import Testing
@testable import GitPulseCore

@MainActor
struct AppSettingsTests {
    @Test func acceptsGitHubURLsAsRepositories() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.selectedRepositoriesText = """
        https://github.com/acme/web
        github.com/acme/api/pull/12
        https://github.com/acme/cli.git
        acme/web
        """

        #expect(settings.selectedRepositories == ["acme/web", "acme/api", "acme/cli"])
        #expect(settings.rejectedRepositoryEntries.isEmpty)
    }

    /// The validator is the only guard on names placed into the GraphQL search string.
    @Test(arguments: [#"acme/web""#, #"acme/we\b"#, "acme/web)", "org:acme/web", "acme/web/extra", "acme/{web}"])
    func rejectsEntriesThatCouldEscapeTheSearchQuery(_ entry: String) {
        let settings = AppSettings(defaults: makeDefaults())
        settings.selectedRepositoriesText = entry

        #expect(settings.selectedRepositories.isEmpty)
        #expect(settings.rejectedRepositoryEntries == [entry])
    }

    @Test func reportsRejectedEntries() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.selectedRepositoriesText = "acme/web\nhttps://gitlab.com/acme/web\nnot-a-repo"

        #expect(settings.selectedRepositories == ["acme/web"])
        #expect(settings.rejectedRepositoryEntries == ["https://gitlab.com/acme/web", "not-a-repo"])
    }
}
