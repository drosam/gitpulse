import SwiftUI

/// View menu commands for the dashboard.
public struct DashboardCommands: Commands {
    var session: Session
    var settings: AppSettings

    public init(session: Session, settings: AppSettings) {
        self.session = session
        self.settings = settings
    }

    public var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Refresh") {
                Task { await session.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)

            Toggle("Show Hidden Pull Requests", isOn: Binding(
                get: { settings.showHiddenPullRequests },
                set: { show in
                    settings.showHiddenPullRequests = show
                    Task { await session.applySettingsChanged(refresh: true) }
                }
            ))
            .keyboardShortcut("h", modifiers: [.command, .shift])
        }
    }
}
