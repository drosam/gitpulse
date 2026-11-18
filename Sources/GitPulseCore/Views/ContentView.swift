import AppKit
import SwiftUI

public struct ContentView: View {
    @Environment(Session.self) private var session

    public init() {}

    public var body: some View {
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
    enum KeyFocus: Hashable { case dashboard, pane(Pane) }

    @Environment(Session.self) private var session
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    @State private var activePane: Pane = .mine
    @State private var mySelectedID: PullRequest.ID?
    @State private var reviewSelectedID: PullRequest.ID?
    @State private var toastMessage: String?
    @State private var notificationPanelPR: PullRequest?
    @FocusState private var keyFocus: KeyFocus?
    var dashboard: Dashboard

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if Notifier.shared.authorizationDenied {
                    NotificationPermissionBanner()
                    Divider()
                }
                if let refreshError = session.refreshError {
                    RefreshErrorBanner(message: refreshError)
                    Divider()
                }
                paneSplit
            }

            if let notificationPanelPR {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(notificationPanelPR.repository)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(notificationPanelPR.title)
                                .font(.headline)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Button {
                            self.notificationPanelPR = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .background(Color.primary.opacity(0.08), in: Circle())
                        .keyboardShortcut(.cancelAction)
                    }
                    UnreadNotificationsView(notifications: notifications(for: notificationPanelPR), showsTitle: false)
                        .padding(-12)
                }
                .padding(16)
                .frame(width: 360)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.24), radius: 20, y: 8)
                .padding(.bottom, 20)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if let toastMessage {
                Text(toastMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.78), in: Capsule())
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: toastMessage)
        // Keys reach the dashboard only while it or one of its lists has focus.
        .focusable()
        .focusEffectDisabled()
        .focused($keyFocus, equals: .dashboard)
        .onKeyPress(phases: .down) { press in
            guard let command = DashboardKeyCommand.command(
                key: press.key, characters: press.characters, modifiers: press.modifiers
            ) else { return .ignored }
            perform(command)
            return .handled
        }
        .onCopyCommand(perform: copySelectedURL)
        .onChange(of: keyFocus) { _, focus in
            if case .pane(let pane) = focus { activePane = pane }
        }
        .onAppear {
            selectFirstIfNeeded()
            keyFocus = .dashboard
        }
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
        .navigationSubtitle(dashboard.viewer.isEmpty ? "" : dashboard.viewer.githubMention)
    }

    private var paneSplit: some View {
        HSplitView {
            PRListView(
                title: "My pull requests",
                systemImage: "arrow.triangle.pull",
                pullRequests: dashboard.myPRs,
                unreadURLs: settings.showUnreadDots ? session.unreadPRURLs : [],
                unreadNotifications: session.unreadNotificationsByURL,
                hiddenURLs: session.hiddenPRURLs,
                isActive: activePane == .mine,
                selectedID: Binding(
                    get: { activePane == .mine ? mySelectedID : nil },
                    set: { mySelectedID = $0; activePane = .mine }
                ),
                keyFocus: $keyFocus,
                focusValue: .pane(.mine)
            )
            PRListView(
                title: "Review requested",
                systemImage: "eye",
                pullRequests: dashboard.reviewRequests,
                unreadURLs: settings.showUnreadDots ? session.unreadPRURLs : [],
                unreadNotifications: session.unreadNotificationsByURL,
                hiddenURLs: session.hiddenPRURLs,
                isActive: activePane == .review,
                selectedID: Binding(
                    get: { activePane == .review ? reviewSelectedID : nil },
                    set: { reviewSelectedID = $0; activePane = .review }
                ),
                keyFocus: $keyFocus,
                focusValue: .pane(.review)
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

    private func perform(_ command: DashboardKeyCommand) {
        switch command {
        case .moveUp: move(-1)
        case .moveDown: move(1)
        case .showMine: switchTo(.mine)
        case .showReview: switchTo(.review)
        case .open: openSelected()
        case .dismiss: dismissSelected()
        case .toggleHide: toggleHideSelected()
        case .viewNotifications: showSelectedNotifications()
        }
    }

    /// Switch the focused pane, selecting its first row if nothing is selected yet.
    /// Keyboard focus follows, so the pane's list does not keep handling arrows for the old pane.
    private func switchTo(_ pane: Pane) {
        activePane = pane
        let prs = activePRs
        if activeSelection == nil, let first = prs.first { activeSelection = first.id }
        keyFocus = prs.isEmpty ? .dashboard : .pane(pane)
    }

    private func openSelected() {
        guard let pr = activePRs.first(where: { $0.id == activeSelection }) else { return }
        if SafeURL.isAllowed(pr.url) { openURL(pr.url) }
        session.markRead(prURL: pr.url)
    }

    private func copySelectedURL() -> [NSItemProvider] {
        guard let pr = activePRs.first(where: { $0.id == activeSelection }) else { return [] }
        showToast("Copied PR URL")
        return [NSItemProvider(object: pr.url.absoluteString as NSString)]
    }

    private func showSelectedNotifications() {
        guard let pr = activePRs.first(where: { $0.id == activeSelection }), session.unreadPRURLs.contains(pr.url) else {
            showToast("No unread notifications")
            return
        }
        notificationPanelPR = pr
    }

    private func notifications(for pullRequest: PullRequest) -> [Session.UnreadNotification] {
        if let notifications = session.unreadNotificationsByURL[pullRequest.url], !notifications.isEmpty {
            return notifications
        }
        return [.init(
            id: "legacy-\(pullRequest.id)",
            repository: pullRequest.repository,
            subtitle: "Unread notification",
            title: pullRequest.title,
            createdAt: pullRequest.updatedAt
        )]
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    /// Space dismisses the selected PR's unread mark without opening it.
    private func dismissSelected() {
        guard let pr = activePRs.first(where: { $0.id == activeSelection }) else { return }
        session.markRead(prURL: pr.url)
    }

    /// H toggles whether the selected PR is hidden.
    private func toggleHideSelected() {
        let prs = activePRs
        guard let index = prs.firstIndex(where: { $0.id == activeSelection }) else { return }
        let pr = prs[index]
        if session.hiddenPRURLs.contains(pr.url) {
            session.unhide(url: pr.url)
        } else {
            if !settings.showHiddenPullRequests {
                let nextPRs = prs.enumerated().filter { $0.offset != index }.map(\.element)
                activeSelection = nextPRs.indices.contains(index) ? nextPRs[index].id : nextPRs.last?.id
            }
            session.hide(pr)
        }
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

/// A failed refresh shown above the last good dashboard instead of replacing it.
struct RefreshErrorBanner: View {
    var message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Couldn't refresh: \(message)")
                .font(.system(size: 12))
                .lineLimit(2)
            Spacer()
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
            if let refreshError = session.refreshError {
                Label(refreshError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
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
