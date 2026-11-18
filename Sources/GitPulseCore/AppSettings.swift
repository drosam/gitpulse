import Foundation
import Observation
import ServiceManagement

@Observable
@MainActor
public final class AppSettings {
    public static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults

    enum RepositoryScope: String, CaseIterable, Identifiable {
        case all
        case selected

        var id: String { rawValue }
    }

    enum PullRequestSort: String, CaseIterable, Identifiable {
        case createdAtNewest
        case updatedAtNewest

        var id: String { rawValue }

        var label: String {
            switch self {
            case .createdAtNewest: return "Created newest to oldest"
            case .updatedAtNewest: return "Updated newest to oldest"
            }
        }
    }

    var showNotificationBanners: Bool {
        didSet { defaults.set(showNotificationBanners, forKey: Self.showNotificationBannersKey) }
    }

    var playNotificationSounds: Bool {
        didSet { defaults.set(playNotificationSounds, forKey: Self.playNotificationSoundsKey) }
    }

    var showDockBadge: Bool {
        didSet { defaults.set(showDockBadge, forKey: Self.showDockBadgeKey) }
    }

    public var showUnreadDots: Bool {
        didSet { defaults.set(showUnreadDots, forKey: Self.showUnreadDotsKey) }
    }

    var showHiddenPullRequests: Bool {
        didSet { defaults.set(showHiddenPullRequests, forKey: Self.showHiddenPullRequestsKey) }
    }

    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Self.launchAtLoginKey) }
    }

    var repositoryScope: RepositoryScope {
        didSet { defaults.set(repositoryScope.rawValue, forKey: Self.repositoryScopeKey) }
    }

    var pullRequestSort: PullRequestSort {
        didSet { defaults.set(pullRequestSort.rawValue, forKey: Self.pullRequestSortKey) }
    }

    /// Newline or comma separated `owner/name` repository names or GitHub repository URLs.
    var selectedRepositoriesText: String {
        didSet { defaults.set(selectedRepositoriesText, forKey: Self.selectedRepositoriesKey) }
    }

    var selectedRepositories: [String] {
        var seen = Set<String>()
        return repositoryEntries
            .compactMap(Self.repositoryName(from:))
            .filter { seen.insert($0).inserted }
    }

    /// Entries that are neither `owner/name` nor a GitHub repository URL.
    var rejectedRepositoryEntries: [String] {
        repositoryEntries.filter { Self.repositoryName(from: $0) == nil }
    }

    var activeRepositories: [String] {
        repositoryScope == .selected ? selectedRepositories : []
    }

    /// "Only selected" with no valid entry; an empty filter would otherwise mean every repository.
    var selectsNoRepositories: Bool {
        repositoryScope == .selected && selectedRepositories.isEmpty
    }

    private var repositoryEntries: [String] {
        selectedRepositoriesText
            .split { $0 == "\n" || $0 == "," || $0 == " " || $0 == "\t" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// `owner/name` from an entry, accepting `github.com/owner/name/...` URLs.
    private static func repositoryName(from entry: String) -> String? {
        var path = entry
        for scheme in ["https://", "http://"] where path.lowercased().hasPrefix(scheme) {
            path.removeFirst(scheme.count)
        }
        if path.lowercased().hasPrefix("www.") { path.removeFirst(4) }
        if path.lowercased().hasPrefix("github.com/") {
            let parts = path.split(separator: "/").dropFirst().prefix(2)
            path = parts.joined(separator: "/")
            if path.hasSuffix(".git") { path.removeLast(4) }
        }
        return isValidRepository(path) ? path : nil
    }

    private static let showNotificationBannersKey = "settings.showNotificationBanners"
    private static let playNotificationSoundsKey = "settings.playNotificationSounds"
    private static let showDockBadgeKey = "settings.showDockBadge"
    private static let showUnreadDotsKey = "settings.showUnreadDots"
    private static let showHiddenPullRequestsKey = "settings.showHiddenPullRequests"
    private static let launchAtLoginKey = "settings.launchAtLogin"
    private static let repositoryScopeKey = "settings.repositoryScope"
    private static let pullRequestSortKey = "settings.pullRequestSort"
    private static let selectedRepositoriesKey = "settings.selectedRepositories"

    private static func isValidRepository(_ repository: String) -> Bool {
        let parts = repository.split(separator: "/")
        guard parts.count == 2 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-")
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
        launchAtLogin = enabled
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showNotificationBanners = defaults.object(forKey: Self.showNotificationBannersKey) as? Bool ?? true
        playNotificationSounds = defaults.object(forKey: Self.playNotificationSoundsKey) as? Bool ?? true
        showDockBadge = defaults.object(forKey: Self.showDockBadgeKey) as? Bool ?? true
        showUnreadDots = defaults.object(forKey: Self.showUnreadDotsKey) as? Bool ?? true
        showHiddenPullRequests = defaults.object(forKey: Self.showHiddenPullRequestsKey) as? Bool ?? false
        launchAtLogin = SMAppService.mainApp.status == .enabled
        repositoryScope = RepositoryScope(rawValue: defaults.string(forKey: Self.repositoryScopeKey) ?? "") ?? .all
        pullRequestSort = PullRequestSort(rawValue: defaults.string(forKey: Self.pullRequestSortKey) ?? "") ?? .createdAtNewest
        selectedRepositoriesText = defaults.string(forKey: Self.selectedRepositoriesKey) ?? ""
    }
}
