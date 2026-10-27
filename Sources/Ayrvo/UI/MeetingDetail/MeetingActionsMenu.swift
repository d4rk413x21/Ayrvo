import AppKit
import SwiftUI

struct MeetingActionsMenu: View {
    let meeting: Meeting
    @ObservedObject var store: MeetingStore
    @Binding var previewError: String?
    let onDelete: () -> Void

    var body: some View {
        Menu {
            Button("Copy notes") { copyNotes() }
            Button("Preview in browser") { previewInBrowser() }
            Divider()
            Menu("Export…") {
                Button("HTML…") { exportHTML() }
                Button("PDF…") { exportPDF() }
                Button("Markdown…") { exportMarkdown() }
                Button("Subtitles (.srt)…") { exportSRT() }
                Button("Subtitles (.vtt)…") { exportVTT() }
                Divider()
                Button("CSV (all meetings)…") { exportCSVAll() }
                    .disabled(store.meetings.isEmpty)
            }
            FolderPickerMenu(
                currentFolderID: meeting.folderID,
                calendarTitle: meeting.calendarEventTitle ?? meeting.title,
                meetingID: meeting.id
            ) {
                Text("Move to folder…")
            }
            Button("Show files in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(
                    [store.archive.folder(for: meeting.id)])
            }
            Divider()
            Button("Move to trash", role: .destructive) { onDelete() }
        } label: {
            Label("More actions", systemImage: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .labelStyle(.iconOnly)
        .help("More actions")
        .accessibilityLabel("More actions")
    }

    private func copyNotes() {
        let text = store.summary(for: meeting.id)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func previewInBrowser() {
        previewError = nil
        let html = HTMLExporter.html(
            meeting: meeting,
            summaryMarkdown: store.summary(for: meeting.id),
            segments: store.transcript(for: meeting.id))
        let safeName = meeting.title.replacingOccurrences(of: "/", with: "-")
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ayrvo — \(safeName).html")
        do {
            try FilePersistence.write(Data(html.utf8), to: file)
            NSWorkspace.shared.open(file)
        } catch {
            previewError = error.localizedDescription
        }
    }

    private func exportCSVAll() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Ayrvo meetings.csv"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let csv = CSVExporter.export(meetings: store.meetings)
        try? FilePersistence.write(Data(csv.utf8), to: dest)
    }

    private func exportHTML() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = safeFilename + ".html"
        panel.allowedContentTypes = [.html]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let html = HTMLExporter.html(
            meeting: meeting,
            summaryMarkdown: store.summary(for: meeting.id),
            segments: store.transcript(for: meeting.id))
        try? FilePersistence.write(Data(html.utf8), to: dest)
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = safeFilename + ".md"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let md = TranscriptFormatter.markdown(
            store.transcript(for: meeting.id),
            speakers: meeting.speakers)
        try? FilePersistence.write(Data(md.utf8), to: dest)
    }

    private func exportSRT() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = safeFilename + ".srt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let srt = TranscriptFormatter.srt(
            store.transcript(for: meeting.id),
            speakers: meeting.speakers)
        try? FilePersistence.write(Data(srt.utf8), to: dest)
    }

    private func exportVTT() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = safeFilename + ".vtt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let vtt = TranscriptFormatter.vtt(
            store.transcript(for: meeting.id),
            speakers: meeting.speakers)
        try? FilePersistence.write(Data(vtt.utf8), to: dest)
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = safeFilename + ".pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            try PDFExporter.exportPDF(
                meeting: meeting,
                summaryMarkdown: store.summary(for: meeting.id),
                segments: store.transcript(for: meeting.id),
                to: dest)
        } catch { PersistenceStatus.shared.report(error) }
    }

    private var safeFilename: String {
        meeting.title.replacingOccurrences(of: "/", with: "-")
    }
}
