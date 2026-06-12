import SwiftUI

@main
struct GHPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = Session()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    Task { await session.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

/// Needed when launched via `swift run` (no app bundle): without this the
/// process stays an accessory and never shows a window or takes focus.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
