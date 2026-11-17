import Foundation
import Testing
@testable import GitPulseCore

struct HTTPTests {
    @Test func sessionKeepsNothingOnDisk() {
        let configuration = HTTP.session.configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func purgeRemovesLegacyCacheAndCookies() throws {
        let fileManager = FileManager.default
        let library = fileManager.temporaryDirectory.appending(path: "gitpulse-http-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: library) }

        let bundleID = "dev.example.app"
        let cache = library.appending(path: "Caches/\(bundleID)")
        let storage = library.appending(path: "HTTPStorages/\(bundleID)")
        let cookies = library.appending(path: "HTTPStorages/\(bundleID).binarycookies")
        let unrelated = library.appending(path: "Caches/other.app")
        for directory in [cache.appending(path: "fsCachedData"), storage, unrelated] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for file in [cache.appending(path: "Cache.db"), cache.appending(path: "Cache.db-wal"), cookies] {
            try Data("x".utf8).write(to: file)
        }

        HTTP.purgeLegacyDiskStorage(bundleID: bundleID, library: library)

        #expect(!fileManager.fileExists(atPath: cache.path))
        #expect(!fileManager.fileExists(atPath: storage.path))
        #expect(!fileManager.fileExists(atPath: cookies.path))
        #expect(fileManager.fileExists(atPath: unrelated.path))
    }

    @Test func purgeWithoutBundleIDDoesNothing() throws {
        let fileManager = FileManager.default
        let library = fileManager.temporaryDirectory.appending(path: "gitpulse-http-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: library) }
        let caches = library.appending(path: "Caches")
        try fileManager.createDirectory(at: caches, withIntermediateDirectories: true)

        HTTP.purgeLegacyDiskStorage(bundleID: nil, library: library)

        #expect(fileManager.fileExists(atPath: caches.path))
    }
}
