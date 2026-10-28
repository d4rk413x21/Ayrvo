import Foundation

/// Everything the pipeline is allowed to change on a meeting. AppState
/// merges this onto a FRESH copy of the meeting, so user edits made during
/// the (minutes-long) run are never clobbered by a stale snapshot.
struct ProcessingOutcome: Sendable {
    var state: MeetingState
    var notice: String?
    var speakers: [Speaker]?
    var platformSpeakerAttribution: Bool = false
    var summaryProvider: String?
    var generatedTitle: String?
}

/// Progressive summary signal for the UI. The draft streams in seconds after
/// Stop; the improvement replaces it once the accurate transcript is ready.
enum SummaryUpdate: Sendable {
    /// Growing markdown of the pass currently streaming (draft, or the sole pass
    /// when there is no live transcript). May be empty at the very start.
    case streaming(String)
    /// A draft is saved; an improvement pass will follow (badge: "Draft · improving").
    case draftSaved
    /// The progressive phase is over — the UI should read the saved summary.
    case done
}

enum SummaryOutcome: Sendable {
    case success(String, provider: String)
    case failure(String)
}
