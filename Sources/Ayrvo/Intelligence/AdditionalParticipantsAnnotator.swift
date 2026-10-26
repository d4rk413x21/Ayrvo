import Foundation

/// Computes the list of meeting participants seen by Zoom's Accessibility tree
/// but absent from the calendar invite, so they can be annotated at the end of
/// the generated notes.
///
/// Pure — no I/O, no AppKit. Takes the Zoom roster and the calendar attendees
/// and returns the names that appear in the roster but not the attendees,
/// excluding the local participant (the Mac account holder — they're always
/// "You" in the notes).
enum AdditionalParticipantsAnnotator {
    /// Build the "Additional participants" markdown block, or nil when there's
    /// nothing to annotate (no extras, or no roster at all).
    ///
    /// - Parameters:
    ///   - roster: names Zoom's AX tree reported as present in the meeting.
    ///   - attendees: names from the calendar invite.
    ///   - localParticipantCheck: predicate identifying the local user's display
    ///     name so they aren't listed as an "additional" participant. Defaults to
    ///     `ZoomActiveSpeakerReader.isLocalParticipant` in production; injected
    ///     in tests.
    static func annotation(
        roster: [String],
        attendees: [String],
        localParticipantCheck: (String) -> Bool = ZoomActiveSpeakerReader.isLocalParticipant
    ) -> String? {
        guard !roster.isEmpty else { return nil }

        let attendeeKeys = Set(attendees.map { Self.key($0) })
        let extras = dedup(roster)
            .filter { !localParticipantCheck($0) }          // drop "You"
            .filter { !attendeeKeys.contains(Self.key($0)) } // drop calendar names
        guard !extras.isEmpty else { return nil }

        let names = extras.joined(separator: ", ")
        return """
        ---

        **Additional participants (from Zoom, not on the calendar invite):** \(names)
        """
    }

    /// Normalize a display name for matching: lowercase, trimmed, collapse
    /// internal whitespace. "Lian Fernandes" / "lian fernandes " / "Lian  Fernandes"
    /// all match.
    private static func key(_ name: String) -> String {
        name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func dedup(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in names {
            let nameKey = Self.key(name)
            guard !seen.contains(nameKey) else { continue }
            seen.insert(nameKey)
            out.append(name)
        }
        return out
    }
}
