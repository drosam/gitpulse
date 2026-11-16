import Foundation

/// Gatekeeper for URLs GitPulse opens on the user's behalf.
enum SafeURL {
    /// Only `https://github.com/...` URLs may be opened.
    static func isAllowed(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host()?.lowercased() == "github.com"
    }
}
