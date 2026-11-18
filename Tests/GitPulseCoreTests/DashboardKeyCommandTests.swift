import SwiftUI
import Testing
@testable import GitPulseCore

struct DashboardKeyCommandTests {
    @Test func mapsNavigationKeys() {
        #expect(DashboardKeyCommand.command(key: .upArrow, characters: "", modifiers: [.numericPad]) == .moveUp)
        #expect(DashboardKeyCommand.command(key: .downArrow, characters: "", modifiers: []) == .moveDown)
        #expect(DashboardKeyCommand.command(key: .leftArrow, characters: "", modifiers: []) == .showMine)
        #expect(DashboardKeyCommand.command(key: .rightArrow, characters: "", modifiers: []) == .showReview)
        #expect(DashboardKeyCommand.command(key: .return, characters: "\r", modifiers: []) == .open)
        #expect(DashboardKeyCommand.command(key: KeyEquivalent("\u{3}"), characters: "\u{3}", modifiers: [.numericPad]) == .open)
        #expect(DashboardKeyCommand.command(key: .space, characters: " ", modifiers: []) == .dismiss)
    }

    @Test func mapsLettersByCharacter() {
        #expect(DashboardKeyCommand.command(key: "h", characters: "h", modifiers: []) == .toggleHide)
        #expect(DashboardKeyCommand.command(key: "h", characters: "H", modifiers: [.shift]) == .toggleHide)
        #expect(DashboardKeyCommand.command(key: "v", characters: "v", modifiers: []) == .viewNotifications)
        #expect(DashboardKeyCommand.command(key: "j", characters: "j", modifiers: []) == nil)
    }

    @Test(arguments: [EventModifiers.command, .control, .option, [.command, .shift]])
    func leavesModifiedPressesToMenus(_ modifiers: EventModifiers) {
        #expect(DashboardKeyCommand.command(key: "h", characters: "h", modifiers: modifiers) == nil)
        #expect(DashboardKeyCommand.command(key: "c", characters: "c", modifiers: modifiers) == nil)
        #expect(DashboardKeyCommand.command(key: .return, characters: "\r", modifiers: modifiers) == nil)
    }
}
