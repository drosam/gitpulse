import SwiftUI

@Observable
@MainActor
final class Session {
    enum State {
        case signedOut
        case authorizing(DeviceFlow.Authorization)
        case loading
        case ready(Dashboard)
        case failed(String)
    }

    private(set) var state: State = .signedOut
    private(set) var isRefreshing = false
    private var token: String?
    private var autoRefreshTask: Task<Void, Never>?

    private static let autoRefreshInterval: Duration = .seconds(60)

    func start() async {
        guard let resolved = TokenStore.resolve() else {
            state = .signedOut
            return
        }
        token = resolved
        await refresh()
        startAutoRefresh()
    }

    func refresh() async {
        guard let token else { return }
        if case .ready = state {} else { state = .loading }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            state = .ready(try await GitHubClient(token: token).fetchDashboard())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func signIn() async {
        do {
            let authorization = try await DeviceFlow.requestCode()
            state = .authorizing(authorization)
            let newToken = try await DeviceFlow.pollForToken(authorization)
            TokenStore.save(newToken)
            token = newToken
            await refresh()
            startAutoRefresh()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func signOut() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        TokenStore.clear()
        token = nil
        state = .signedOut
    }

    // MARK: - Auto-refresh

    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Session.autoRefreshInterval)
                guard !Task.isCancelled else { return }
                await self?.backgroundRefresh()
            }
        }
    }

    /// Unlike `refresh()`, keeps the current dashboard if the fetch fails,
    /// so a transient network error never replaces data with an error screen.
    private func backgroundRefresh() async {
        guard let token else { return }
        if let dashboard = try? await GitHubClient(token: token).fetchDashboard() {
            state = .ready(dashboard)
        }
    }
}
