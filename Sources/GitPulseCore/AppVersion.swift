import Foundation

public enum AppVersion {
    /// `CFBundleShortVersionString`, or `dev` when running without a bundle (`swift run`).
    public static func display(bundle: Bundle = .main) -> String {
        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty
        else { return "dev" }
        return version
    }
}
