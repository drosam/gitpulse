import SwiftUI

struct PRListView: View {
    var title: String
    var systemImage: String
    var pullRequests: [PullRequest]
    var unreadURLs: Set<URL> = []

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
                    PRRow(
                        pullRequest: pullRequest,
                        hasNotification: unreadURLs.contains(pullRequest.url)
                    )
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

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            stateIcon
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(pullRequest.title)
                        .fontWeight(.semibold)
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
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if hasNotification {
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                    .help("Unread notification")
            }

            if pullRequest.commentCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "bubble.right")
                    Text("\(pullRequest.commentCount)")
                }
                .font(.caption)
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
        .background(isHovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
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
        }
    }

    private func open() {
        openURL(pullRequest.url)
        session.markRead(prURL: pullRequest.url)
    }

    /// Green open-PR icon, gray dotted draft icon — like GitHub's list.
    private var stateIcon: some View {
        PullRequestIcon(isDraft: pullRequest.isDraft)
            .foregroundStyle(pullRequest.isDraft ? Color.secondary : Color.green)
            .help(pullRequest.isDraft ? "Draft pull request" : "Open pull request")
    }

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

/// GitHub-style label chip: the label's own color as background,
/// black or white text picked by background brightness.
struct LabelPill: View {
    var label: PullRequest.Label

    var body: some View {
        Text(label.name)
            .font(.caption2.weight(.semibold))
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
