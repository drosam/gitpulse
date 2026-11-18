import SwiftUI

/// Dashboard keyboard shortcut, decided from a key press without touching any view state.
enum DashboardKeyCommand: Equatable {
    case moveUp
    case moveDown
    case showMine
    case showReview
    case open
    case dismiss
    case toggleHide
    case viewNotifications

    /// Matches by character, not physical key, so letters follow the active keyboard layout.
    /// Presses with Command, Control or Option are left to menus and the system.
    static func command(key: KeyEquivalent, characters: String, modifiers: EventModifiers) -> DashboardKeyCommand? {
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        switch key {
        case .upArrow: return .moveUp
        case .downArrow: return .moveDown
        case .leftArrow: return .showMine
        case .rightArrow: return .showReview
        case .return: return .open
        case .space: return .dismiss
        default: break
        }
        switch characters.lowercased() {
        case "\u{3}": return .open  // keypad Enter
        case "h": return .toggleHide
        case "v": return .viewNotifications
        default: return nil
        }
    }
}
