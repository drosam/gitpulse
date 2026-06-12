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
    @Environment(Session.self) private var session
    var dashboard: Dashboard

    var body: some View {
        HSplitView {
            PRListView(title: "My pull requests", systemImage: "arrow.triangle.pull", pullRequests: dashboard.myPRs)
            PRListView(title: "Review requested", systemImage: "eye", pullRequests: dashboard.reviewRequests)
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                Text(dashboard.viewer)
                    .foregroundStyle(.secondary)
            }
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await session.refresh() }
                }
            }
        }
        .navigationTitle("Scout")
    }
}

struct SignInView: View {
    @Environment(Session.self) private var session

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "binoculars")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Scout")
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
