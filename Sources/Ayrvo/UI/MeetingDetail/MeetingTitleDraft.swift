import Foundation

/// Keeps local edits separate from store updates until a save succeeds.
struct MeetingTitleDraft {
    var text: String
    private var baselineTitle: String
    private var failedTitle: String?

    init(_ title: String) {
        text = title
        baselineTitle = title
    }

    var normalizedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasChanges: Bool { normalizedText != baselineTitle || failedTitle != nil }

    mutating func update(_ title: String, isEditing: Bool) {
        guard !isEditing, !hasChanges else { return }
        self = Self(title)
    }

    mutating func save(using write: (String) -> Bool) -> Bool {
        guard hasChanges else { return true }
        let title = normalizedText
        guard !title.isEmpty else { return false }
        let saved = write(title)
        // Failed writes may already be visible in the store's in-memory meeting.
        guard saved else { failedTitle = title; return false }
        self = Self(title)
        return true
    }

    mutating func discard(currentTitle: String, hasPendingWrite: Bool, restore: (String) -> Void) {
        if let failedTitle, hasPendingWrite, currentTitle == failedTitle {
            restore(baselineTitle)
            self = Self(baselineTitle)
        } else {
            self = Self(currentTitle)
        }
    }
}
