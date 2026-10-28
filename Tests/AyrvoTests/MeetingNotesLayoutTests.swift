import Testing
@testable import Ayrvo

struct MeetingNotesLayoutTests {
    @Test func testEditingKeepsTheDraftVisibleDuringRecordingAndProcessing() {
        let state = layout(recording: true, editing: true, notes: true, working: true)
        #expect(state.content == .editor)
        #expect(!state.centersContent)
    }

    @Test func testPreparationStillShowsTheWriteNotesPrompt() {
        let state = layout(prep: true, editing: true, notes: true)
        #expect(state.content == .preparation)
        #expect(!state.centersContent)
    }

    @Test func testAvailableNotesStayVisibleWhileAnImprovedSummaryIsProcessing() {
        let state = layout(recording: true, notes: true, working: true)
        #expect(state.content == .summary)
        #expect(!state.centersContent)
    }

    @Test func testPersonalNotesRemainReadableWhenTheirPanelIsHidden() {
        let state = layout(working: true, sideNotes: true)
        #expect(state.content == .sideNotes)
        #expect(!state.centersContent)
        let panelOpen = layout(working: true, sideNotes: true, panel: true)
        #expect(panelOpen.content == .working)
        #expect(panelOpen.centersContent)
    }

    @Test func testRecordingPlaceholderAndWorkingStateDoNotCenterTheDocument() {
        #expect(layout(recording: true).content == .recording)
        let working = layout(recording: true, working: true)
        #expect(working.content == .working)
        #expect(!working.centersContent)
    }

    @Test func testEmptyAndProcessingDocumentsAreCenteredWhenNotRecording() {
        #expect(layout().content == .empty)
        #expect(layout().centersContent)
        #expect(layout(working: true).content == .working)
        #expect(layout(working: true).centersContent)
    }

    @Test func testResumeRemainsAvailableWithoutAFooterButton() {
        #expect(MeetingNotesLayout.primaryAction(
            canContinueRecording: true, resumesInFooter: false, isFailed: true) == .resume)
        #expect(MeetingNotesLayout.primaryAction(
            canContinueRecording: true, resumesInFooter: false, isFailed: false) == .resume)
        #expect(MeetingNotesLayout.primaryAction(
            canContinueRecording: true, resumesInFooter: true, isFailed: false) == nil)
    }

    @Test func testRetryIsOfferedOnlyForFailedMeetingsThatCannotResume() {
        #expect(MeetingNotesLayout.primaryAction(
            canContinueRecording: false, resumesInFooter: false, isFailed: true) == .retry)
        #expect(MeetingNotesLayout.primaryAction(
            canContinueRecording: false, resumesInFooter: false, isFailed: false) == nil)
    }

    private func layout(recording: Bool = false, prep: Bool = false, editing: Bool = false,
                        notes: Bool = false, working: Bool = false, sideNotes: Bool = false,
                        panel: Bool = false) -> MeetingNotesLayout {
        MeetingNotesLayout(isRecording: recording, isPrep: prep, isEditing: editing,
                           hasDisplayedNotes: notes, isWorking: working,
                           hasSideNotes: sideNotes, showsSideNotes: panel)
    }
}
