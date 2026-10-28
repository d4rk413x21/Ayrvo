import SwiftUI
import AppKit

struct TrackerTaskRow: View {
    let task: TrackedTask
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onClaim: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.ayrvoActionColor) private var actionColor

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onTap) {
                Image(systemName: task.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(task.isChecked ? Theme.mint(scheme) : Theme.tertiary(scheme))
            }
            .buttonStyle(.plain)
            .help(task.isChecked ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.text)
                    .font(.ayrvo(13, .medium))
                    .foregroundStyle(task.isChecked ? Theme.secondary(scheme) : Theme.heading(scheme))
                    .strikethrough(task.isChecked)
                    .lineLimit(3)

                if let detail = task.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.ayrvo(11))
                        .foregroundStyle(Theme.tertiary(scheme))
                        .lineLimit(2)
                }

                if let source = task.source {
                    Text("From \(source.meetingTitle)")
                        .font(.ayrvo(9))
                        .foregroundStyle(Theme.tertiary(scheme).opacity(0.7))
                }
            }

            Spacer(minLength: 0)

            Image(systemName: task.priority.systemImage)
                .font(.system(size: 10))
                .foregroundStyle(task.priority.color.opacity(0.8))
                .help(task.priority.label)

            if let owner = task.owner {
                Text(owner)
                    .font(.ayrvo(9, .semibold))
                    .foregroundStyle(task.isMine ? actionColor : Theme.blueberry(scheme))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (task.isMine ? actionColor : Theme.blueberry(scheme)).opacity(0.12),
                        in: Capsule()
                    )
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit\u{2026}") { onEdit() }
            Button("Mark as mine") { onClaim() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
        .onTapGesture(count: 2) { onEdit() }
        .accessibilityAction(named: Text("Edit task")) { onEdit() }
        .focusable()
        .onKeyPress(.return) { onEdit(); return .handled }
    }
}
