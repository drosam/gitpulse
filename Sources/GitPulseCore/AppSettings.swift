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

    /// Newline or comma separated `owner/name` repository names.
    var selectedRepositoriesText: String {
        didSet { defaults.set(selectedRepositoriesText, forKey: Self.selectedRepositoriesKey) }
    }

    var selectedRepositories: [String] {
        selectedRepositoriesText
            .split { $0 == "\n" || $0 == "," || $0 == " " || $0 == "\t" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter(Self.isValidRepository)
    }

    var activeRepositories: [String] {
        repositoryScope == .selected ? selectedRepositories : []
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
