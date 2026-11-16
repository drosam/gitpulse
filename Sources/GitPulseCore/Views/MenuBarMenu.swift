import AppKit
import SwiftUI

public struct MenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    public init() {}

    public var body: some View {
        Button("GitPulse \(AppVersion.display())") {}
            .disabled(true)
        Divider()
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
