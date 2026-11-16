import Foundation
import Testing
@testable import GitPulseCore

struct AppVersionTests {
    private func bundle(info: [String: Any]?) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitPulseVersion-\(UUID().uuidString).bundle")
        let contents = root.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        if let info {
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }
        return try #require(Bundle(url: root))
    }

    @Test func showsBundleShortVersion() throws {
        let bundle = try bundle(info: ["CFBundleShortVersionString": "0.1.0", "CFBundleIdentifier": "test.version"])
        #expect(AppVersion.display(bundle: bundle) == "0.1.0")
    }

    @Test func showsDevWithoutVersion() throws {
        #expect(AppVersion.display(bundle: try bundle(info: nil)) == "dev")
    }
}
