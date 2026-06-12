import SwiftUI

struct PRListView: View {
    var title: String
    var systemImage: String
    var pullRequests: [PullRequest]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("\(title) (\(pullRequests.count))", systemImage: systemImage)
                .font(.headline)
                .padding(10)

            Divider()

            if pullRequests.isEmpty {
                Spacer()
                Text("Nothing here 🎉")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(pullRequests) { pullRequest in
                    PRRow(pullRequest: pullRequest)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PRRow: View {
    @Environment(\.openURL) private var openURL
    var pullRequest: PullRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if pullRequest.isDraft {
                    Text("Draft")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Text(pullRequest.title)
                    .lineLimit(1)
                    .fontWeight(.medium)
            }
            HStack(spacing: 8) {
                Text("\(pullRequest.repository) #\(pullRequest.number)")
                Text("by \(pullRequest.author)")
                Text("+\(pullRequest.additions)").foregroundStyle(.green)
                Text("−\(pullRequest.deletions)").foregroundStyle(.red)
                reviewBadge
                Spacer()
                Text(pullRequest.updatedAt, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            openURL(pullRequest.url)
        }
        .contextMenu {
            Button("Open on GitHub") { openURL(pullRequest.url) }
        }
    }

    @ViewBuilder
    private var reviewBadge: some View {
        switch pullRequest.reviewDecision {
        case .approved:
            Label("Approved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .changesRequested:
            Label("Changes requested", systemImage: "xmark.circle.fill")
                .foregroundStyle(.orange)
        case .reviewRequired, nil:
            EmptyView()
        }
    }
}
