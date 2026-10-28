import SwiftUI

struct MeetingNotesSection: View {
    @Environment(\.colorScheme) private var scheme
    let layout: MeetingNotesLayout
    let sideNotes: String
    @Binding var showsSideNotes: Bool
    @Binding var draft: String?
    let processingStage: String?
    let reader: MeetingSummaryView
    let emptyNotes: MeetingEmptyNotesView
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: layout.centersContent ? .center : .leading, spacing: 12) {
            switch layout.content {
            case .editor:
                MeetingNotesEditor(
                    text: Binding(get: { draft ?? "" }, set: { draft = $0 }),
                    onSave: onSave,
                    onCancel: onCancel)
            case .summary:
                if !showsSideNotes, !sideNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    myNotesReader.padding(.bottom, 16)
                }
                reader
            case .sideNotes:
                myNotesReader
            case .preparation:
                prepPlaceholder
            case .recording:
                recordingPlaceholder
            case .working:
                EmptyStateView(title: "Working on it…", message: processingStage ?? "Writing your notes…")
            case .empty:
                emptyNotes
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: layout.centersContent ? .infinity : nil,
            alignment: layout.centersContent ? .center : .leading)
    }

    private var prepPlaceholder: some View {
        Text("Write notes")
            .font(.ayrvo(14))
            .foregroundStyle(Theme.tertiary(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 40)
    }

    private var recordingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsSideNotes {
                Text("Enhanced notes will appear here as the meeting is summarized. The live transcript is in the Transcript panel below.")
                    .font(.ayrvo(13))
                    .foregroundStyle(Theme.tertiary(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 40)
            } else {
                Button {
                    showsSideNotes = true
                } label: {
                    Text("Enhanced notes will appear here. Open My notes on the left, or use the Transcript panel below for the live transcript.")
                    .font(.ayrvo(14))
                    .foregroundStyle(Theme.tertiary(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open My notes")
            }
        }
    }

    private var myNotesReader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("My notes")
                .font(.ayrvo(12, .semibold))
                .foregroundStyle(Theme.secondary(scheme))
            Text(sideNotes)
                .font(.ayrvo(13))
                .foregroundStyle(Theme.secondary(scheme))
                .textSelection(.enabled)
                .lineSpacing(4)
        }
    }

}
