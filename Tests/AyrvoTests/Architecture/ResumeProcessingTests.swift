import Foundation
import Testing
@testable import Ayrvo

@MainActor
struct ResumeProcessingTests {
    @Test func testOldProcessingCannotRemoveTheNewLiveTranscript() async throws {
        let repository = MockMeetingRepository()
        defer { try? FileManager.default.removeItem(at: repository.archive.root) }
        var meeting = Meeting(title: "Resume", createdAt: .now)
        meeting.state = .processing
        try repository.archive.createFolder(for: meeting.id)
        repository.upsert(meeting)
        let gate = RecordingGate()
        defer { gate.open() }
        let notifications = MockNotificationService()
        let useCase = ProcessMeetingUseCase(
            meetingRepository: repository, processingService: PausedResumeProcessor(gate: gate),
            notificationService: notifications)
        var updates: [String] = []
        useCase.onSummaryUpdate = { _, _ in updates.append("old summary") }
        let oldRun = Task { await useCase.execute(meeting) }
        await gate.waitUntilPaused()
        repository.archive.beginRecording(for: meeting.id)
        meeting.state = .recording
        repository.upsert(meeting)
        let live = [TranscriptSegment(speakerID: "me", start: 121, end: 125, text: "New session")]
        repository.archive.saveLiveTranscript(live, for: meeting.id)
        gate.open()
        await oldRun.value
        await Task.yield()
        #expect(repository.archive.liveTranscript(for: meeting.id) == live)
        #expect(repository.meeting(id: meeting.id)?.state == .recording)
        #expect(notifications.readyMeetings.isEmpty)
        #expect(updates.isEmpty)
    }

    @Test func testLivePromotionPreservesAbsoluteTimesAndDoesNotDuplicateOnRetry() async throws {
        let repository = MockMeetingRepository()
        defer { try? FileManager.default.removeItem(at: repository.archive.root) }
        var meeting = Meeting(title: "Resume", createdAt: .now)
        meeting.duration = 135
        meeting.audioStartOffset = 120
        try repository.archive.createFolder(for: meeting.id)
        repository.upsert(meeting)
        let prior = TranscriptSegment(speakerID: "me", start: 0, end: 100, text: "Previous session")
        let live = TranscriptSegment(speakerID: "me", start: 121, end: 125, text: "New session")
        try repository.archive.saveTranscript([prior], for: meeting.id)
        repository.archive.saveLiveTranscript([live], for: meeting.id)
        let processor = MockProcessingService()
        processor.outcome = ProcessingOutcome(state: .failed)
        let useCase = ProcessMeetingUseCase(
            meetingRepository: repository, processingService: processor,
            notificationService: MockNotificationService())
        await useCase.execute(meeting)
        #expect(repository.transcript(for: meeting.id) == [prior, live])
        await useCase.execute(meeting)
        #expect(repository.transcript(for: meeting.id) == [prior, live])
        let offset = ProcessingPipeline.appendOffset(meeting: meeting, prior: [prior])
        #expect(offset == 120)
        let recognized = TranscriptSegment(speakerID: "me", start: 1, end: 5, text: "New session")
        let final = ProcessingPipeline.offsetSegments([recognized], by: offset)
        #expect(final.first?.start == live.start)
        #expect(final.first?.end == live.end)
    }

    @Test func testRecordingRejectsOldAndQueuedProcessingWrites() throws {
        let repository = MockMeetingRepository()
        defer { try? FileManager.default.removeItem(at: repository.archive.root) }
        let id = UUID()
        try repository.archive.createFolder(for: id)
        let archive = repository.archive
        let old = try #require(archive.beginProcessing(for: id))
        try archive.saveSummary("Previous notes", for: id, processingRun: old)
        archive.beginRecording(for: id)
        #expect(archive.beginProcessing(for: id) == nil)
        #expect(throws: (any Error).self) { try archive.saveSummary("Stale notes", for: id, processingRun: old) }
        #expect(throws: (any Error).self) { try archive.saveTranscript([], for: id, processingRun: old) }
        #expect(archive.summary(for: id) == "Previous notes")
        archive.endRecording(for: id)
        let current = try #require(archive.beginProcessing(for: id))
        archive.endProcessing(id, run: old)
        #expect(archive.isProcessing(id, run: current))
        #expect(!archive.isProcessing(id, run: old))
        try archive.saveSummary("Current notes", for: id, processingRun: current)
        #expect(archive.summary(for: id) == "Current notes")
    }
}

private final class PausedResumeProcessor: ProcessingService, Sendable {
    let gate: RecordingGate
    init(gate: RecordingGate) { self.gate = gate }

    func process(
        meeting: Meeting, archive: MeetingArchive, processingRun: UUID,
        onProgress: @escaping @Sendable (String) -> Void,
        onSummary: @escaping @Sendable (SummaryUpdate) -> Void
    ) async -> ProcessingOutcome {
        await gate.pause()
        onSummary(.streaming("Stale summary"))
        return ProcessingOutcome(state: .ready)
    }

    func summarize(meeting: Meeting, transcript: String, userNotes: String, forceProvider: AIProvider?,
                   onDelta: (@Sendable (String) -> Void)?) async -> SummaryOutcome { .failure("Unused") }
    func generateTitle(summary: String, provider: String) async -> String? { nil }
}
