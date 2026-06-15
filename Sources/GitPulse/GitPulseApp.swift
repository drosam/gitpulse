import SwiftUI

@main
struct GitPulseApp: App {
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
            // White ring with a coloured inner dot = pending; hollow ring = clear.
            if session.hasUnread {
                ZStack {
                    Circle().stroke(.white, lineWidth: 1.4)
                    Circle()
                        .fill(Color(red: 1.0, green: 0.42, blue: 0.21))
                        .padding(3.5)
                }
                .frame(width: 15, height: 15)
            } else {
                Image(systemName: "circle")
            }
        }
    }
}

struct MenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open GitPulse") {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit GitPulse") {
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

    func applicationDidBecomeActive(_ notification: Notification) {
        Notifier.shared.refreshAuthorizationStatus()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier?.rawValue.hasPrefix("main") == true else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
