/// Resolves the document's note content and alignment from the current recording/editing state.
struct MeetingNotesLayout: Equatable {
    enum Content: Equatable { case editor, summary, sideNotes, preparation, recording, working, empty }
    enum PrimaryAction: Equatable { case resume, retry }

    let content: Content
    let centersContent: Bool

    init(isRecording: Bool, isPrep: Bool, isEditing: Bool, hasDisplayedNotes: Bool,
         isWorking: Bool, hasSideNotes: Bool, showsSideNotes: Bool) {
        let hasInlineNotes = hasSideNotes && !showsSideNotes
        centersContent = !isRecording && !isPrep && !isEditing && !hasDisplayedNotes && !hasInlineNotes
        if isPrep && !isRecording {
            content = .preparation
        } else if isEditing {
            content = .editor
        } else if hasDisplayedNotes {
            content = .summary
        } else if !isRecording && hasInlineNotes {
            content = .sideNotes
        } else if isWorking {
            content = .working
        } else {
            content = isRecording ? .recording : .empty
        }
    }

    static func primaryAction(canContinueRecording: Bool, resumesInFooter: Bool, isFailed: Bool) -> PrimaryAction? {
        if canContinueRecording { return resumesInFooter ? nil : .resume }
        return isFailed ? .retry : nil
    }
}
