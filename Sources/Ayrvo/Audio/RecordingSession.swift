import AppKit
import Foundation
import SwiftUI

/// Owns the two capture paths for one meeting. Either side may fail to start
/// (missing permission, no tap grant) — a session is viable with at least one.
@MainActor
final class RecordingSession: ObservableObject {
  /// Number of bars in the live mic level meter. Drives `micBarLevels` init.
  private static let levelBarCount = 12

  let meetingID: UUID
  let startedAt = Date()
  /// Elapsed time already on the meeting before this session (continue recording).
  private let elapsedOffset: TimeInterval
  private let sourceApp: String?

  @Published private(set) var elapsed: TimeInterval = 0
  /// Coarse elapsed time for the menu-bar status item, refreshed every 30s
  /// to avoid constant redraws of the system status bar. Driven by
  /// `menuBarTicker`; the in-menu RecordingCard uses the 1s `elapsed` for a
  /// smooth clock. Snaps to `elapsed` immediately on start/stop.
  @Published private(set) var menuBarElapsed: TimeInterval = 0
  @Published private(set) var micBarLevels: [Float] = Array(repeating: 0, count: levelBarCount)
  /// Rolling live transcript (finalized segments) + the current in-progress
  /// fragment, updated in real time while recording. A convenience surface — the
  /// accurate, diarized transcript is still produced post-hoc by the batch pipeline.
  @Published private(set) var liveSegments: [TranscriptSegment] = []
  @Published private(set) var volatileText: String = ""
  /// Display name of whoever Zoom marks as the active remote speaker, when known.
  @Published private(set) var activeRemoteSpeaker: String?
  @Published private(set) var speakerTrackingNotice: String?
  /// Zoom participant names captured at recording start, for the live UI.
  @Published private(set) var liveRoster: [String] = []
  /// Set when the mic engine failed to restart after an audio route change
  /// (e.g. AirPods connecting mid-recording), so the UI can warn that the mic
  /// side of the recording has gone silent. Cleared on the next successful restart.
  @Published private(set) var micRestartError: String?
  /// Set by `stop()` when neither side of the recording captured any audio
  /// (both mic and system file are zero bytes), so the UI can warn the user
  /// their microphone and system audio settings need checking.
  @Published private(set) var stopNotice: String?
  /// Bookmarks dropped during recording via the ⌃⌥B hotkey or the
  /// "Hey Ayrvo, mark this" voice trigger. Mirrored from the shared
  /// `TranscriptMarkerStore` so the live UI badges turns in real time.
  @Published private(set) var markers: [TranscriptMarker] = []
  private(set) var micStarted = false
  private(set) var systemStarted = false
  /// True when the local participant is muted in Zoom — the mic buffer sink is
  /// disconnected so no silent buffers reach the live transcriber or the .m4a file.
  private var micPaused = false

  private let mic = MicRecorder()
  private let tap = SystemAudioTap()
  private let archive: MeetingArchive
  private var liveTranscriber: LiveTranscriber?
  /// Per-meeting transcription locale. When non-nil, both live channels pin to
  /// this locale for the whole call; nil means "auto" (code-switching). Set via
  /// `transcriptionLocale(forMeeting:)` from `TranscriptionLocaleStore` at start.
  private var transcriptionLocale: Locale?
  private var platformSpeakerTracker: PlatformSpeakerTracker?
  /// Cached result of `speakerTrackingTargetAsync()`, set during
  /// `startPostCaptureSetup` so `startupNotice` can answer without a
  /// synchronous AX scan on MainActor. Nil until the async scan lands.
  private var platformTrackingWanted: Bool?
  private var speakerTrackingTarget: SpeakerTrackingTarget?
  private var stopped = false
  private var activeObserver: NSObjectProtocol?
  private var rosterTimer: Timer?
  private var systemAudioMonitor: SystemAudioMonitor?
  private var lastLivePersist = Date.distantPast
  private var ticker: Timer?
  /// 30s coarse timer driving `menuBarElapsed` for the status-bar item.
  private var menuBarTicker: Timer?

  enum SessionError: LocalizedError {
    case nothingStarted(String)
    var errorDescription: String? {
      if case .nothingStarted(let detail) = self {
        return "Could not start recording: \(detail)"
      }
      return nil
    }
  }

  init(
    meetingID: UUID,
    archive: MeetingArchive,
    elapsedOffset: TimeInterval = 0,
    sourceApp: String? = nil
  ) {
    self.meetingID = meetingID
    self.archive = archive
    self.elapsedOffset = elapsedOffset
    self.sourceApp = sourceApp
    self.elapsed = elapsedOffset
    self.menuBarElapsed = elapsedOffset
  }

  /// Pin the transcription locale for this meeting. Persists via `store` so the
  /// choice survives a resume/restart, and applies to the live transcriber
  /// immediately if it's already running (the running channels keep their
  /// current locale until `stop()`/restart; the next `start()` honors the pin).
  func setTranscriptionLocale(_ locale: Locale?, store: TranscriptionLocaleStore) {
    let id = locale.map { $0.identifier(.bcp47) }
    store.set(meetingID: meetingID.uuidString, localeIdentifier: id)
    transcriptionLocale = locale
    liveTranscriber?.localeOverride = locale
    AyrvoConsoleLog.locales(
      "transcription locale \(locale.map { $0.identifier(.bcp47) } ?? "auto") for \(meetingID.uuidString.prefix(8))"
    )
  }

  /// Drop a bookmark at the current recording timestamp. Called by the
  /// ⌃⌥B hotkey (or the "Hey Ayrvo, mark this" voice trigger) while
  /// recording. The label is stored on the marker and the marker is
  /// mirrored to the shared `TranscriptMarkerStore` so the transcript reader
  /// badges the nearest turn.
  func addMarker(label: String = "Bookmark") {
    TranscriptMarkerStore.shared.add(
      meetingID: meetingID,
      timestamp: elapsed,
      label: label)
    markers = TranscriptMarkerStore.shared.markers(for: meetingID)
    AyrvoConsoleLog.recording(
      "marker added at \(Int(elapsed))s label=\"\(label)\" meeting=\(meetingID.uuidString.prefix(8))"
    )
  }

  func start(micURL: URL, systemURL: URL, localeStore: TranscriptionLocaleStore? = nil) throws {
    try startSync(micURL: micURL, systemURL: systemURL, localeStore: localeStore)
  }

  /// Async variant that runs the blocking CoreAudio device setup on a background
  /// task instead of the main thread. The main thread can deadlock in
  /// `AudioObjectGetPropertyDataSize` (the HAL mutex) when CoreAudio IO contexts
  /// are active on other threads — this is the exact hang the file logger was
  /// added to diagnose. Prefer this from `@MainActor async` callers.
  func startAsync(micURL: URL, systemURL: URL, localeStore: TranscriptionLocaleStore? = nil) async throws {
    AudioDeviceRouting.logAudioDeviceSnapshot(context: "session start")
    AyrvoConsoleLog.recording(
      "start meeting=\(meetingID.uuidString.prefix(8)) offset=\(Int(elapsedOffset))s source=\(sourceApp ?? "manual") accessibility=\(AccessibilityPermission.isTrusted)"
    )
    if let localeStore, transcriptionLocale == nil {
      transcriptionLocale = localeStore.locale(forMeetingID: meetingID.uuidString)
    }

    // Live transcription runs alongside capture. Set the buffer sinks BEFORE
    // starting the recorders so no early audio is missed; it's best-effort —
    // any failure here never affects the recording itself.
    let live = LiveTranscriber(startDate: startedAt, timeOffset: elapsedOffset)
    live.headphoneBleedMode = AudioDeviceRouting.headphoneBleedLikely
    live.localeOverride = transcriptionLocale
    if live.headphoneBleedMode {
      AyrvoConsoleLog.recording("headphone bleed mode — mic bleed will attribute to Others")
    }
    live.onUpdate = { [weak self] segments, volatile in
      Task { @MainActor in self?.applyLive(segments, volatile) }
    }
    liveTranscriber = live

    // Set the local speaker's display name immediately from the macOS account
    // holder. When the Zoom roster arrives, it's refined to the Zoom display name.
    let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
    if !full.isEmpty {
      LiveTranscriber.localSpeakerName = full
    }

    mic.levelHandler = { [weak self] levels in
      Task { @MainActor in self?.micBarLevels = levels }
    }
    mic.bufferSink = { [weak live] buffer in live?.feedMic(buffer) }
    mic.onRestartFailure = { [weak self] error in
      // The mic engine failed to restart after an audio route change —
      // surface it so the UI can warn that the mic side went silent.
      Task { @MainActor in self?.micRestartError = error.localizedDescription }
    }
    tap.signalDetectedHandler = {
      AppSettings.markSystemAudioConfirmed()
      AyrvoConsoleLog.recording("system audio confirmed — non-silent signal received")
    }
    tap.bufferSink = { [weak live] buffer in live?.feedSystem(buffer) }
    // Run the blocking CoreAudio device setup (tap.start + mic.start) on a
    // background task so the HAL mutex can't deadlock the main thread. The
    // recorders are internally synchronized (MicRecorder.lock /
    // SystemAudioTap.controlQueue) so running off-MainActor is safe; they only
    // call back into MainActor via the closures set above.
    let micRecorder = mic
    let systemTap = tap
    let resolvedSourceApp = sourceApp
    let result: (didMic: Bool, didSystem: Bool, problems: [String]) = await Task.detached(priority: .userInitiated) {
      // Start the system audio tap FIRST. It creates a Core Audio aggregate
      // device (AudioHardwareCreateAggregateDevice) which can disrupt an
      // already-running AVAudioEngine's input node — the engine's input route
      // becomes stale and no buffers arrive. Starting the tap first means the
      // aggregate device exists before the mic engine starts, so the engine
      // binds to the correct input device.
      var problems: [String] = []
      var didMic = false
      var didSystem = false
      do {
        try systemTap.start(writingTo: systemURL)
        didSystem = true
      } catch {
        let ns = error as NSError
        AyrvoConsoleLog.recording(
          "system tap start failed domain=\(ns.domain) code=\(ns.code) — \(error.localizedDescription)"
        )
        problems.append("system audio: \(error.localizedDescription)")
      }
      do {
        try micRecorder.start(writingTo: micURL, sourceApp: resolvedSourceApp)
        didMic = true
      } catch {
        let ns = error as NSError
        AyrvoConsoleLog.recording(
          "mic start failed domain=\(ns.domain) code=\(ns.code) — \(error.localizedDescription)")
        problems.append("microphone: \(error.localizedDescription)")
      }
      return (didMic, didSystem, problems)
    }.value
    micStarted = result.didMic
    systemStarted = result.didSystem
    if systemStarted {
      live.systemPeakProvider = { [weak tap] in tap?.recentSystemPeak ?? 0 }
    }
    guard micStarted || systemStarted else {
      AyrvoConsoleLog.recording("failed to start — \(result.problems.joined(separator: "; "))")
      throw SessionError.nothingStarted(result.problems.joined(separator: "; "))
    }
    AyrvoConsoleLog.recording("capture mic=\(micStarted) system=\(systemStarted) live=starting")

    startPostCaptureSetup(live: live)
  }

  /// Synchronous start — used by tests and any non-async caller. Runs the
  /// blocking CoreAudio setup on the calling thread; do NOT call from the main
  /// thread in production (use `startAsync` instead to avoid the HAL deadlock).
  private func startSync(micURL: URL, systemURL: URL, localeStore: TranscriptionLocaleStore?) throws {
    AudioDeviceRouting.logAudioDeviceSnapshot(context: "session start")
    AyrvoConsoleLog.recording(
      "start meeting=\(meetingID.uuidString.prefix(8)) offset=\(Int(elapsedOffset))s source=\(sourceApp ?? "manual") accessibility=\(AccessibilityPermission.isTrusted)"
    )
    if let localeStore, transcriptionLocale == nil {
      transcriptionLocale = localeStore.locale(forMeetingID: meetingID.uuidString)
    }
    var problems: [String] = []

    // Live transcription runs alongside capture. Set the buffer sinks BEFORE
    // starting the recorders so no early audio is missed; it's best-effort —
    // any failure here never affects the recording itself.
    let live = LiveTranscriber(startDate: startedAt, timeOffset: elapsedOffset)
    live.headphoneBleedMode = AudioDeviceRouting.headphoneBleedLikely
    live.localeOverride = transcriptionLocale
    if live.headphoneBleedMode {
      AyrvoConsoleLog.recording("headphone bleed mode — mic bleed will attribute to Others")
    }
    live.onUpdate = { [weak self] segments, volatile in
      Task { @MainActor in self?.applyLive(segments, volatile) }
    }
    liveTranscriber = live

    // Set the local speaker's display name immediately from the macOS account
    // holder. When the Zoom roster arrives, it's refined to the Zoom display name.
    let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
    if !full.isEmpty {
      LiveTranscriber.localSpeakerName = full
    }

    mic.levelHandler = { [weak self] levels in
      Task { @MainActor in self?.micBarLevels = levels }
    }
    mic.bufferSink = { [weak live] buffer in live?.feedMic(buffer) }
    mic.onRestartFailure = { [weak self] error in
      // The mic engine failed to restart after an audio route change —
      // surface it so the UI can warn that the mic side went silent.
      Task { @MainActor in self?.micRestartError = error.localizedDescription }
    }
    tap.signalDetectedHandler = {
      AppSettings.markSystemAudioConfirmed()
      AyrvoConsoleLog.recording("system audio confirmed — non-silent signal received")
    }
    tap.bufferSink = { [weak live] buffer in live?.feedSystem(buffer) }
    // Start the system audio tap FIRST. It creates a Core Audio aggregate
    // device (AudioHardwareCreateAggregateDevice) which can disrupt an
    // already-running AVAudioEngine's input node — the engine's input route
    // becomes stale and no buffers arrive. Starting the tap first means the
    // aggregate device exists before the mic engine starts, so the engine
    // binds to the correct input device.
    do {
      try tap.start(writingTo: systemURL)
      systemStarted = true
      live.systemPeakProvider = { [weak tap] in tap?.recentSystemPeak ?? 0 }
    } catch {
      let ns = error as NSError
      AyrvoConsoleLog.recording(
        "system tap start failed domain=\(ns.domain) code=\(ns.code) — \(error.localizedDescription)"
      )
      problems.append("system audio: \(error.localizedDescription)")
    }
    do {
      try mic.start(writingTo: micURL, sourceApp: sourceApp)
      micStarted = true
    } catch {
      let ns = error as NSError
      AyrvoConsoleLog.recording(
        "mic start failed domain=\(ns.domain) code=\(ns.code) — \(error.localizedDescription)")
      problems.append("microphone: \(error.localizedDescription)")
    }
    guard micStarted || systemStarted else {
      AyrvoConsoleLog.recording("failed to start — \(problems.joined(separator: "; "))")
      throw SessionError.nothingStarted(problems.joined(separator: "; "))
    }
    AyrvoConsoleLog.recording("capture mic=\(micStarted) system=\(systemStarted) live=starting")

    startPostCaptureSetup(live: live)
  }

  /// Post-capture setup shared by both start paths: live transcription launch,
  /// Zoom speaker tracker, elapsed timer, and system-audio watchdog.
  private func startPostCaptureSetup(live: LiveTranscriber) {
    // Model/asset setup is async; buffers fed before it's ready are dropped.
    Task {
      do {
        try await live.start()
        AyrvoConsoleLog.recording("live transcription ready")
      } catch {
        AyrvoConsoleLog.recording("live transcription unavailable — \(error.localizedDescription)")
      }
    }

    // The Zoom AX-tree scan (ZoomActiveSpeakerReader.scan) walks every node
    // in Zoom's accessibility tree and can take 20–30s when the roster is
    // large. Running it on MainActor freezes the menu bar UI at recording
    // start. Move the scan + tracker creation off the main thread; only hop
    // back to MainActor to wire callbacks and start polling.
    Task.detached { [weak self] in
      guard let self else { return }
      let target = await self.speakerTrackingTargetAsync()
      await MainActor.run {
        guard !self.stopped else { return }
        self.speakerTrackingTarget = target
        self.platformTrackingWanted = target != nil
        if target != nil { self.ensurePlatformTracker() }
        self.activeObserver = NotificationCenter.default.addObserver(
          forName: NSApplication.didBecomeActiveNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated { self?.ensurePlatformTrackerIfNeeded() }
        }
      }
    }

    ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.elapsed = self.elapsedOffset + Date().timeIntervalSince(self.startedAt)
      }
    }

    // Coarse 30s timer for the menu-bar status item — avoids redrawing the
    // system status bar every second. `elapsed` (1s) stays smooth for the
    // in-menu RecordingCard; `menuBarElapsed` (30s) feeds only the bar item.
    menuBarElapsed = elapsedOffset
    menuBarTicker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.menuBarElapsed = self.elapsed
      }
    }
    menuBarTicker?.tolerance = 5

    if systemStarted {
      let monitor = SystemAudioMonitor(tap: tap) { [weak self] in self?.systemStarted == true }
      systemAudioMonitor = monitor
      monitor.start()
    }
  }

  /// Applies a live-transcript update on the main actor: refreshes the observable
  /// state and persists to live.json at most every ~1.5 s (throttled so the MCP
  /// process sees a fresh file without thrashing the disk).
  private func applyLive(_ segments: [TranscriptSegment], _ volatile: String) {
    guard !stopped else { return }
    volatileText = volatile
    // Echo detection can retract a previously attributed mic sentence
    // and replace it with system speech without changing the segment count.
    // Comparing only counts leaves stale "You" labels on screen and in live.json.
    guard segments != liveSegments else { return }
    liveSegments = segments
    let now = Date()
    if now.timeIntervalSince(lastLivePersist) >= 1.5 {
      lastLivePersist = now
      archive.saveLiveTranscript(segments, for: meetingID)
    }
  }

  /// Returns the parts that had problems starting, for the meeting notice.
  var startupNotice: String? {
    var parts: [String] = []
    switch (micStarted, systemStarted) {
    case (true, true): break
    case (false, true):
      if AudioDeviceRouting.defaultInputIsBluetooth {
        // The built-in mic fallback should have caught this, but if it
        // also failed (no built-in mic, or TCC blocked), the mic side
        // is lost. The message is source-agnostic now — Chrome/Meet and
        // Zoom all contend for the BT headset mic.
        parts.append(
          "Microphone wasn't recorded — your Bluetooth headset mic is held by the meeting app."
            + " The other side of the call was captured. To record your voice too, switch the meeting app's microphone to your Mac's built-in mic."
        )
      } else {
        parts.append(
          "Microphone wasn't recorded (permission missing?) — only the other side of the call was captured."
        )
      }
      if !tap.signalDetected {
        parts.append(
          "Grant System Audio Recording in Privacy & Security → System Audio Recording Only.")
      }
    case (true, false):
      parts.append(
        "System audio wasn't recorded — only your microphone was captured. Grant System Audio Recording in Privacy & Security."
      )
    case (false, false): break
    }
    if (platformTrackingWanted ?? Self.isZoom(sourceApp)), !AccessibilityPermission.isTrusted {
      parts.append(
        "Enable Accessibility for Ayrvo in Privacy & Security to identify meeting speakers by name.")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " ")
  }

  func stop() {
    let tracker = teardownRecorders()
    // Compute stopNotice off the main thread to avoid the CoreAudio HAL
    // deadlock (MicRecorder.stop()/SystemAudioTap.stop() acquire locks that
    // may be held by a CoreAudio IO callback). Fire-and-forget; the UI
    // observes `@Published stopNotice` when the async block lands.
    Task { await finalizeStopNotice(tracker: tracker) }
    flushLiveTranscriber()
  }

  /// Async variant of `stop()` that awaits the file-size check so callers
  /// (and tests) can observe `stopNotice` deterministically. The recorder
  /// stops and byte check run on a background thread (same deadlock-avoidance
  // as `stop()`), then hop back to the main actor to set `stopNotice`.
  func stopAsync() async {
    let tracker = teardownRecorders()
    // Finalize the files off MainActor, then flush the live transcript before
    // the post-recording pipeline reads either source.
    await finalizeStopNotice(tracker: tracker)
    await flushLiveTranscriberAsync()
  }

  /// Synchronous teardown of timers, observers, trackers, and level meters.
  private func teardownRecorders() -> (any PlatformSpeakerTracker)? {
    stopped = true
    elapsed = max(elapsed, elapsedOffset + Date().timeIntervalSince(startedAt))
    speakerTrackingNotice = nil
    AyrvoConsoleLog.recording(
      "stop meeting=\(meetingID.uuidString.prefix(8)) elapsed=\(Int(elapsed))s liveSegments=\(liveSegments.count)"
    )
    systemAudioMonitor?.stop()
    systemAudioMonitor = nil
    ticker?.invalidate()
    ticker = nil
    menuBarTicker?.invalidate()
    menuBarTicker = nil
    menuBarElapsed = elapsed
    if let activeObserver {
      NotificationCenter.default.removeObserver(activeObserver)
      self.activeObserver = nil
    }
    let tracker = platformSpeakerTracker
    platformSpeakerTracker = nil
    rosterTimer?.invalidate()
    rosterTimer = nil
    liveRoster = []
    LiveTranscriber.localSpeakerName = "You"
    LiveTranscriber.remoteSpeakerName = "Others"
    activeRemoteSpeaker = nil
    micBarLevels = Array(repeating: 0, count: Self.levelBarCount)
    return tracker
  }

  /// Finalize the live transcriber: stop it and flush the last live.json.
  private func flushLiveTranscriber() {
    guard let live = liveTranscriber else { return }
    liveTranscriber = nil
    let archiveRef = self.archive
    // This Task inherits the main actor. After the transcribers finalize,
    // flush the last live.json; the pipeline removes it once the durable
    // transcript.json lands.
    Task {
      let completed = await live.stop()
      archiveRef.saveLiveTranscript(completed, for: meetingID)
      AyrvoConsoleLog.recording("live transcript flushed (\(completed.count) segments)")
    }
  }

  /// The awaited version prevents the final live.json write from racing
  /// with processing (which reads and then removes that file).
  private func flushLiveTranscriberAsync() async {
    guard let live = liveTranscriber else { return }
    liveTranscriber = nil
    let completed = await live.stop()
    // Do not rely on main-actor callback scheduling: the final batch pipeline
    // must persist the fully resolved (echo-filtered) live segments.
    liveSegments = completed
    archive.saveLiveTranscript(completed, for: meetingID)
    AyrvoConsoleLog.recording("live transcript flushed (\(completed.count) segments)")
  }

  /// Stop the mic/system recorders (off the main actor, when called via
  /// `Task.detached`) and compute `stopNotice`. Set when both capture files
  /// are 0 bytes, signalling the UI that no audio was captured. The recorder
  /// stops must run off the main thread because `MicRecorder.stop()` and
  /// `SystemAudioTap.stop()` acquire internal locks/queues that may be held
  /// by a CoreAudio IO callback or a route restart — blocking the main
  /// thread here freezes the UI (the deadlock seen when
  /// `restartAfterConfigurationChange` holds `MicRecorder.lock` while
  /// `stop()` waits for it on the main thread).
  private func finalizeStopNotice(tracker: (any PlatformSpeakerTracker)?) async {
    let micURL = archive.micURL(for: meetingID)
    let systemURL = archive.systemURL(for: meetingID)
    let micRecorder = mic
    let systemTap = tap
    let didMic = micStarted
    let didSystem = systemStarted
    // Run the blocking recorder stops + file-size check off the main actor
    // (see deadlock note above), then set `stopNotice` back here on the main
    // actor — no `MainActor.run` hop needed since this method is @MainActor
    // and the `await` returns us here.
    let result = await Task.detached(priority: .userInitiated) {
      if didMic { micRecorder.stop() }
      if didSystem { systemTap.stop() }
      tracker?.stop()
      let m =
        (try? FileManager.default.attributesOfItem(atPath: micURL.path)[.size] as? Int) ?? 0
      let s =
        (try? FileManager.default.attributesOfItem(atPath: systemURL.path)[.size] as? Int) ?? 0
      return (
        micBytes: m, systemBytes: s,
        micHeard: didMic && micRecorder.captureStats.receivedAnyBuffer,
        systemSignal: didSystem && systemTap.signalDetected,
        writeErrors: [micRecorder.writeError, systemTap.writeError].compactMap { $0 })
    }.value
    let (micBytes, systemBytes) = (result.micBytes, result.systemBytes)
    AyrvoConsoleLog.recording(
      "capture files mic=\(micBytes)B system=\(systemBytes)B micSignal=\(result.micHeard) systemSignal=\(result.systemSignal)"
    )
    let writeErrors = result.writeErrors
    if !writeErrors.isEmpty {
      stopNotice = writeErrors.joined(separator: " ")
    } else if micBytes == 0 && systemBytes == 0 {
      stopNotice = "No audio was captured — check your microphone and system audio settings"
      AyrvoConsoleLog.recording("stop notice: no audio captured (both files empty)")
    } else {
      stopNotice = nil
    }
  }

  private static func isZoom(_ sourceApp: String?) -> Bool {
    MeetingDetector.isZoomSource(sourceApp)
  }

  /// Async variant that runs the AX scan off MainActor. The fast path
  /// (Zoom source) returns immediately without a scan.
  private func speakerTrackingTargetAsync() async -> SpeakerTrackingTarget? {
    if MeetingDetector.isChromeMeetSource(sourceApp) { return .googleMeetChrome }
    if Self.isZoom(sourceApp) { return .zoom }
    guard sourceApp == nil || sourceApp?.isEmpty == true else { return nil }
    guard AccessibilityPermission.isTrusted else { return nil }
    return await Task.detached(priority: .userInitiated) {
      if GoogleMeetReader.scan() != nil { return SpeakerTrackingTarget.googleMeetChrome }
      let scan = ZoomActiveSpeakerReader.scan()
      return scan.zoomPID != nil && !scan.roster.isEmpty ? .zoom : nil
    }.value
  }

  /// Starts the selected meeting tracker once Accessibility trust is granted.
  /// The caller MUST have already verified tracking is needed (via
  /// `speakerTrackingTargetAsync`) — this does NOT re-scan, so it's safe to
  /// call on MainActor without blocking. The immediate initial roster is fetched
  /// asynchronously to avoid blocking MainActor on the tracker's serial queue
  /// (its `logInitialScan` runs a full AX walk on that queue).
  private func ensurePlatformTracker() {
    if platformSpeakerTracker != nil {
      AyrvoConsoleLog.recording("ensurePlatformTracker — already running")
      return
    }
    AyrvoConsoleLog.recording(
      "ensurePlatformTracker — creating tracker accessibility=\(AccessibilityPermission.isTrusted)")
    guard let target = speakerTrackingTarget, !stopped else { return }
    let tracker = PlatformSpeakerTrackerFactory.make(
      target: target,
      meetingID: meetingID,
      archive: archive,
      startDate: startedAt,
      elapsedOffset: elapsedOffset)
    tracker.onActiveSpeaker = { [weak self] name in
      AyrvoConsoleLog.recording("UI activeRemoteSpeaker=\(name ?? "nil")")
      self?.activeRemoteSpeaker = name
    }
    tracker.onLocalMuteChanged = { [weak self] muted in
      guard let self else { return }
      self.micPaused = muted
      if muted {
        AyrvoConsoleLog.recording("mic paused — local participant muted in Zoom")
        self.mic.bufferSink = nil
      } else {
        AyrvoConsoleLog.recording("mic resumed — local participant unmuted in Zoom")
        if let live = self.liveTranscriber {
          self.mic.bufferSink = { buffer in live.feedMic(buffer) }
        }
      }
    }
    // Poll the tracker's roster for the live UI (participant names).
    let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, let tracker = self.platformSpeakerTracker else { return }
        let roster = tracker.currentRoster()
        self.speakerTrackingNotice = tracker.statusMessage
        if roster != self.liveRoster {
          self.liveRoster = roster
          AyrvoConsoleLog.recording("live roster updated: [\(roster.joined(separator: ", "))]")
          self.updateLiveSpeakerNames(from: roster)
        }
      }
    }
    timer.tolerance = 0.5
    rosterTimer = timer
    // Bridge: LiveTranscriber queries the platform tracker's timeline to attribute
    // system-audio segments to the active speaker's name in real time.
    if let live = liveTranscriber {
      live.platformSpeakerResolver = { [weak tracker] t in
        tracker?.speakerAt(t)
      }
      AyrvoConsoleLog.recording("platformSpeakerResolver wired to LiveTranscriber")
    }
    platformSpeakerTracker = tracker
    tracker.start()

    // Fetch the initial roster off MainActor so participant names appear
    // promptly without blocking the main thread on the tracker's serial
    // queue (which runs a full AX scan in logInitialScan). The 2s roster
    // timer above is the fallback if this loses the race.
    Task { [weak tracker, weak self] in
      guard let tracker else { return }
      let roster = await Task.detached(priority: .userInitiated) {
        tracker.currentRoster()
      }.value
      await MainActor.run {
        guard let self, !roster.isEmpty, roster != self.liveRoster else { return }
        self.liveRoster = roster
        self.updateLiveSpeakerNames(from: roster)
        AyrvoConsoleLog.recording("initial roster: [\(roster.joined(separator: ", "))]")
      }
    }
  }

  /// Called from `didBecomeActive` — re-checks whether platform tracking is
  /// needed (the user may have just granted Accessibility, or a meeting may
  /// have started since the initial scan), then creates the tracker if so.
  /// Never blocks MainActor on an AX scan.
  private func ensurePlatformTrackerIfNeeded() {
    guard !stopped else { return }
    if let tracker = platformSpeakerTracker {
      if AccessibilityPermission.isTrusted { tracker.start() }
      return
    }
    Task { [weak self] in
      guard let self else { return }
      let target = await self.speakerTrackingTargetAsync()
      guard !self.stopped else { return }
      self.speakerTrackingTarget = target
      self.platformTrackingWanted = target != nil
      if target != nil { self.ensurePlatformTracker() }
    }
  }

  /// Updates `LiveTranscriber.localSpeakerName` and `.remoteSpeakerName` from the
  /// meeting roster. Meet uses explicit local markers; Zoom uses the existing account matcher.
  /// the remote name is the single non-local participant in a 1:1 call, or
  /// "Others" when there are multiple remote participants (until the active-speaker
  /// timeline can disambiguate them).
  private func updateLiveSpeakerNames(from roster: [String]) {
    let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
    let localName =
      roster.first(where: { platformSpeakerTracker?.isLocalParticipant($0) == true })
      ?? (full.isEmpty ? nil : full)
    let remoteNames = roster.filter { platformSpeakerTracker?.isLocalParticipant($0) != true }

    if let localName, !localName.isEmpty {
      LiveTranscriber.localSpeakerName = localName
      AyrvoConsoleLog.recording("local speaker name → \(localName)")
    }
    // In a 1:1 call with one remote participant, use their name directly.
    // With multiple remotes, keep "Others" — the platform speaker resolver
    // handles per-segment attribution via active-speaker tracking.
    if speakerTrackingTarget != .googleMeetChrome && remoteNames.count == 1 {
      LiveTranscriber.remoteSpeakerName = remoteNames[0]
      AyrvoConsoleLog.recording("remote speaker name → \(remoteNames[0])")
    } else {
      LiveTranscriber.remoteSpeakerName = "Others"
    }
  }
}
