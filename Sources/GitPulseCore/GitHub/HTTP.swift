import Foundation

/// Network access for GitHub requests.
public enum HTTP {
    /// Keeps no cache, cookies or credentials, so the bearer token and pull request
    /// data never reach `~/Library/Caches` or `~/Library/HTTPStorages`.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// Deletes the disk cache and cookie store that v0.1.0 wrote through `URLSession.shared`.
    /// Those files contain the bearer token in plain text.
    public static func purgeLegacyDiskStorage(
        bundleID: String? = Bundle.main.bundleIdentifier,
        library: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
    ) {
        guard let bundleID, !bundleID.isEmpty else { return }
        let paths = [
            "Caches/\(bundleID)",
            "HTTPStorages/\(bundleID)",
            "HTTPStorages/\(bundleID).binarycookies",
        ]
        for path in paths {
            try? FileManager.default.removeItem(at: library.appending(path: path))
        }
    }
}
