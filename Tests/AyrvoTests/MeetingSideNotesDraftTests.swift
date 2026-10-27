import Testing
@testable import Ayrvo

struct MeetingSideNotesDraftTests {
    @Test func testLoadingExistingNotesDoesNotScheduleAWrite() {
        var draft = MeetingSideNotesDraft()
        draft.load("Existing notes")
        var writes = 0
        draft.flush { _ in writes += 1 }
        #expect(draft.text == "Existing notes")
        #expect(writes == 0)
    }

    @Test func testFlushWritesOnlyTheLatestEdit() {
        var draft = MeetingSideNotesDraft()
        draft.edit("First edit")
        draft.edit("Latest edit")
        var saved: [String] = []
        draft.flush { saved.append($0) }
        draft.flush { saved.append($0) }
        #expect(saved == ["Latest edit"])
        #expect(!draft.needsFlush)
    }

    @Test func testReloadDoesNotReplacePendingLocalChanges() {
        var draft = MeetingSideNotesDraft()
        draft.load("Saved notes")
        draft.edit("Unsaved notes")
        draft.load("Another saved version")
        #expect(draft.text == "Unsaved notes")
        #expect(draft.needsFlush)
    }

    @Test func testUnchangedTextDoesNotBecomePending() {
        var draft = MeetingSideNotesDraft()
        draft.load("Saved notes")
        draft.edit("Saved notes")
        #expect(!draft.needsFlush)
    }
}
