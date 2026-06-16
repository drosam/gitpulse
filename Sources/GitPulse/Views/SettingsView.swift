import SwiftUI

struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Notifications") {
                Toggle("Show notification banners", isOn: $settings.showNotificationBanners)
                Toggle("Play notification sounds", isOn: $settings.playNotificationSounds)
                Toggle("Show Dock badge count", isOn: $settings.showDockBadge)
                Toggle("Show unread dots in the app and menu bar", isOn: $settings.showUnreadDots)
            }

            Section("Repositories") {
                Picker("Pull request scope", selection: $settings.repositoryScope) {
                    Text("All my repositories").tag(AppSettings.RepositoryScope.all)
                    Text("Only selected repositories").tag(AppSettings.RepositoryScope.selected)
                }
                .pickerStyle(.radioGroup)

                Text("Selected repositories")
                    .font(.headline)
                Text("Enter one full repository name per line, for example `owner/repo`. Applies to authored, assigned, review-requested, and merged PR checks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $settings.selectedRepositoriesText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100)
                    .border(Color.secondary.opacity(0.25))
                    .disabled(settings.repositoryScope != .selected)

                HStack {
                    Text(settings.repositoryScope == .selected ? "Checking \(settings.selectedRepositories.count) repositories" : "Checking all matching repositories")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh Now") {
                        Task { await session.applySettingsChanged(refresh: true) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 460)
        .onChange(of: settings.showDockBadge) { _, _ in
            Task { await session.applySettingsChanged() }
        }
        .onChange(of: settings.repositoryScope) { _, _ in
            Task { await session.applySettingsChanged(refresh: true) }
        }
    }
}
