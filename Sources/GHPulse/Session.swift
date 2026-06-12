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
    private var token: String?

    func start() async {
        guard let resolved = TokenStore.resolve() else {
            state = .signedOut
            return
        }
        token = resolved
        await refresh()
    }

    func refresh() async {
        guard let token else { return }
        if case .ready = state {} else { state = .loading }
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
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func signOut() {
        TokenStore.clear()
        token = nil
        state = .signedOut
    }
}
