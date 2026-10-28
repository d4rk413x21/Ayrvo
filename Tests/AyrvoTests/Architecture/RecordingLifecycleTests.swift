import Foundation
import Testing
@testable import Ayrvo

@MainActor
struct RecordingLifecycleTests {
    private func readyMeeting(in repository: MockMeetingRepository) throws -> Meeting {
        var meeting = Meeting(title: "Resume", createdAt: .now)
        meeting.state = .ready
        meeting.duration = 120
        try repository.archive.createFolder(for: meeting.id)
        repository.upsert(meeting)
        return meeting
    }

    @Test func testStopInvalidatesAResumeStillStartingCapture() async throws {
        let repository = MockMeetingRepository()
        defer { try? FileManager.default.removeItem(at: repository.archive.root) }
        let meeting = try readyMeeting(in: repository)
        let audio = repository.archive.micURL(for: meeting.id)
        try Data("previous audio".utf8).write(to: audio)
        let gate = RecordingGate()
        defer { gate.open() }
        var stoppedCaptures = 0
        let service = RecordingServiceImpl(
            prepareMicrophone: {},
            startCapture: { _, mic, _, _ in
                try Data("new audio".utf8).write(to: mic)
                await gate.pause()
            },
            stopCapture: { _ in stoppedCaptures += 1 })
        let resume = Task { await service.continueRecording(meetingID: meeting.id, meetingRepository: repository) }
        await gate.waitUntilPaused()
        let stopped = await service.stop()
        #expect(stopped == nil)
        #expect(service.isStartingRecording)
        gate.open()
        let result = await resume.value
        guard case .failure(.cancelled) = result else {
            Issue.record("A completed startup must not resurrect a recording after Stop")
            return
        }
        #expect(stoppedCaptures == 1)
        #expect(!service.isRecording)
        #expect(!service.isStartingRecording)
        #expect(service.currentSession == nil)
        #expect(repository.meeting(id: meeting.id)?.state == .ready)
        #expect(try String(contentsOf: audio, encoding: .utf8) == "previous audio")
    }

    @Test func testStopAlsoCancelsAPendingPermissionPreparation() async throws {
        let repository = MockMeetingRepository()
        defer { try? FileManager.default.removeItem(at: repository.archive.root) }
        let meeting = try readyMeeting(in: repository)
        let gate = RecordingGate()
        defer { gate.open() }
        var starts = 0
        let service = RecordingServiceImpl(
            prepareMicrophone: { await gate.pause() },
            startCapture: { _, _, _, _ in starts += 1 }, stopCapture: { _ in })
        let resume = Task { await service.continueRecording(meetingID: meeting.id, meetingRepository: repository) }
        await gate.waitUntilPaused()
        _ = await service.stop()
        gate.open()
        let result = await resume.value
        guard case .failure(.cancelled) = result else { Issue.record("Expected cancellation"); return }
        #expect(starts == 0)
        #expect(repository.meeting(id: meeting.id)?.state == .ready)
    }

    @Test func testNewResumeIsRejectedUntilCaptureHasFinishedStopping() async throws {
        let repository = MockMeetingRepository()
        defer { try? FileManager.default.removeItem(at: repository.archive.root) }
        let meeting = try readyMeeting(in: repository)
        let gate = RecordingGate()
        defer { gate.open() }
        var starts = 0
        let service = RecordingServiceImpl(
            prepareMicrophone: {}, startCapture: { _, _, _, _ in starts += 1 },
            stopCapture: { _ in await gate.pause() })
        let result = await service.continueRecording(meetingID: meeting.id, meetingRepository: repository)
        guard case .success = result else { Issue.record("Expected resume"); return }
        let stop = Task { await service.stop() }
        await gate.waitUntilPaused()
        #expect(!service.isRecording)
        #expect(service.isStartingRecording)
        let overlapping = await service.continueRecording(meetingID: meeting.id, meetingRepository: repository)
        guard case .failure(.alreadyRecording) = overlapping else {
            gate.open()
            Issue.record("A second capture must not start while the first is closing")
            return
        }
        #expect(starts == 1)
        gate.open()
        _ = await stop.value
        #expect(!service.isStartingRecording)
    }

    @Test func testOldHandleCannotReactivateAStoppedOrReplacedSession() async throws {
        let repository = MockMeetingRepository()
        defer { try? FileManager.default.removeItem(at: repository.archive.root) }
        var meeting = try readyMeeting(in: repository)
        let service = RecordingServiceImpl(prepareMicrophone: {}, startCapture: { _, _, _, _ in }, stopCapture: { _ in })
        let first = await service.continueRecording(meetingID: meeting.id, meetingRepository: repository)
        guard case .success(let oldHandle) = first else { Issue.record("Expected resume"); return }
        #expect(oldHandle.isCurrent(in: service))
        #expect(oldHandle.session.elapsed == 120)
        _ = await service.stop()
        #expect(!oldHandle.isCurrent(in: service))
        meeting.state = .ready
        repository.upsert(meeting)
        let second = await service.continueRecording(meetingID: meeting.id, meetingRepository: repository)
        guard case .success(let currentHandle) = second else { Issue.record("Expected second resume"); return }
        #expect(!oldHandle.isCurrent(in: service))
        #expect(currentHandle.isCurrent(in: service))
        _ = await service.stop()
    }
}

@MainActor
final class RecordingGate {
    private let entered = AsyncStream<Void>.makeStream()
    private var waiter: CheckedContinuation<Void, Never>?

    func pause() async {
        await withCheckedContinuation { continuation in
            waiter = continuation
            entered.continuation.yield(())
        }
    }

    func waitUntilPaused() async {
        for await _ in entered.stream { return }
    }

    func open() {
        waiter?.resume()
        waiter = nil
    }
}
