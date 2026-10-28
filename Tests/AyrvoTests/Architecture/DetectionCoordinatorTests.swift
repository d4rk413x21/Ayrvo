import Foundation
import Testing
@testable import Ayrvo

@MainActor
struct DetectionCoordinatorTests {
    @Test func testManualStopPreventsAutoResumeUntilTheMicrophoneIsReleased() async {
        var settings = MockSettingsRepository()
        settings.autoRecord = true
        let detection = MockMeetingDetectionService()
        let coordinator = MeetingDetectionCoordinator(detectionService: detection, settings: settings)
        var recording = true
        var starts = 0
        coordinator.isRecording = { recording }
        coordinator.onAutoRecord = { _ in starts += 1 }
        coordinator.start()
        let event = ArchitectureFixtures.micEvent()
        detection.emit(event)
        try? await Task.sleep(for: .milliseconds(50))
        coordinator.recordingStoppedManually()
        recording = false
        detection.emit(event)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(starts == 0)
        let released = ArchitectureFixtures.micEvent(pid: event.pid, running: false)
        detection.emit(released)
        try? await Task.sleep(for: .milliseconds(50))
        detection.emit(event)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(starts == 1)
        coordinator.stop()
    }
    private func makeCoordinator(
        settings: MockSettingsRepository = MockSettingsRepository(),
        recording: MockRecordingService,
        detection: MockMeetingDetectionService = MockMeetingDetectionService()
    ) -> (MeetingDetectionCoordinator, MockMeetingDetectionService, MockSettingsRepository, StartRecordingUseCase, StopRecordingUseCase) {
        let meetings = MockMeetingRepository()
        let processing = MockProcessingService()
        let processUC = ProcessMeetingUseCase(
            meetingRepository: meetings,
            processingService: processing,
            notificationService: MockNotificationService())
        let start = StartRecordingUseCase(
            recordingService: recording,
            meetingRepository: meetings,
            folderRepository: MeetingFolderStore(archive: FolderArchive(root: meetings.archive.root)),
            calendarRepository: MockCalendarRepository(),
            settings: settings,
            templateOverrides: TemplateOverrideStore(root: meetings.archive.root),
            availableTemplateNames: { [] })
        let stop = StopRecordingUseCase(
            recordingService: recording,
            meetingRepository: meetings,
            processMeeting: processUC)
        let coordinator = MeetingDetectionCoordinator(
            detectionService: detection,
            settings: settings)
        coordinator.onAutoRecord = { name in
            _ = await start.execute(sourceApp: name, calendarEvent: nil)
        }
        coordinator.onAutoStop = {
            _ = await stop.execute()
        }
        return (coordinator, detection, settings, start, stop)
    }

    @Test func testAutoRecordStartsCapture() async {
        var settings = MockSettingsRepository()
        settings.autoRecord = true
        let recording = MockRecordingService()
        let handle = ArchitectureFixtures.recordingHandle(
            repository: MockMeetingRepository(), title: "Auto")
        recording.startResult = .success(handle)

        let (coordinator, detection, _, _, _) = makeCoordinator(
            settings: settings, recording: recording)
        coordinator.isRecording = { false }
        coordinator.isStartingRecording = { false }
        coordinator.start()

        detection.emit(ArchitectureFixtures.micEvent())
        try? await Task.sleep(for: .milliseconds(50))

        #expect(recording.startCallCount == 1)
    }

    @Test func testManualDetectionSurfacesAppName() async {
        var settings = MockSettingsRepository()
        settings.autoRecord = false
        let (coordinator, detection, _, _, _) = makeCoordinator(settings: settings, recording: MockRecordingService())
        var detected: String?
        coordinator.onDetectedAppNameChanged = { detected = $0 }
        coordinator.isRecording = { false }
        coordinator.isStartingRecording = { false }
        coordinator.start()

        detection.emit(ArchitectureFixtures.micEvent())
        try? await Task.sleep(for: .milliseconds(50))

        #expect(detected == "Zoom")
    }

    @Test func testDismissDetectionClearsPendingApp() async {
        let (coordinator, detection, _, _, _) = makeCoordinator(recording: MockRecordingService())
        var detected: String? = "pending"
        coordinator.onDetectedAppNameChanged = { detected = $0 }
        coordinator.isRecording = { false }
        coordinator.isStartingRecording = { false }
        coordinator.start()
        detection.emit(ArchitectureFixtures.micEvent())
        try? await Task.sleep(for: .milliseconds(50))

        coordinator.dismissDetection()

        #expect(detected == nil)
    }

    @Test func testAutoStopTriggersStopUseCase() async {
        var settings = MockSettingsRepository()
        settings.autoStopRecording = true
        let recording = MockRecordingService()
        let meetings = MockMeetingRepository()
        let handle = ArchitectureFixtures.recordingHandle(repository: meetings)
        recording.stopPair = (handle.session, handle.meeting)

        let processing = MockProcessingService()
        let processUC = ProcessMeetingUseCase(
            meetingRepository: meetings,
            processingService: processing,
            notificationService: MockNotificationService())
        let start = StartRecordingUseCase(
            recordingService: recording,
            meetingRepository: meetings,
            folderRepository: MeetingFolderStore(archive: FolderArchive(root: meetings.archive.root)),
            calendarRepository: MockCalendarRepository(),
            settings: settings,
            templateOverrides: TemplateOverrideStore(root: meetings.archive.root),
            availableTemplateNames: { [] })
        let stop = StopRecordingUseCase(
            recordingService: recording,
            meetingRepository: meetings,
            processMeeting: processUC)
        let detection = MockMeetingDetectionService()
        let coordinator = MeetingDetectionCoordinator(
            detectionService: detection,
            settings: settings)
        coordinator.onAutoRecord = { name in
            _ = await start.execute(sourceApp: name, calendarEvent: nil)
        }
        coordinator.onAutoStop = {
            _ = await stop.execute()
        }
        coordinator.isRecording = { recording.isRecording }
        coordinator.isStartingRecording = { false }
        coordinator.start()

        recording.adopt(handle)
        detection.emit(ArchitectureFixtures.micEvent(running: true))
        detection.emit(ArchitectureFixtures.micEvent(running: false))

        try? await Task.sleep(for: .seconds(9))

        #expect(recording.stopCallCount == 1)
        #expect(processing.processCallCount == 1)
    }

    @Test func testMicReconnectCancelsPendingAutoStop() async {
        var settings = MockSettingsRepository()
        settings.autoStopRecording = true
        let recording = MockRecordingService()
        let meetings = MockMeetingRepository()
        let handle = ArchitectureFixtures.recordingHandle(repository: meetings)
        recording.stopPair = (handle.session, handle.meeting)

        let processing = MockProcessingService()
        let processUC = ProcessMeetingUseCase(
            meetingRepository: meetings,
            processingService: processing,
            notificationService: MockNotificationService())
        let stop = StopRecordingUseCase(
            recordingService: recording,
            meetingRepository: meetings,
            processMeeting: processUC)
        let detection = MockMeetingDetectionService()
        let coordinator = MeetingDetectionCoordinator(
            detectionService: detection,
            settings: settings)
        coordinator.onAutoStop = {
            _ = await stop.execute()
        }
        coordinator.isRecording = { true }
        coordinator.isStartingRecording = { false }
        coordinator.start()

        detection.emit(ArchitectureFixtures.micEvent(running: false))
        detection.emit(ArchitectureFixtures.micEvent(running: true))
        try? await Task.sleep(for: .seconds(9))

        #expect(recording.stopCallCount == 0)
    }
}
