import AVFoundation
import AppKit
import Foundation
import UserNotifications
import os

@MainActor
final class RecordingServiceImpl: RecordingService {
  private(set) var currentSession: RecordingSession?
  private(set) var recordingMeeting: Meeting?
  private var _isStartingRecording = false
  private var isStoppingRecording = false
  private let log = Logger(subsystem: AppIdentity.bundleIdentifier, category: "recording")
  /// Per-meeting transcription locale overrides. Injected by the dependency
  /// container; nil in tests means "auto" for every meeting.
  var localeStore: TranscriptionLocaleStore?

  private var recordingArchive: MeetingArchive?
  private var startRequestID: UUID?
  private let prepareMicrophone: @MainActor () async -> Void
  private let startCapture: @MainActor (RecordingSession, URL, URL, TranscriptionLocaleStore?) async throws -> Void
  private let stopCapture: @MainActor (RecordingSession) async -> Void

  init(
    prepareMicrophone: (@MainActor () async -> Void)? = nil,
    startCapture: @escaping @MainActor (RecordingSession, URL, URL, TranscriptionLocaleStore?) async throws -> Void = {
      try await $0.startAsync(micURL: $1, systemURL: $2, localeStore: $3)
    },
    stopCapture: @escaping @MainActor (RecordingSession) async -> Void = { await $0.stopAsync() }
  ) {
    self.prepareMicrophone = prepareMicrophone ?? Self.prepareMicrophoneForCapture
    self.startCapture = startCapture
    self.stopCapture = stopCapture
  }

  private func claimStart() -> UUID? {
    guard !isRecording, !isStartingRecording else { return nil }
    let id = UUID()
    startRequestID = id
    _isStartingRecording = true
    return id
  }

  private func releaseStart(_ id: UUID) {
    if startRequestID == id { startRequestID = nil }
    _isStartingRecording = false
  }

  var isRecording: Bool { currentSession != nil }
  var isStartingRecording: Bool { _isStartingRecording || isStoppingRecording }

  func startRecording(
    sourceApp: String?,
    calendarEvent: CalendarEventSummary?,
    meetingRepository: MeetingRepository,
    folderRepository: FolderRepository,
    calendarRepository: CalendarRepository,
    settings: SettingsRepository,
    templateOverrides: TemplateOverrideRepository?,
    availableTemplateNames: @escaping () -> [String]
  ) async -> Result<RecordingSessionHandle, RecordingError> {
    guard !isRecording, !isStartingRecording else { return .failure(.alreadyRecording) }
    AyrvoConsoleLog.recording(
      "start requested source=\(sourceApp ?? "manual") calendar=\(calendarEvent?.title ?? "none")")

    guard let requestID = claimStart() else { return .failure(.alreadyRecording) }
    defer { releaseStart(requestID) }
    await prepareMicrophone()
    guard startRequestID == requestID else { return .failure(.cancelled) }

    let resolvedCalendarEvent = await resolveCalendarEvent(
      calendarEvent: calendarEvent,
      sourceApp: sourceApp,
      calendarRepository: calendarRepository,
      meetingRepository: meetingRepository,
      settings: settings)

    guard startRequestID == requestID else { return .failure(.cancelled) }

    if let event = resolvedCalendarEvent,
      let existing = calendarRepository.meetingForCalendarEvent(
        event, in: meetingRepository.meetings),
      existing.canResumeRecording(isRecording: false)
    {
      AyrvoConsoleLog.recording("resuming existing meeting for calendar event \"\(event.title)\"")
      // A crash-orphan may have been created before the source was known
      // (sourceApp == nil), which stops the Zoom speaker tracker from
      // starting on resume — so the live UI gets no named speakers and
      // the final transcript has no roster. Update it to the source we
      // just detected (e.g. Zoom) so the tracker starts on the resumed call.
      if let sourceApp, existing.sourceApp == nil {
        var updated = existing
        updated.sourceApp = sourceApp
        meetingRepository.upsert(updated)
        AyrvoConsoleLog.recording(
          "resume: set source=\(sourceApp) on orphan \(existing.id.uuidString.prefix(8))")
      }
      return await resumeMeeting(meetingID: existing.id, meetingRepository: meetingRepository, requestID: requestID)
    }

    var meeting = Meeting(title: Meeting.placeholderTitle(for: Date()), createdAt: Date())
    meeting.sourceApp = sourceApp
    meeting.templateName = settings.defaultTemplate

    if let resolvedCalendarEvent {
      applyCalendarEvent(resolvedCalendarEvent, to: &meeting)
      AyrvoConsoleLog.recording(
        "matched calendar \"\(resolvedCalendarEvent.title)\" (\(resolvedCalendarEvent.attendees.count) attendees)"
      )
    }

    // Smart templates: once the calendar event (title + attendees) is applied,
    // override the default template with the one the resolver picks for this
    // meeting type. Transcript keywords aren't available yet at start time.
    if settings.smartTemplatesEnabled {
      let type = MeetingTemplateResolver.resolve(for: meeting)
      meeting.templateName = MeetingTemplateResolver.templateName(for: type)
      AyrvoConsoleLog.intelligence(
        "smart template → \(type.rawValue) (\"\(meeting.templateName ?? "")\")")
    }
    // Per-event assignment wins over both default and smart — same precedence
    // as PrepareMeetingUseCase, so manual and auto-detected starts agree.
    if let event = resolvedCalendarEvent,
      let override = templateOverrides?.templateName(
        forEventID: event.id, available: availableTemplateNames())
    {
      meeting.templateName = override
      AyrvoConsoleLog.intelligence("per-event template → \"\(override)\" for \"\(event.title)\"")
    }

    if let title = meeting.calendarEventTitle,
      let folder = folderRepository.folder(forTitle: title)
    {
      meeting.folderID = folder.id
      AyrvoConsoleLog.recording("auto-folder \"\(folder.name)\"")
    }

    guard !isRecording else { return .failure(.alreadyRecording) }

    return await startSession(for: meeting, meetingRepository: meetingRepository, requestID: requestID)
  }

  func continueRecording(
    meetingID: UUID,
    meetingRepository: MeetingRepository
  ) async -> Result<RecordingSessionHandle, RecordingError> {
    guard let requestID = claimStart() else { return .failure(.alreadyRecording) }
    defer { releaseStart(requestID) }
    guard let existing = meetingRepository.meeting(id: meetingID) else { return .failure(.meetingNotFound) }
    guard existing.canResumeRecording(isRecording: false) else { return .failure(.cannotContinue) }
    await prepareMicrophone()
    guard startRequestID == requestID else { return .failure(.cancelled) }
    return await resumeMeeting(meetingID: meetingID, meetingRepository: meetingRepository, requestID: requestID)
  }

  private func resumeMeeting(
    meetingID: UUID, meetingRepository: MeetingRepository, requestID: UUID
  ) async -> Result<RecordingSessionHandle, RecordingError> {
    guard var meeting = meetingRepository.meeting(id: meetingID) else {
      AyrvoConsoleLog.recording("continue failed — meeting not found")
      return .failure(.meetingNotFound)
    }
    let fromPrep = meeting.canStartFromPrep(isRecording: false)
    guard fromPrep || meeting.canContinueRecording(isRecording: false) else {
      AyrvoConsoleLog.recording(
        "continue failed — meeting \(meetingID.uuidString.prefix(8)) not resumable")
      return .failure(.cannotContinue)
    }
    AyrvoConsoleLog.recording(
      "continue \(meetingID.uuidString.prefix(8)) fromPrep=\(fromPrep) duration=\(Int(meeting.duration))s"
    )

    let original = meeting
    let archive = meetingRepository.archive
    archive.beginRecording(for: meetingID)
    var savedFiles: RecordingResumeFiles
    do {
      savedFiles = try RecordingResumeFiles(archive: archive, meetingID: meetingID)
    } catch {
      archive.endRecording(for: meetingID)
      restoreResumeMetadata(original, repository: meetingRepository)
      return .failure(.sessionStartFailed(error.localizedDescription))
    }
    let offset = fromPrep ? 0 : max(0, meeting.duration, meetingRepository.transcript(for: meetingID).map(\.end).max() ?? 0)
    meeting.audioStartOffset = offset
    meeting.state = .recording
    meeting.notice = nil
    meetingRepository.upsert(meeting)

    let newSession = RecordingSession(
      meetingID: meeting.id,
      archive: archive,
      elapsedOffset: offset,
      sourceApp: meeting.sourceApp)
    do {
      try await startCapture(
        newSession, archive.micURL(for: meeting.id), archive.systemURL(for: meeting.id), localeStore)
    } catch {
      await stopCapture(newSession)
      restoreResume(original, files: &savedFiles, repository: meetingRepository)
      archive.endRecording(for: meetingID)
      return .failure(.sessionStartFailed(error.localizedDescription))
    }
    guard startRequestID == requestID, var fresh = meetingRepository.meeting(id: meetingID) else {
      await stopCapture(newSession)
      restoreResume(original, files: &savedFiles, repository: meetingRepository)
      archive.endRecording(for: meetingID)
      return .failure(.cancelled)
    }
    do { try savedFiles.commit() } catch { PersistenceStatus.shared.report(error) }
    fresh.state = .recording
    fresh.notice = newSession.startupNotice
    fresh.audioStartOffset = offset
    meetingRepository.upsert(fresh)
    recordingArchive = archive
    currentSession = newSession
    recordingMeeting = fresh
    AyrvoConsoleLog.recording("continue started \(meetingID.uuidString.prefix(8))")
    return .success(RecordingSessionHandle(session: newSession, meeting: fresh))
  }

  private func restoreResume(_ original: Meeting, files: inout RecordingResumeFiles, repository: MeetingRepository) {
    do { try files.rollback() } catch { PersistenceStatus.shared.report(error) }
    restoreResumeMetadata(original, repository: repository)
  }

  private func restoreResumeMetadata(_ original: Meeting, repository: MeetingRepository) {
    guard var fresh = repository.meeting(id: original.id) else { return }
    fresh.state = original.state == .processing ? .failed : original.state
    fresh.notice = original.notice
    fresh.audioStartOffset = original.audioStartOffset
    repository.upsert(fresh)
  }

  func stop() async -> (session: RecordingSession, meeting: Meeting)? {
    startRequestID = nil
    guard let session = currentSession, let meeting = recordingMeeting else { return nil }
    AyrvoConsoleLog.recording(
      "stop \(meeting.id.uuidString.prefix(8)) elapsed=\(Int(session.elapsed))s")
    isStoppingRecording = true
    defer { isStoppingRecording = false }
    // Keep new starts blocked until capture and its live transcript are closed.
    let archive = recordingArchive
    clear()
    // AAC metadata/headers are only reliable after AVAudioFile is closed.
    // Unlike stop(), stopAsync() waits for both recorders and live.json.
    await stopCapture(session)
    archive?.endRecording(for: meeting.id)
    AyrvoConsoleLog.recording(
      "capture finalized before processing \(meeting.id.uuidString.prefix(8))")
    return (session, meeting)
  }

  func discard() -> (session: RecordingSession, meeting: Meeting)? {
    startRequestID = nil
    guard let session = currentSession, let meeting = recordingMeeting else { return nil }
    AyrvoConsoleLog.recording("discard \(meeting.id.uuidString.prefix(8))")
    let archive = recordingArchive
    clear()
    isStoppingRecording = true
    Task {
      await stopCapture(session)
      archive?.endRecording(for: meeting.id)
      isStoppingRecording = false
    }
    return (session, meeting)
  }

  func prepareForTermination(meetingRepository: MeetingRepository) async {
    startRequestID = nil
    guard let session = currentSession, let meeting = recordingMeeting else { return }
    let archive = recordingArchive
    isStoppingRecording = true
    defer { isStoppingRecording = false }
    clear()
    AyrvoConsoleLog.recording("app terminating — finalizing \(meeting.id.uuidString.prefix(8))")
    await stopCapture(session)
    archive?.endRecording(for: meeting.id)
    var fresh = meetingRepository.meeting(id: meeting.id) ?? meeting
    fresh.duration = session.elapsed
    if let notice = session.stopNotice {
      fresh.notice = [fresh.notice, notice].compactMap { $0 }.joined(separator: " ")
    }
    fresh.state = .processing
    meetingRepository.upsert(fresh)
  }

  private func startSession(
    for meeting: Meeting,
    meetingRepository: MeetingRepository,
    requestID: UUID
  ) async -> Result<RecordingSessionHandle, RecordingError> {
    let archive = meetingRepository.archive
    do {
      try archive.createFolder(for: meeting.id)
    } catch {
      AyrvoConsoleLog.recording("archive folder creation failed — \(error.localizedDescription)")
      return .failure(.archiveCreationFailed(error.localizedDescription))
    }

    archive.beginRecording(for: meeting.id)
    let newSession = RecordingSession(
      meetingID: meeting.id,
      archive: archive,
      sourceApp: meeting.sourceApp)
    do {
      try await startCapture(
        newSession, archive.micURL(for: meeting.id), archive.systemURL(for: meeting.id), localeStore)
    } catch {
      await stopCapture(newSession)
      archive.endRecording(for: meeting.id)
      try? FileManager.default.removeItem(at: archive.folder(for: meeting.id))
      AyrvoConsoleLog.recording("session start failed — \(error.localizedDescription)")
      return .failure(.sessionStartFailed(error.localizedDescription))
    }
    guard startRequestID == requestID else {
      await stopCapture(newSession)
      archive.endRecording(for: meeting.id)
      try? archive.delete(id: meeting.id)
      return .failure(.cancelled)
    }
    var saved = meeting
    saved.state = .recording
    saved.audioStartOffset = 0
    saved.notice = newSession.startupNotice
    meetingRepository.upsert(saved)
    recordingArchive = archive
    currentSession = newSession
    recordingMeeting = saved
    AyrvoConsoleLog.recording(
      "started \(meeting.id.uuidString.prefix(8)) title=\"\(meeting.title)\" notice=\(newSession.startupNotice ?? "none")"
    )
    return .success(RecordingSessionHandle(session: newSession, meeting: saved))
  }

  private static func prepareMicrophoneForCapture() async {
    if !MicRecorder.permissionGranted {
      let granted = await MicRecorder.requestPermission()
      AyrvoConsoleLog.recording(
        "mic permission requested granted=\(granted) status=\(MicRecorder.permissionGranted)")
      if !granted {
        // The TCC prompt was denied or didn't appear (common with ad-hoc
        // signed apps after a rebuild — macOS silently denies). Open
        // System Settings so the user can toggle it manually.
        AyrvoConsoleLog.recording("mic permission DENIED — opening System Settings → Microphone")
        await MainActor.run {
          if let url = URL(
            string:
              "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone"
          ) {
            NSWorkspace.shared.open(url)
          }
        }
      }
    }
    AyrvoConsoleLog.recording(
      "permissions mic=\(MicRecorder.permissionGranted) system=\(SystemAudioPermission.statusLabel)"
    )

  }

  private func clear() {
    recordingArchive = nil
    currentSession = nil
    recordingMeeting = nil
  }

  private func resolveCalendarEvent(
    calendarEvent: CalendarEventSummary?,
    sourceApp: String?,
    calendarRepository: CalendarRepository,
    meetingRepository: MeetingRepository,
    settings: SettingsRepository
  ) async -> CalendarEventSummary? {
    if let calendarEvent { return calendarEvent }
    guard settings.useCalendar, CalendarAuthorization.isAuthorized else { return nil }
    if let current = await calendarRepository.currentEvent(at: .now, sourceApp: sourceApp) {
      return current
    }
    // Fallback: detection fired slightly before the calendar event's start
    // (the user joined the call early, or the event starts in a few minutes).
    // `currentEvent` only looks 10 min forward; a prep meeting created from
    // the Coming Up view still has the event's real start, so reuse it and
    // avoid creating a duplicate recording entry with no calendar link.
    let now = Date()
    let archive = ArchivedEventStore()
    let candidates = meetingRepository.meetings.filter { meeting in
      guard meeting.state == .prep,
            meeting.calendarEventID != nil,
            let start = meeting.calendarEventStart
      else { return false }
      // Skip prep meetings whose calendar event was archived after they were
      // prepared — archived events must never become recordings.
      if let eid = meeting.calendarEventID,
         archive.isArchived(title: meeting.calendarEventTitle ?? meeting.title, eventID: eid) {
        return false
      }
      return abs(start.timeIntervalSince(now)) <= 15 * 60
    }
    if let prep = candidates.first,
       let id = prep.calendarEventID,
       let start = prep.calendarEventStart,
       let end = prep.calendarEventEnd {
      return CalendarEventSummary(
        id: id,
        title: prep.calendarEventTitle ?? prep.title,
        start: start,
        end: end,
        location: nil,
        attendees: prep.attendees,
        conferenceURL: nil,
        calendarID: nil,
        calendarTitle: nil,
        calendarColor: .gray)
    }
    return nil
  }

  private func applyCalendarEvent(_ event: CalendarEventSummary, to meeting: inout Meeting) {
    meeting.title = event.title
    meeting.calendarEventTitle = event.title
    meeting.attendees = event.attendees
    meeting.calendarEventID = event.id
    meeting.calendarEventStart = event.start
    meeting.calendarEventEnd = event.end
  }
}
