import SwiftUI

public struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(AppSettings.self) private var settings
    @State private var launchAtLoginError: String?

    public init() {}

    public var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Account") {
                if let source = session.tokenSource {
                    LabeledContent("Signed in as", value: session.viewerLogin.map(\.githubMention) ?? "…")
                    LabeledContent("Token from", value: source.label)
                    Button("Sign Out") {
                        session.signOut()
                    }
                    Text("Signing out clears this account's hidden pull requests and unread dots in GitPulse. It doesn't revoke GitPulse's access on GitHub; do that at github.com/settings/applications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not signed in. Open GitPulse to sign in.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Notifications") {
                Toggle("Show notification banners", isOn: $settings.showNotificationBanners)
                Toggle("Play notification sounds", isOn: $settings.playNotificationSounds)
                Toggle("Show Dock badge count", isOn: $settings.showDockBadge)
                Toggle("Show unread dots in the app and menu bar", isOn: $settings.showUnreadDots)
            }

            Section("General") {
                Picker("Pull request order", selection: $settings.pullRequestSort) {
                    ForEach(AppSettings.PullRequestSort.allCases) { sort in
                        Text(sort.label).tag(sort)
                    }
                }

                Toggle("Start GitPulse at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { enabled in
                        launchAtLoginError = nil
                        do {
                            try settings.setLaunchAtLogin(enabled)
                        } catch {
                            launchAtLoginError = error.localizedDescription
                        }
                    }
                ))
                if let launchAtLoginError {
                    Text("Could not update login item: \(launchAtLoginError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Repositories") {
                Picker("Pull request scope", selection: $settings.repositoryScope) {
                    Text("All my repositories").tag(AppSettings.RepositoryScope.all)
                    Text("Only selected repositories").tag(AppSettings.RepositoryScope.selected)
                }
                .pickerStyle(.radioGroup)

                Text("Selected repositories")
                    .font(.headline)
                Text("Enter one repository per line, as `owner/repo` or its GitHub URL. Applies to authored, assigned, review-requested, and merged PR checks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $settings.selectedRepositoriesText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100)
                    .border(Color.secondary.opacity(0.25))
                    .disabled(settings.repositoryScope != .selected)

                if settings.repositoryScope == .selected, !settings.rejectedRepositoryEntries.isEmpty {
                    Text("Ignored: \(settings.rejectedRepositoryEntries.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    Text(repositoryStatus)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh Now") {
                        Task { await session.applySettingsChanged(refresh: true) }
                    }
                }
            }

            Section("Hidden Pull Requests") {
                Toggle("Show hidden pull requests in lists", isOn: $settings.showHiddenPullRequests)
                Text("Shown hidden pull requests stay dimmed and marked Hidden. Their row can show a blue unread dot, but they do not affect the menu bar dot, Dock badge, sounds, or banners.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if session.hiddenPullRequests.isEmpty {
                    Text("No hidden pull requests")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.hiddenPullRequests) { pullRequest in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(pullRequest.title)
                                    .lineLimit(1)
                                Text("\(pullRequest.repository) #\(pullRequest.number)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restore") {
                                session.unhide(pullRequest)
                            }
                        }
                    }
                    Button("Restore All") {
                        session.unhideAll()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 520)
        .onChange(of: settings.showDockBadge) { _, _ in
            Task { await session.applySettingsChanged() }
        }
        .onChange(of: settings.repositoryScope) { _, _ in
            Task { await session.applySettingsChanged(refresh: true) }
        }
        .onChange(of: settings.pullRequestSort) { _, _ in
            Task { await session.applySettingsChanged() }
        }
        .onChange(of: settings.showHiddenPullRequests) { _, _ in
            Task { await session.applySettingsChanged() }
        }
    }

    private var repositoryStatus: String {
        guard settings.repositoryScope == .selected else { return "Checking all matching repositories" }
        let count = settings.selectedRepositories.count
        if count == 0 { return "No valid repositories, so no pull requests are checked" }
        return count == 1 ? "Checking 1 repository" : "Checking \(count) repositories"
    }
}
