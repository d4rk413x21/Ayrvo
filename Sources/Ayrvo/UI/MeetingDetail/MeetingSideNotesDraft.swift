/// Tracks local edits before they are handed to persistence and its failed-write recovery queue.
struct MeetingSideNotesDraft {
    private(set) var text = ""
    private(set) var needsFlush = false

    mutating func load(_ text: String) {
        guard !needsFlush else { return }
        self.text = text
    }

    mutating func edit(_ text: String) {
        guard self.text != text else { return }
        self.text = text
        needsFlush = true
    }

    mutating func flush(using write: (String) -> Void) {
        guard needsFlush else { return }
        write(text)
        needsFlush = false
    }
}
