import AppKit
import SwiftUI
import Testing
@testable import GitPulseCore

@MainActor
struct DemoModeTests {
    @Test func demoSessionLoadsFixturesWithUnreadState() async throws {
        let (session, _) = DemoMode.makeSessionAndSettings(defaults: makeDefaults())
        await session.start()

        guard case .ready(let dashboard) = session.state else {
            Issue.record("Demo session should be ready, got \(session.state)")
            return
        }
        #expect(dashboard.viewer == DemoData.viewer)
        #expect(dashboard.myPRs.contains { $0.isMerged })
        #expect(dashboard.myPRs.contains { $0.isDraft })
        #expect(dashboard.myPRs.contains { $0.isInMergeQueue })
        #expect(!dashboard.reviewRequests.isEmpty)
        #expect(session.hasUnread)
    }

    @Test func demoDataUsesOnlyGitHubURLs() {
        let dashboard = DemoData.dashboard()
        let all = dashboard.myPRs + dashboard.reviewRequests + dashboard.recentlyMerged
        #expect(all.allSatisfy { SafeURL.isAllowed($0.url) })
    }
}

/// Render-smoke only: views build and draw with demo data in both appearances.
@MainActor
struct RenderSmokeTests {
    private func render(_ view: some View, scheme: ColorScheme) -> NSImage? {
        let renderer = ImageRenderer(content: view
            .environment(\.colorScheme, scheme)
            .frame(width: 900, height: 520))
        renderer.scale = 1
        return renderer.nsImage
    }

    private func demo() async -> (Session, AppSettings, Dashboard) {
        let (session, settings) = DemoMode.makeSessionAndSettings(defaults: makeDefaults())
        await session.start()
        guard case .ready(let dashboard) = session.state else { return (session, settings, DemoData.dashboard()) }
        return (session, settings, dashboard)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func dashboardRenders(_ scheme: ColorScheme) async throws {
        let (session, settings, dashboard) = await demo()
        let image = try #require(render(
            DashboardView(dashboard: dashboard).environment(session).environment(settings),
            scheme: scheme
        ))
        #expect(image.size.width > 0 && image.size.height > 0)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func pullRequestListRenders(_ scheme: ColorScheme) async throws {
        let (session, settings, dashboard) = await demo()
        struct Host: View {
            var session: Session
            var dashboard: Dashboard
            @FocusState private var focus: DashboardView.KeyFocus?

            var body: some View {
                PRListView(
                    title: "My pull requests",
                    systemImage: "arrow.triangle.pull",
                    pullRequests: dashboard.myPRs,
                    unreadURLs: session.unreadPRURLs,
                    unreadNotifications: session.unreadNotificationsByURL,
                    isActive: true,
                    selectedID: .constant(dashboard.myPRs.first?.id),
                    keyFocus: $focus,
                    focusValue: .pane(.mine)
                )
            }
        }
        let list = Host(session: session, dashboard: dashboard)
        let image = try #require(render(list.environment(session).environment(settings), scheme: scheme))
        #expect(image.size.width > 0 && image.size.height > 0)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func rowsRenderEveryDemoState(_ scheme: ColorScheme) async throws {
        let (session, settings, dashboard) = await demo()
        let rows = VStack {
            ForEach(dashboard.myPRs + dashboard.reviewRequests) { pr in
                PRRow(pullRequest: pr, hasNotification: session.unreadPRURLs.contains(pr.url))
            }
        }
        let image = try #require(render(rows.environment(session).environment(settings), scheme: scheme))
        #expect(image.size.width > 0 && image.size.height > 0)
    }

    @Test func settingsRenders() async throws {
        let (session, settings, _) = await demo()
        let image = try #require(render(SettingsView().environment(session).environment(settings), scheme: .light))
        #expect(image.size.width > 0)
    }
}
