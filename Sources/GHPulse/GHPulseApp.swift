import SwiftUI

@main
struct GHPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = Session()

    var body: some Scene {
        WindowGroup(id: "main") {
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

        MenuBarExtra {
            MenuBarMenu()
        } label: {
            // Filled circle = pending notifications, hollow = all clear.
            Label("GHPulse", systemImage: session.hasUnread ? "circle.fill" : "circle")
                .labelStyle(.iconOnly)
        }
    }
}

struct MenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open GHPulse") {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit GHPulse") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// Starts as a regular app (also needed when launched via `swift run`, which
/// has no bundle), then drops to accessory — menubar only, no Dock icon —
/// whenever the main window closes.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Notifier.shared.setUp()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier?.rawValue.hasPrefix("main") == true else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
