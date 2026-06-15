import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(Session.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .signedOut:
                SignInView()
            case .authorizing(let authorization):
                AuthorizingView(authorization: authorization)
            case .loading:
                ProgressView("Loading pull requests…")
            case .ready(let dashboard):
                DashboardView(dashboard: dashboard)
            case .failed(let message):
                ErrorView(message: message)
            }
        }
        .frame(minWidth: 760, minHeight: 420)
        .task { await session.start() }
    }
}

struct DashboardView: View {
    enum Pane { case mine, review }

    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var activePane: Pane = .mine
    @State private var mySelectedID: PullRequest.ID?
    @State private var reviewSelectedID: PullRequest.ID?
    var dashboard: Dashboard

    var body: some View {
        VStack(spacing: 0) {
            if Notifier.shared.authorizationDenied {
                NotificationPermissionBanner()
                Divider()
            }
            paneSplit
        }
        .background(KeyNavigator(
            onUp: { move(-1) },
            onDown: { move(1) },
            onLeft: { switchTo(.mine) },
            onRight: { switchTo(.review) },
            onReturn: openSelected
        ))
        .onAppear { selectFirstIfNeeded() }
        .toolbar {
            ToolbarItem {
                if session.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await session.refresh() }
                    }
                }
            }
        }
        .navigationTitle("GitPulse")
        .navigationSubtitle(dashboard.viewer)
    }

    private var paneSplit: some View {
        HSplitView {
            PRListView(
                title: "My pull requests",
                systemImage: "arrow.triangle.pull",
                pullRequests: dashboard.myPRs,
                unreadURLs: session.unreadPRURLs,
                isActive: activePane == .mine,
                selectedID: Binding(
                    get: { activePane == .mine ? mySelectedID : nil },
                    set: { mySelectedID = $0; activePane = .mine }
                )
            )
            PRListView(
                title: "Review requested",
                systemImage: "eye",
                pullRequests: dashboard.reviewRequests,
                unreadURLs: session.unreadPRURLs,
                isActive: activePane == .review,
                selectedID: Binding(
                    get: { activePane == .review ? reviewSelectedID : nil },
                    set: { reviewSelectedID = $0; activePane = .review }
                )
            )
        }
    }

    // MARK: - Keyboard navigation

    private var activePRs: [PullRequest] {
        activePane == .mine ? dashboard.myPRs : dashboard.reviewRequests
    }

    private var activeSelection: PullRequest.ID? {
        get { activePane == .mine ? mySelectedID : reviewSelectedID }
        nonmutating set {
            if activePane == .mine { mySelectedID = newValue } else { reviewSelectedID = newValue }
        }
    }

    /// Move selection within the active pane by `delta` rows, clamped to the ends.
    private func move(_ delta: Int) {
        let prs = activePRs
        guard !prs.isEmpty else { return }
        let current = prs.firstIndex { $0.id == activeSelection } ?? -1
        let next = max(0, min(prs.count - 1, current + delta))
        activeSelection = prs[next].id
    }

    /// Switch the focused pane, selecting its first row if nothing is selected yet.
    private func switchTo(_ pane: Pane) {
        activePane = pane
        let prs = activePRs
        if activeSelection == nil, let first = prs.first { activeSelection = first.id }
    }

    private func openSelected() {
        guard let pr = activePRs.first(where: { $0.id == activeSelection }) else { return }
        openURL(pr.url)
        session.markRead(prURL: pr.url)
    }

    private func selectFirstIfNeeded() {
        if mySelectedID == nil, let first = dashboard.myPRs.first { mySelectedID = first.id }
    }
}

/// Shown when macOS notification permission is denied — otherwise banners are
/// silently dropped and the user never learns why review alerts stopped.
struct NotificationPermissionBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(.orange)
            Text("Notifications are turned off, so review alerts won't appear.")
                .font(.system(size: 12))
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.system(size: 12))
            .buttonStyle(.link)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
    }
}

struct SignInView: View {
    @Environment(Session.self) private var session

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("GitPulse")
                .font(.title)
            Text("Track your pull requests and review requests on GitHub.")
                .foregroundStyle(.secondary)
            Button("Sign in with GitHub") {
                Task { await session.signIn() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct AuthorizingView: View {
    var authorization: DeviceFlow.Authorization

    var body: some View {
        VStack(spacing: 12) {
            Text("Enter this code on GitHub")
                .font(.headline)
            Text(authorization.userCode)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .textSelection(.enabled)
            Link("Open \(authorization.verificationUri.absoluteString)", destination: authorization.verificationUri)
            ProgressView()
                .controlSize(.small)
                .padding(.top, 8)
        }
        .padding()
    }
}

struct ErrorView: View {
    @Environment(Session.self) private var session
    var message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack {
                Button("Retry") {
                    Task { await session.start() }
                }
                Button("Sign out") {
                    session.signOut()
                }
            }
        }
        .padding()
    }
}
