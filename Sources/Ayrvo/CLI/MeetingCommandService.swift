import Foundation

enum MeetingCommandError: LocalizedError, Equatable {
    case badArgument(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .badArgument(let message): return message
        case .notFound(let id): return "No meeting with id \(id)"
        }
    }
}

final class MeetingCommandService {
    static let liveDefaultWindowMinutes = 6

    private let archive: MeetingArchive

    init(archive: MeetingArchive) {
        self.archive = archive
    }

    func list(limit: Int = 20, offset: Int = 0) -> String {
        let limit = max(1, min(200, limit))
        let offset = max(0, offset)
        let all = archive.allMeetings()
        if all.isEmpty { return "No meetings recorded yet." }
        guard offset < all.count else {
            return "No more meetings (offset \(offset) ≥ \(all.count))."
        }
        let page = Array(all.dropFirst(offset).prefix(limit))
        var body = page.map(Self.describe).joined(separator: "\n")
        let nextOffset = offset + page.count
        if nextOffset < all.count {
            body += "\n\nnext_offset: \(nextOffset) (more meetings remain; pass offset=\(nextOffset) to fetch the next page)"
        }
        return body
    }

    func search(query: String, limit: Int = 20, offset: Int = 0) throws -> String {
        guard !query.isEmpty else { throw MeetingCommandError.badArgument("'query' is required") }
        let limit = max(1, min(200, limit))
        let offset = max(0, offset)
        let all = archive.search(query)
        if all.isEmpty { return "No meetings matched \"\(query)\"." }
        guard offset < all.count else {
            return "No more matches for \"\(query)\" (offset \(offset) ≥ \(all.count))."
        }
        let page = Array(all.dropFirst(offset).prefix(limit))
        var body = page.map { hit in
            Self.describe(hit.meeting) + hit.excerpts.map { "\n    · \($0)" }.joined()
        }.joined(separator: "\n")
        let nextOffset = offset + page.count
        if nextOffset < all.count {
            body += "\n\nnext_offset: \(nextOffset) (more matches remain; pass offset=\(nextOffset) to fetch the next page)"
        }
        return body
    }

    func show(id: String) throws -> String {
        let meeting = try meeting(id: id)
        let summary = archive.summary(for: meeting.id)
        var output = Self.describe(meeting)
        if !meeting.attendees.isEmpty {
            output += "\nAttendees: \(meeting.attendees.joined(separator: ", "))"
        }
        output += "\nSpeakers: \(meeting.speakers.map(\.name).joined(separator: ", "))"
        output += "\n\n" + (summary.isEmpty ? "(no summary yet)" : summary)
        return output
    }

    func transcript(id: String) throws -> String {
        let meeting = try meeting(id: id)
        let segments = archive.transcript(for: meeting.id)
        if segments.isEmpty { return "(no transcript for \(meeting.title))" }
        return "# \(meeting.title)\n\n"
            + TranscriptFormatter.plainText(segments, speakers: meeting.speakers)
    }

    func live(minutes: Int? = nil) -> String {
        Self.liveTranscriptText(archive: archive, minutes: minutes)
    }

    private func meeting(id idString: String) throws -> Meeting {
        guard let id = UUID(uuidString: idString) else {
            throw MeetingCommandError.badArgument("'id' must be a meeting UUID")
        }
        guard let meeting = archive.meeting(id: id) else {
            throw MeetingCommandError.notFound(idString)
        }
        return meeting
    }

    static func describe(_ meeting: Meeting) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        var line = "[\(meeting.id.uuidString)] \(meeting.title) — \(formatter.string(from: meeting.createdAt))"
        if meeting.duration > 0 { line += " (\(TemplateRenderer.duration(meeting.duration)))" }
        return line
    }

    static func liveTranscriptText(
        archive: MeetingArchive,
        now: Date = Date(),
        minutes: Int? = nil
    ) -> String {
        guard let meeting = archive.allMeetings().first(where: { $0.state == .recording }),
              let modified = archive.liveTranscriptModified(for: meeting.id),
              now.timeIntervalSince(modified) < 60
        else { return "No meeting is being recorded right now." }
        let all = archive.liveTranscript(for: meeting.id)
        guard !all.isEmpty else {
            return "A meeting is being recorded (\"\(meeting.title)\"), but nothing has been transcribed yet."
        }

        let window = minutes ?? liveDefaultWindowMinutes
        var segments = all
        var trimmed = false
        if window > 0, let latest = all.map(\.end).max() {
            let cutoff = latest - TimeInterval(window) * 60
            let recent = all.filter { $0.end >= cutoff }
            if recent.count < all.count { segments = recent; trimmed = true }
        }
        let body = TranscriptFormatter.plainText(segments, speakers: LiveTranscriber.speakers)
        let scope = trimmed
            ? "the last \(window) minutes of the live transcript (call again with a larger \"minutes\", or minutes=0 for the whole meeting, if you need earlier context)"
            : "the live transcript so far"

        return """
        [The user is IN this meeting right now and needs a fast, glanceable answer. Reply in 1-2 sentences, no preamble, and don't summarize the transcript back — answer only what was asked.]

        Here is \(scope) of "\(meeting.title)". This is a real-time approximation (it may lag a few seconds behind and isn't final):

        \(body)

        [Reminder: the user is live in the meeting — answer now, in 1-2 sentences.]
        """
    }
}
