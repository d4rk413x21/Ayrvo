import AppKit
import Foundation

/// Renders a meeting as a paginated PDF (US Letter) via NSPrintOperation.
///
/// Builds an `NSAttributedString` from the meeting title + summary + transcript,
/// applies sensible defaults for US Letter margins and font, and runs a print
/// operation that writes PDF to `dest`. No web view required.
enum PDFExporter {
    /// Produce a PDF at `dest` for `meeting`.
    static func exportPDF(
        meeting: Meeting,
        summaryMarkdown: String,
        segments: [TranscriptSegment],
        to dest: URL
    ) throws {
        let attributed = build(meeting: meeting, summaryMarkdown: summaryMarkdown, segments: segments)
        let printView = NSTextView()
        printView.frame = NSRect(x: 0, y: 0, width: 612, height: 792)  // US Letter @ 72dpi
        printView.textContainerInset = NSSize(width: 54, height: 54)  // 0.75" margins
        printView.isEditable = false
        printView.isSelectable = true
        printView.textStorage?.setAttributedString(attributed)

        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 612, height: 792)  // US Letter
        printInfo.orientation = .portrait
        printInfo.scalingFactor = 1.0
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.leftMargin = 54
        printInfo.rightMargin = 54
        printInfo.topMargin = 54
        printInfo.bottomMargin = 54
        // `.save` + `jobSavingURL` direct NSPrintOperation to write the PDF without
        // showing a panel. `runOperation` returns the page count.
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = dest

        let operation = NSPrintOperation(view: printView, printInfo: printInfo)
        operation.jobTitle = meeting.title
        operation.showsProgressPanel = false
        operation.showsPrintPanel = false
        let didRun = operation.run()
        guard didRun,
              FileManager.default.fileExists(atPath: dest.path) else {
            throw NSError(
                domain: "PDFExporter", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "PDF write failed — no file at \(dest.path)"])
        }
        _ = didRun
    }

    // MARK: - Assembly

    /// Build the attributed string for the whole document.
    private static func build(
        meeting: Meeting,
        summaryMarkdown: String,
        segments: [TranscriptSegment]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 22),
            .foregroundColor: NSColor.labelColor
        ]
        result.append(NSAttributedString(string: meeting.title + "\n", attributes: titleAttrs))

        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        let duration = TemplateRenderer.duration(meeting.duration)
        let attendees = meeting.attendees.isEmpty
            ? meeting.speakers.map(\.name)
            : meeting.attendees
        let metaLine = "\(formatter.string(from: meeting.createdAt)) · \(duration)"
            + (attendees.isEmpty ? "" : " · \(attendees.joined(separator: ", "))")
        result.append(NSAttributedString(string: metaLine + "\n\n", attributes: metaAttrs))

        if !summaryMarkdown.isEmpty {
            let sectionAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 14),
                .foregroundColor: NSColor.labelColor
            ]
            result.append(NSAttributedString(string: "Notes\n", attributes: sectionAttrs))
            result.append(renderMarkdown(summaryMarkdown))
            result.append(NSAttributedString(string: "\n\n"))
        }

        if !segments.isEmpty {
            let sectionAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 14),
                .foregroundColor: NSColor.labelColor
            ]
            result.append(NSAttributedString(string: "Transcript\n", attributes: sectionAttrs))
            result.append(transcript(segments: segments, speakers: meeting.speakers))
        }
        return result
    }

    /// Minimal markdown → attributed string. Mirrors HTMLExporter.renderMarkdown's
    /// supported subset, but emits NSAttributedString runs instead of HTML.
    private static func renderMarkdown(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = NSFont.systemFont(ofSize: 12)
        let lines = markdown.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                result.append(NSAttributedString(string: "\n"))
                continue
            }
            if trimmed.hasPrefix("### ") {
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 13)]
                let body = String(trimmed.dropFirst(4))
                result.append(NSAttributedString(string: body + "\n", attributes: attrs))
            } else if trimmed.hasPrefix("## ") {
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 14)]
                let body = String(trimmed.dropFirst(3))
                result.append(NSAttributedString(string: body + "\n", attributes: attrs))
            } else if trimmed.hasPrefix("# ") {
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 16)]
                let body = String(trimmed.dropFirst(2))
                result.append(NSAttributedString(string: body + "\n", attributes: attrs))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let attrs: [NSAttributedString.Key: Any] = [.font: bodyFont]
                let body = String(trimmed.dropFirst(2))
                result.append(NSAttributedString(string: "  • " + body + "\n", attributes: attrs))
            } else if trimmed == "---" {
                let ruleAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 1),
                    .backgroundColor: NSColor.separatorColor
                ]
                let rule = String(repeating: "─", count: 60) + "\n"
                result.append(NSAttributedString(string: rule, attributes: ruleAttrs))
            } else {
                let attrs: [NSAttributedString.Key: Any] = [.font: bodyFont]
                let suffix = index < lines.count - 1 ? "\n" : ""
                result.append(NSAttributedString(string: line + suffix, attributes: attrs))
            }
        }
        return result
    }

    /// Transcript turns as attributed text. Mirrors TranscriptFormatter.markdown
    /// but with font/color runs. Speaker names resolved via the `speakers` map
    /// (same approach as HTMLExporter.transcriptTurns).
    private static func transcript(segments: [TranscriptSegment], speakers: [Speaker]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let speakerFont = NSFont.boldSystemFont(ofSize: 11)
        let bodyFont = NSFont.systemFont(ofSize: 11)
        let speakerColor = NSColor.secondaryLabelColor
        let names = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0.name) })

        var currentSpeaker: String?
        var texts: [String] = []
        var startTime: TimeInterval = 0

        func flush() {
            guard let speaker = currentSpeaker, !texts.isEmpty else { return }
            let who = names[speaker] ?? speaker
            result.append(NSAttributedString(
                string: who + "\n",
                attributes: [.font: speakerFont, .foregroundColor: speakerColor]))
            let time = MeetingArchive.timestamp(startTime)
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            result.append(NSAttributedString(string: time + "\n", attributes: timeAttrs))
            result.append(NSAttributedString(
                string: texts.joined(separator: " ") + "\n\n",
                attributes: [.font: bodyFont]))
        }

        for segment in segments {
            if segment.speakerID != currentSpeaker {
                flush()
                currentSpeaker = segment.speakerID
                texts = []
                startTime = segment.start
            }
            texts.append(segment.text)
        }
        flush()
        return result
    }
}
