import AppKit
import SwiftUI

struct MeetingShareNotesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.ayrvoActionColor) private var actionColor
    @State private var copiedShareNotes = false

    let meeting: Meeting
    @ObservedObject var store: MeetingStore

    /// Copies the read-only notes HTML to the pasteboard or saves it locally.
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.ayrvo(16, .medium))
                        .foregroundStyle(actionColor)
                    Text("Share Notes")
                        .font(.ayrvo(18, .bold))
                        .foregroundStyle(Theme.heading(scheme))
                }
                Text("A read-only page with the summary, action items, and transcript.")
                    .font(.ayrvo(12))
                    .foregroundStyle(Theme.secondary(scheme))
            }

            // Action buttons as cards
            VStack(spacing: 10) {
                shareActionCard(
                    icon: "doc.on.doc",
                    title: "Copy HTML",
                    subtitle: "Copy to clipboard"
                ) { copyShareNotesHTML() }

                shareActionCard(
                    icon: "square.and.arrow.down",
                    title: "Save HTML",
                    subtitle: "Save as a file"
                ) { saveShareNotesHTML() }
            }

            // Status
            if copiedShareNotes {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.mint(scheme))
                    Text("HTML copied to clipboard!")
                        .font(.ayrvo(11, .medium))
                        .foregroundStyle(Theme.mint(scheme))
                    Spacer()
                }
                .padding(10)
                .background(Theme.mint(scheme).opacity(0.08),
                           in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Spacer()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
        }
        .padding(24)
        .frame(width: 440, height: 360)
        .onDisappear { copiedShareNotes = false }
    }

    private func shareActionCard(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.ayrvo(18, .medium))
                    .foregroundStyle(actionColor)
                    .frame(width: 36, height: 36)
                    .background(
                        actionColor.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.ayrvo(13, .semibold))
                        .foregroundStyle(Theme.heading(scheme))
                    Text(subtitle)
                        .font(.ayrvo(10))
                        .foregroundStyle(Theme.tertiary(scheme))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.ayrvo(10, .medium))
                    .foregroundStyle(Theme.tertiary(scheme))
            }
            .padding(12)
            .background(
                Theme.card(scheme).opacity(0.7),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func sharedNotesInputs() -> (Meeting, String, [TranscriptTurn], [ActionItem]) {
        let m = meeting
        let summary = store.summary(for: m.id)
        let turns = TranscriptTurnBuilder.turns(from: store.transcript(for: m.id))
        let items = ActionItemParser.parse(summary)
        return (m, summary, turns, items)
    }

    private func copyShareNotesHTML() {
        let (m, summary, turns, items) = sharedNotesInputs()
        let html = SharedNotesExporter.exportHTML(
            meeting: m, summary: summary, transcript: turns, actionItems: items)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(html, forType: .string)
        copiedShareNotes = true
    }

    private func saveShareNotesHTML() {
        let (m, summary, turns, items) = sharedNotesInputs()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = meeting.title.replacingOccurrences(of: "/", with: "-") + ".html"
        panel.allowedContentTypes = [.html]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let html = SharedNotesExporter.exportHTML(
            meeting: m, summary: summary, transcript: turns, actionItems: items)
        try? FilePersistence.write(Data(html.utf8), to: dest)
    }
}
