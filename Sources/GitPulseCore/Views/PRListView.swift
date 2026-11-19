import SwiftUI

struct PRListView: View {
    var title: String
    var systemImage: String
    var pullRequests: [PullRequest]
    var unreadURLs: Set<URL> = []
    var unreadNotifications: [URL: [Session.UnreadNotification]] = [:]
    var hiddenURLs: Set<URL> = []
    var isActive: Bool
    @Binding var selectedID: PullRequest.ID?
    var keyFocus: FocusState<DashboardView.KeyFocus?>.Binding
    var focusValue: DashboardView.KeyFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("\(title) (\(pullRequests.count))", systemImage: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .padding(10)

            Divider()

            if pullRequests.isEmpty {
                Spacer()
                Text("Nothing here 🎉")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    List(pullRequests, selection: $selectedID) { pullRequest in
                        PRRow(
                            pullRequest: pullRequest,
                            hasNotification: unreadURLs.contains(pullRequest.url),
                            unreadNotifications: notifications(for: pullRequest),
                            isHidden: hiddenURLs.contains(pullRequest.url)
                        )
                        .id(pullRequest.id)
                        .tag(pullRequest.id)
                    }
                    .listStyle(.inset)
                    .focused(keyFocus, equals: focusValue)
                    .onChange(of: selectedID) { _, id in
                        scrollToSelection(id, with: proxy)
                    }
                    .onChange(of: isActive) { _, active in
                        if active {
                            scrollToSelection(selectedID, with: proxy)
                        }
                    }
                    .onChange(of: pullRequests.map(\.id)) { _, _ in
                        scrollToSelection(selectedID, with: proxy)
                    }
                }
            }
        }
        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scrollToSelection(_ id: PullRequest.ID?, with proxy: ScrollViewProxy) {
        guard isActive, let id, pullRequests.contains(where: { $0.id == id }) else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func notifications(for pullRequest: PullRequest) -> [Session.UnreadNotification] {
        if let notifications = unreadNotifications[pullRequest.url], !notifications.isEmpty {
            return notifications
        }
        guard unreadURLs.contains(pullRequest.url) else { return [] }
        return [.init(
            id: "legacy-\(pullRequest.id)",
            repository: pullRequest.repository,
            subtitle: "Unread notification",
            title: pullRequest.title,
            createdAt: pullRequest.updatedAt
        )]
    }
}

struct UnreadNotificationsView: View {
    var notifications: [Session.UnreadNotification]
    var repository: String? = nil
    var title: String? = nil
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTitle {
                header
            }
            ForEach(notifications) { notification in
                notificationRow(notification)
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
    }

    private func notificationRow(_ notification: Session.UnreadNotification) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: Self.iconName(for: notification.resolvedKind))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Self.iconColor(for: notification.resolvedKind))
                .frame(width: 24, height: 24)
                .background(Self.iconColor(for: notification.resolvedKind).opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(notification.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
    }

    static func iconName(for kind: NotificationEvent.Kind?) -> String {
        switch kind {
        case .merged: "arrow.triangle.merge"
        case .approved: "checkmark.seal.fill"
        case .changesRequested: "xmark.seal.fill"
        case .commented: "text.bubble.fill"
        case .checksPassed: "checkmark.circle.fill"
        case .checksFailed: "xmark.circle.fill"
        case .reviewRequested: "eye.fill"
        case .leftMergeQueue: "arrow.uturn.backward.circle.fill"
        case .reviewDismissed, .reviewed, nil: "bell.fill"
        }
    }

    static func iconColor(for kind: NotificationEvent.Kind?) -> Color {
        switch kind {
        case .merged: .purple
        case .approved, .checksPassed: .green
        case .changesRequested, .checksFailed: .red
        case .commented: .blue
        case .reviewRequested: .orange
        case .leftMergeQueue, .reviewDismissed, .reviewed, nil: .secondary
        }
    }

    @ViewBuilder
    private var header: some View {
        if let repository, let title {
            VStack(alignment: .leading, spacing: 2) {
                Text(repository)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
            }
        } else {
            Text("Unread notifications")
                .font(.headline)
        }
    }
}

struct PRRow: View {
    @Environment(\.openURL) private var openURL
    @Environment(Session.self) private var session
    @State private var isHovering = false
    @State private var isShowingNotifications = false
    var pullRequest: PullRequest
    var hasNotification: Bool = false
    var unreadNotifications: [Session.UnreadNotification] = []
    var isHidden: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            stateIcon
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(pullRequest.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    checkIcon
                    ForEach(pullRequest.labels.prefix(3), id: \.self) { label in
                        LabelPill(label: label)
                    }
                    if pullRequest.labels.count > 3 {
                        Text("+\(pullRequest.labels.count - 3)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                if !pullRequest.headBranch.isEmpty {
                    Text(pullRequest.headBranch)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.secondary)
                        // Align the branch text (not the chip box) with the rows above/below.
                        .padding(.leading, -5)
                }
                HStack(spacing: 6) {
                    Text(caption)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if pullRequest.isMerged {
                        Text("•")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        mergedPill
                    }
                    if isQueued {
                        Text("•")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        mergeQueuePill
                    }
                    if isHidden {
                        Text("•")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        hiddenPill
                    }
                }
            }

            Spacer(minLength: 8)

            if hasNotification {
                Button {
                    isShowingNotifications.toggle()
                } label: {
                    Circle()
                        .fill(.blue)
                        .frame(width: 10, height: 10)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .help("Unread notification — click to view, press space to dismiss")
                .popover(isPresented: $isShowingNotifications, arrowEdge: .trailing) {
                    UnreadNotificationsView(
                        notifications: unreadNotifications,
                        repository: pullRequest.repository,
                        title: pullRequest.title
                    )
                }
            }

            if pullRequest.commentCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "bubble.right")
                    Text("\(pullRequest.commentCount)")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }

            Image(systemName: "arrow.up.right")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .opacity(isHovering ? 1 : 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .opacity(isHidden ? 0.55 : 1)
        .background(isHidden ? Color.secondary.opacity(0.08) : (isHovering ? Color.primary.opacity(0.06) : .clear), in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            open()
        }
        .contextMenu {
            Button("Open on GitHub") { open() }
            if isHidden {
                Button("Restore Pull Request") {
                    session.unhide(url: pullRequest.url)
                }
            } else {
                Button("Hide Pull Request") { session.hide(pullRequest) }
            }
        }
    }

    private func open() {
        if SafeURL.isAllowed(pullRequest.url) { openURL(pullRequest.url) }
        session.markRead(prURL: pullRequest.url)
    }

    private var isQueued: Bool {
        pullRequest.isInMergeQueue || pullRequest.mergeQueueState == "QUEUED" || pullRequest.mergeQueueState == "AWAITING_CHECKS"
    }

    /// Gold merge-queue glyph while the PR waits in the queue, otherwise the
    /// green open-PR icon (gray dotted for drafts) — like GitHub's list.
    @ViewBuilder
    private var stateIcon: some View {
        if pullRequest.isMerged {
            GitMergeIcon()
                .foregroundStyle(.purple)
                .help("Merged pull request")
        } else if isQueued {
            MergeQueueIcon()
                .foregroundStyle(Self.queuedGold)
                .help("Waiting in the merge queue")
        } else {
            PullRequestIcon(isDraft: pullRequest.isDraft)
                .foregroundStyle(pullRequest.isDraft ? Color.secondary : Color.green)
                .help(pullRequest.isDraft ? "Draft pull request" : "Open pull request")
        }
    }

    private static let queuedGold = Color(red: 0.85, green: 0.62, blue: 0.10)

    /// Head-commit check rollup: ✓ green, ✗ red, ● yellow while running.
    @ViewBuilder
    private var checkIcon: some View {
        switch pullRequest.checkState {
        case .success:
            Image(systemName: "checkmark")
                .font(.caption.bold())
                .foregroundStyle(.green)
        case .failure, .error:
            Image(systemName: "xmark")
                .font(.caption.bold())
                .foregroundStyle(.red)
        case .pending, .expected:
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(.yellow)
        case nil:
            EmptyView()
        }
    }

    /// Yellow "Queued" badge, shown only while the PR sits in a merge queue
    /// waiting (QUEUED or AWAITING_CHECKS). Other merge-queue states get no pill.
    @ViewBuilder
    private var mergeQueuePill: some View {
        if isQueued {
            Text("Queued")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Self.queuedGold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Self.queuedGold.opacity(0.15), in: Capsule())
            .help("Waiting in the merge queue")
        }
    }

    private var mergedPill: some View {
        Text("Merged")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.purple)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.purple.opacity(0.15), in: Capsule())
            .help("Merged pull request")
    }

    private var hiddenPill: some View {
        Text("Hidden")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .help("Hidden pull request")
    }

    private var caption: String {
        var parts = [
            "\(pullRequest.repository) #\(pullRequest.number)",
            "opened \(pullRequest.createdAt.formatted(.relative(presentation: .named)))",
            "by \(pullRequest.author.githubMention)",
        ]
        if let status = reviewStatus {
            parts.append("• \(status)")
        }
        return parts.joined(separator: " ")
    }

    private var reviewStatus: String? {
        if pullRequest.isDraft { return "Draft" }
        switch pullRequest.reviewDecision {
        case .approved: return "Approved"
        case .changesRequested: return "Changes requested"
        case .reviewRequired: return "Review required"
        case nil: return nil
        }
    }
}

/// Hand-drawn version of GitHub's octicons `git-pull-request` and
/// `git-pull-request-draft` (no SF Symbol equivalent exists).
/// Drawn in a 16×16 design space; tinted via `foregroundStyle`.
struct PullRequestIcon: View {
    var isDraft: Bool

    var body: some View {
        ZStack {
            OcticonShape(path: strokes).stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            OcticonShape(path: fills).fill()
        }
        .frame(width: 16, height: 16)
    }

    private var strokes: Path {
        var path = Path()
        // Left rail: circle, line, circle; then the bottom-right circle.
        path.addPath(.circle(at: CGPoint(x: 3.25, y: 3.25), radius: 1.5))
        path.move(to: CGPoint(x: 3.25, y: 5.6))
        path.addLine(to: CGPoint(x: 3.25, y: 10.4))
        path.addPath(.circle(at: CGPoint(x: 3.25, y: 12.75), radius: 1.5))
        path.addPath(.circle(at: CGPoint(x: 12.75, y: 12.75), radius: 1.5))
        if !isDraft {
            // Arrow shaft curving from the top into the right rail.
            path.move(to: CGPoint(x: 8.0, y: 3.25))
            path.addLine(to: CGPoint(x: 10.5, y: 3.25))
            path.addQuadCurve(to: CGPoint(x: 12.75, y: 5.5), control: CGPoint(x: 12.75, y: 3.25))
            path.addLine(to: CGPoint(x: 12.75, y: 10.4))
        }
        return path
    }

    private var fills: Path {
        var path = Path()
        if isDraft {
            // Dotted right rail.
            path.addPath(.circle(at: CGPoint(x: 12.75, y: 3.25), radius: 1.25))
            path.addPath(.circle(at: CGPoint(x: 12.75, y: 7.5), radius: 1.25))
        } else {
            // Arrowhead.
            path.move(to: CGPoint(x: 8.3, y: 1.1))
            path.addLine(to: CGPoint(x: 8.3, y: 5.4))
            path.addLine(to: CGPoint(x: 6.0, y: 3.25))
            path.closeSubpath()
        }
        return path
    }
}

/// GitHub's `git-merge` octicon, hand-traced from `git-merge-16`.
/// Tinted via `foregroundStyle`.
struct GitMergeIcon: View {
    var body: some View {
        OcticonShape(path: strokes)
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: 16, height: 16)
    }

    private var strokes: Path {
        var path = Path()
        // Main rail from the top-left node to the bottom-left node.
        path.move(to: CGPoint(x: 4.25, y: 5.35))
        path.addLine(to: CGPoint(x: 4.25, y: 10.65))
        // Curved branch from the top-left node into the right node.
        path.move(to: CGPoint(x: 5.45, y: 5.15))
        path.addCurve(
            to: CGPoint(x: 9.25, y: 8.25),
            control1: CGPoint(x: 6.25, y: 7.0),
            control2: CGPoint(x: 7.75, y: 8.25)
        )
        path.addLine(to: CGPoint(x: 10.65, y: 8.25))
        path.addPath(.circle(at: CGPoint(x: 5.0, y: 3.25), radius: 1.5))
        path.addPath(.circle(at: CGPoint(x: 4.25, y: 12.75), radius: 1.5))
        path.addPath(.circle(at: CGPoint(x: 12.75, y: 8.25), radius: 1.5))
        return path
    }
}

/// GitHub's `git-merge-queue` octicon, hand-traced in a 16×16 design space:
/// a top-left dot above a left rail ending in a ring, a middle dot, and a
/// bottom-right ring. Tinted via `foregroundStyle`.
struct MergeQueueIcon: View {
    var body: some View {
        ZStack {
            OcticonShape(path: fills).fill()
            OcticonShape(path: rings).stroke(lineWidth: 1.5)
        }
        .frame(width: 16, height: 16)
    }

    private var fills: Path {
        var path = Path()
        path.addPath(.circle(at: CGPoint(x: 3.75, y: 3.25), radius: 1.25))   // top-left dot
        path.addPath(.circle(at: CGPoint(x: 7.5, y: 6.0), radius: 1.25))     // middle dot
        // Left rail: rounded-top bar dropping into the bottom-left ring.
        path.addPath(Path(roundedRect: CGRect(x: 3.0, y: 7.0, width: 1.5, height: 4.0), cornerSize: CGSize(width: 0.75, height: 0.75)))
        return path
    }

    private var rings: Path {
        var path = Path()
        path.addPath(.circle(at: CGPoint(x: 3.75, y: 12.75), radius: 1.5))   // bottom-left ring
        path.addPath(.circle(at: CGPoint(x: 12.25, y: 8.5), radius: 1.5))    // bottom-right ring
        return path
    }
}

/// Octicon path drawn in a 16×16 design space, scaled to the frame. Plain
/// shapes, not `Canvas`, which rendered magenta in list rows after a state change.
private struct OcticonShape: Shape {
    var path: Path

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 16
        return path.applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}

private extension Path {
    static func circle(at center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

/// GitHub-style label chip: the label's own color as background,
/// black or white text picked by background brightness.
struct LabelPill: View {
    var label: PullRequest.Label

    var body: some View {
        Text(label.name)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(background, in: Capsule())
            .foregroundStyle(isLight ? Color.black : Color.white)
    }

    private var rgb: (red: Double, green: Double, blue: Double) {
        guard label.color.count == 6, let value = UInt32(label.color, radix: 16) else {
            return (0.5, 0.5, 0.5)
        }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    private var background: Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private var isLight: Bool {
        0.299 * rgb.red + 0.587 * rgb.green + 0.114 * rgb.blue > 0.6
    }
}
