import SwiftUI

@main
struct GitPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = Session()
    @State private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(session)
                .environment(settings)
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

        Settings {
            SettingsView()
                .environment(session)
                .environment(settings)
        }

        MenuBarExtra {
            MenuBarMenu()
        } label: {
            // White ring + blue inner dot = pending; hollow ring = clear.
            // Pending uses a non-template NSImage so the menu bar keeps its
            // colour instead of flattening it to monochrome (which hid it).
            if settings.showUnreadDots && session.hasUnread {
                Image(nsImage: Self.unreadIcon)
            } else {
                Image(systemName: "circle")
            }
        }
    }

    /// Hand-drawn pending icon: white outer ring, blue inner dot.
    /// `isTemplate = false` keeps the colours in the menu bar.
    private static let unreadIcon: NSImage = {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()

        let inset: CGFloat = 1.5
        let ring = NSBezierPath(ovalIn: NSRect(
            x: inset, y: inset,
            width: size.width - inset * 2, height: size.height - inset * 2
        ))
        ring.lineWidth = 1.4
        NSColor.white.setStroke()
        ring.stroke()

        let pad: CGFloat = 2.9
        let dot = NSBezierPath(ovalIn: NSRect(
            x: pad, y: pad,
            width: size.width - pad * 2, height: size.height - pad * 2
        ))
        NSColor(srgbRed: 0.0, green: 0.478, blue: 1.0, alpha: 1).setFill()
        dot.fill()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }()
}

struct MenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Open GitPulse") {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Settings…") {
            NSApp.setActivationPolicy(.regular)
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)
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
