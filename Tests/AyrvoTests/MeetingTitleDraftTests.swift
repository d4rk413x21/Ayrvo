import Testing
@testable import Ayrvo

struct MeetingTitleDraftTests {
    @Test func testCleanDraftFollowsExternalChangesWithoutWriting() {
        var draft = MeetingTitleDraft("Planning")
        draft.update("Renamed elsewhere", isEditing: false)
        #expect(draft.text == "Renamed elsewhere")
        #expect(!draft.hasChanges)
        #expect(draft.save { _ in Issue.record("Unexpected write"); return false })
    }

    @Test func testFocusPreservesTextUntilEditingEnds() {
        var draft = MeetingTitleDraft("Planning")
        draft.update("Renamed elsewhere", isEditing: true)
        #expect(draft.text == "Planning")
        #expect(!draft.hasChanges)
        draft.update("Renamed elsewhere", isEditing: false)
        #expect(draft.text == "Renamed elsewhere")
    }

    @Test func testLocalEditsSurviveStoreUpdatesAfterFocusLoss() {
        var draft = MeetingTitleDraft("Planning")
        draft.text = "My title"
        draft.update("Renamed elsewhere", isEditing: false)
        #expect(draft.text == "My title")
        #expect(draft.hasChanges)
    }

    @Test func testBlankTitleIsRetainedWithoutWriting() {
        var draft = MeetingTitleDraft("Planning")
        draft.text = " \n "
        #expect(!draft.save { _ in Issue.record("Unexpected write"); return true })
        draft.update("Planning", isEditing: false)
        #expect(draft.text == " \n ")
        #expect(draft.hasChanges)
    }

    @Test func testFailedSaveStaysDirtyEvenIfStoreAlreadyShowsTheEdit() {
        var draft = MeetingTitleDraft("Planning")
        draft.text = "My title"
        #expect(!draft.save { _ in false })
        draft.update("My title", isEditing: false)
        #expect(draft.hasChanges)
        var writes = 0
        #expect(!draft.save { _ in writes += 1; return false })
        #expect(writes == 1)
        #expect(draft.text == "My title")
    }

    @Test func testSuccessfulSaveNormalizesAndStopsRepeatWrites() {
        var draft = MeetingTitleDraft("Planning")
        draft.text = "  My title\n"
        var saved: [String] = []
        #expect(draft.save { saved.append($0); return true })
        #expect(draft.text == "My title")
        #expect(!draft.hasChanges)
        #expect(draft.save { saved.append($0); return true })
        #expect(saved == ["My title"])
        draft.update("Later change", isEditing: false)
        #expect(draft.text == "Later change")
    }

    @Test func testRevertingAfterFailedSaveStillWritesTheOriginalTitle() {
        var draft = MeetingTitleDraft("Planning")
        draft.text = "My title"
        #expect(!draft.save { _ in false })
        draft.update("My title", isEditing: false)
        draft.text = "Planning"
        #expect(draft.hasChanges)
        var saved: [String] = []
        #expect(draft.save { saved.append($0); return true })
        #expect(saved == ["Planning"])
        #expect(!draft.hasChanges)
    }

    @Test func testReturningToOriginalTitleCancelsTheEdit() {
        var draft = MeetingTitleDraft("Planning")
        draft.text = "Another title"
        draft.text = " Planning\n"
        #expect(!draft.hasChanges)
        draft.update("Renamed elsewhere", isEditing: false)
        #expect(draft.text == "Renamed elsewhere")
    }

    @Test func testDiscardRestoresOnlyOurPendingFailedTitle() {
        var draft = MeetingTitleDraft("Planning")
        draft.text = "My title"
        #expect(!draft.save { _ in false })
        draft.text = "A later unsaved edit"
        var restored: [String] = []
        draft.discard(currentTitle: "My title", hasPendingWrite: true) { restored.append($0) }
        #expect(restored == ["Planning"])
        #expect(draft.text == "Planning")
        #expect(!draft.hasChanges)
    }

    @Test func testDiscardLeavesRecoveredOrExternalTitlesAlone() {
        for (currentTitle, hasPendingWrite) in [("My title", false), ("Renamed elsewhere", true)] {
            var draft = MeetingTitleDraft("Planning")
            draft.text = "My title"
            #expect(!draft.save { _ in false })
            draft.discard(currentTitle: currentTitle, hasPendingWrite: hasPendingWrite) { _ in
                Issue.record("Unexpected overwrite")
            }
            #expect(draft.text == currentTitle)
            #expect(!draft.hasChanges)
        }
    }

    @Test func testDiscardOfUnwrittenEditDoesNotTouchOtherPendingMetadata() {
        var draft = MeetingTitleDraft("Planning")
        draft.text = "My title"
        draft.discard(currentTitle: "Planning", hasPendingWrite: true) { _ in
            Issue.record("Unexpected write")
        }
        #expect(draft.text == "Planning")
        #expect(!draft.hasChanges)
    }
}
