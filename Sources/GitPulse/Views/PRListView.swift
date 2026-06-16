import SwiftUI

struct PRListView: View {
    var title: String
    var systemImage: String
    var pullRequests: [PullRequest]
    var unreadURLs: Set<URL> = []
    var hiddenURLs: Set<URL> = []
    var isActive: Bool
    @Binding var selectedID: PullRequest.ID?

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
                List(pullRequests, selection: $selectedID) { pullRequest in
                    PRRow(
                        pullRequest: pullRequest,
                        hasNotification: unreadURLs.contains(pullRequest.url),
                        isHidden: hiddenURLs.contains(pullRequest.url)
                    )
                    .tag(pullRequest.id)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PRRow: View {
    @Environment(\.openURL) private var openURL
    @Environment(Session.self) private var session
    @State private var isHovering = false
    var pullRequest: PullRequest
    var hasNotification: Bool = false
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
                Circle()
                    .fill(.blue)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)
                    .help("Unread notification — press space to dismiss")
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
                    Task { await session.unhide(url: pullRequest.url) }
                }
            } else {
                Button("Hide Pull Request") { session.hide(pullRequest) }
            }
        }
    }

    private func open() {
        openURL(pullRequest.url)
        session.markRead(prURL: pullRequest.url)
    }

    private var isQueued: Bool {
        pullRequest.mergeQueueState == "QUEUED" || pullRequest.mergeQueueState == "AWAITING_CHECKS"
    }

    /// Gold merge-queue glyph while the PR waits in the queue, otherwise the
    /// green open-PR icon (gray dotted for drafts) — like GitHub's list.
    @ViewBuilder
    private var stateIcon: some View {
        if isQueued {
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
            "by \(pullRequest.author)",
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
        Canvas { context, size in
            let scale = min(size.width, size.height) / 16
            context.scaleBy(x: scale, y: scale)
            let stroke = StrokeStyle(lineWidth: 1.5, lineCap: .round)

            // Left rail: circle, line, circle.
            context.stroke(circle(at: CGPoint(x: 3.25, y: 3.25)), with: .foreground, style: stroke)
            context.stroke(line(x: 3.25, from: 5.6, to: 10.4), with: .foreground, style: stroke)
            context.stroke(circle(at: CGPoint(x: 3.25, y: 12.75)), with: .foreground, style: stroke)

            // Bottom-right circle.
            context.stroke(circle(at: CGPoint(x: 12.75, y: 12.75)), with: .foreground, style: stroke)

            if isDraft {
                // Dotted right rail.
                context.fill(dot(at: CGPoint(x: 12.75, y: 3.25)), with: .foreground)
                context.fill(dot(at: CGPoint(x: 12.75, y: 7.5)), with: .foreground)
            } else {
                // Arrow curving from the top into the right rail.
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: 8.0, y: 3.25))
                    path.addLine(to: CGPoint(x: 10.5, y: 3.25))
                    path.addQuadCurve(
                        to: CGPoint(x: 12.75, y: 5.5),
                        control: CGPoint(x: 12.75, y: 3.25)
                    )
                    path.addLine(to: CGPoint(x: 12.75, y: 10.4))
                }, with: .foreground, style: stroke)
                context.fill(Path { path in
                    path.move(to: CGPoint(x: 8.3, y: 1.1))
                    path.addLine(to: CGPoint(x: 8.3, y: 5.4))
                    path.addLine(to: CGPoint(x: 6.0, y: 3.25))
                    path.closeSubpath()
                }, with: .foreground)
            }
        }
        .frame(width: 16, height: 16)
    }

    private func circle(at center: CGPoint) -> Path {
        Path(ellipseIn: CGRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3))
    }

    private func dot(at center: CGPoint) -> Path {
        Path(ellipseIn: CGRect(x: center.x - 1.25, y: center.y - 1.25, width: 2.5, height: 2.5))
    }

    private func line(x: CGFloat, from startY: CGFloat, to endY: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: x, y: startY))
            path.addLine(to: CGPoint(x: x, y: endY))
        }
    }
}

/// GitHub's `git-merge-queue` octicon, hand-traced in a 16×16 design space:
/// a top-left dot above a left rail ending in a ring, a middle dot, and a
/// bottom-right ring. Ring holes are erased with a `.clear` pass so the row
/// background shows through. Tinted via `foregroundStyle`.
struct MergeQueueIcon: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 16
            context.scaleBy(x: scale, y: scale)

            // Solid bodies: two dots, the left rail, and the two outer rings.
            var solid = Path()
            solid.addPath(dot(at: CGPoint(x: 3.75, y: 3.25), r: 1.25))   // top-left dot
            solid.addPath(dot(at: CGPoint(x: 7.5, y: 6.0), r: 1.25))     // middle dot
            // Left rail: rounded-top bar dropping into the bottom-left ring.
            solid.addPath(Path(roundedRect: CGRect(x: 3.0, y: 7.0, width: 1.5, height: 6.0), cornerSize: CGSize(width: 0.75, height: 0.75)))
            solid.addPath(dot(at: CGPoint(x: 3.75, y: 12.75), r: 2.25))  // bottom-left ring (outer)
            solid.addPath(dot(at: CGPoint(x: 12.25, y: 8.5), r: 2.25))   // bottom-right ring (outer)
            context.fill(solid, with: .foreground)

            // Punch the ring holes so the background shows through.
            var holes = Path()
            holes.addPath(dot(at: CGPoint(x: 3.75, y: 12.75), r: 0.75))
            holes.addPath(dot(at: CGPoint(x: 12.25, y: 8.5), r: 0.75))
            context.blendMode = .clear
            context.fill(holes, with: .color(.black))
        }
        .frame(width: 16, height: 16)
    }

    private func dot(at center: CGPoint, r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
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

/// Single window-wide key monitor for keyboard navigation.
/// Installed ONCE by DashboardView — never per-pane — so each keypress is handled exactly once.
struct KeyNavigator: NSViewRepresentable {
    var onUp: () -> Void
    var onDown: () -> Void
    var onLeft: () -> Void
    var onRight: () -> Void
    var onReturn: () -> Void
    var onSpace: () -> Void
    var onHide: () -> Void
    var onToggleHiddenVisibility: () -> Void
    var onCopy: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak coordinator = context.coordinator] event in
            guard let coordinator else { return event }
            let keyCode = event.keyCode
            var consume = false
            MainActor.assumeIsolated {
                switch keyCode {
                case 126: coordinator.onUp();    consume = true   // Up
                case 125: coordinator.onDown();  consume = true   // Down
                case 123: coordinator.onLeft();  consume = true   // Left
                case 124: coordinator.onRight(); consume = true   // Right
                case 36, 76: coordinator.onReturn(); consume = true  // Return / Enter
                case 49: coordinator.onSpace(); consume = true  // Space
                case 4:
                    if event.modifierFlags.contains(.command) {
                        coordinator.onToggleHiddenVisibility()
                    } else {
                        coordinator.onHide()
                    }
                    consume = true  // H / Command-H
                case 8 where event.modifierFlags.contains(.command):
                    coordinator.onCopy()
                    consume = true  // Command-C
                default: break
                }
            }
            return consume ? nil : event
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onUp = onUp
        context.coordinator.onDown = onDown
        context.coordinator.onLeft = onLeft
        context.coordinator.onRight = onRight
        context.coordinator.onReturn = onReturn
        context.coordinator.onSpace = onSpace
        context.coordinator.onHide = onHide
        context.coordinator.onToggleHiddenVisibility = onToggleHiddenVisibility
        context.coordinator.onCopy = onCopy
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onUp: onUp, onDown: onDown, onLeft: onLeft, onRight: onRight, onReturn: onReturn, onSpace: onSpace, onHide: onHide, onToggleHiddenVisibility: onToggleHiddenVisibility, onCopy: onCopy)
    }

    class Coordinator {
        var onUp: () -> Void
        var onDown: () -> Void
        var onLeft: () -> Void
        var onRight: () -> Void
        var onReturn: () -> Void
        var onSpace: () -> Void
        var onHide: () -> Void
        var onToggleHiddenVisibility: () -> Void
        var onCopy: () -> Void
        var monitor: Any?

        init(onUp: @escaping () -> Void, onDown: @escaping () -> Void, onLeft: @escaping () -> Void, onRight: @escaping () -> Void, onReturn: @escaping () -> Void, onSpace: @escaping () -> Void, onHide: @escaping () -> Void, onToggleHiddenVisibility: @escaping () -> Void, onCopy: @escaping () -> Void) {
            self.onUp = onUp; self.onDown = onDown; self.onLeft = onLeft; self.onRight = onRight; self.onReturn = onReturn; self.onSpace = onSpace; self.onHide = onHide; self.onToggleHiddenVisibility = onToggleHiddenVisibility; self.onCopy = onCopy
        }

        deinit { monitor.map { NSEvent.removeMonitor($0) } }
    }
}
