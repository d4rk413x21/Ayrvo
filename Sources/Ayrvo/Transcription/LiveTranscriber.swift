import AVFoundation
import Foundation
import Speech
import Synchronization

/// Real-time, on-device transcription that runs *alongside* recording to feed the
/// live UI and the `get_live_transcript` MCP tool. Two streaming SpeechTranscribers
/// consume the same buffers the recorders already capture — mic tagged "You", the
/// system tap tagged "Others" — and their finalized results merge by wall-clock
/// time into one rolling transcript.
///
/// This is a real-time *approximation*: volatile results are interim and finalized
/// streaming results commit with limited look-ahead. The accurate, diarized
/// transcript is still produced post-hoc by the batch pipeline over the `.m4a`
/// (see the design doc, docs/plans/2026-07-09-live-transcription.md). The streaming
/// SpeechAnalyzer API is pinned in tasks/research/research-speechanalyzer.md.
final class LiveTranscriber: @unchecked Sendable {
  static let youSpeakerID = "me"
  static let othersSpeakerID = "them"

  /// How far apart, in seconds, a mic echo and its clean system copy may land.
  /// The two channels finalize the same utterance independently, so their
  /// point-in-time stamps drift; wider than the batch tolerance to absorb that.
  static let liveEchoWindow: TimeInterval = 6
  /// Allow the remote speech recognizer to finalize before attributing a mic line.
  /// The raw microphone is still recorded without delay.
  static let microphoneAttributionDelay: TimeInterval = 5

  /// Synthetic speakers used to format the live transcript.
  static let speakers = [
    Speaker(id: youSpeakerID, name: "You", isMe: true),
    Speaker(id: othersSpeakerID, name: "Others"),
  ]

  /// Display name for the local speaker ("You"), overridden with the Zoom
  /// roster's local participant name or NSFullUserName when available.
  private static let speakerNames = Mutex((local: "You", remote: "Others"))
  static var localSpeakerName: String {
    get { speakerNames.withLock { $0.local } }
    set { speakerNames.withLock { $0.local = newValue } }
  }

  /// Display name for the remote speaker ("Others"), overridden with the
  /// single remote Zoom participant when the roster has exactly one non-local name.
  static var remoteSpeakerName: String {
    get { speakerNames.withLock { $0.remote } }
    set { speakerNames.withLock { $0.remote = newValue } }
  }

  static func name(for speakerID: String) -> String {
    switch speakerID {
    case youSpeakerID: return localSpeakerName
    case othersSpeakerID: return remoteSpeakerName
    default: return speakerID
    }
  }

  /// A run of consecutive same-speaker segments, for rendering. `id` is the
  /// running index so SwiftUI ForEach stays stable as segments append.
  struct Turn: Identifiable {
    let id: Int
    let speakerID: String
    let text: String
  }

  static func turns(from segments: [TranscriptSegment]) -> [Turn] {
    var out: [Turn] = []
    var speaker: String?
    var texts: [String] = []
    func flush() {
      if let speaker, !texts.isEmpty {
        out.append(Turn(id: out.count, speakerID: speaker, text: texts.joined(separator: " ")))
      }
    }
    for seg in segments {
      if seg.speakerID != speaker {
        flush()
        speaker = seg.speakerID
        texts = []
      }
      texts.append(seg.text)
    }
    flush()
    return out
  }

  /// Called (on an arbitrary task, not the main actor) whenever the rolling
  /// transcript changes: time-sorted finalized segments + the current volatile
  /// (in-progress) fragment. The caller is responsible for hopping to the main
  /// actor / persisting.
  var onUpdate: (@Sendable ([TranscriptSegment], String) -> Void)?

  private let startDate: Date
  /// Seconds already on the meeting before this live session (resume recording).
  private let timeOffset: TimeInterval
  private let lock = NSLock()
  private var finalized: [TranscriptSegment] = []
  // Mic speech is provisional while the other channel's final text catches up.
  // Only validated local utterances become public live transcript segments.
  private var pendingMic: [UInt64: TranscriptSegment] = [:]
  private var nextPendingID: UInt64 = 0
  private var volatile: [String: String] = [:]  // speakerID -> in-progress text
  private var channels: [SpeechAnalysisChannel] = []
  private var started = false
  private var stopped = false

  /// Minimum tap peak that indicates remote speech is playing (headphone bleed proxy).
  static let remoteSpeechPeakThreshold: Float = 0.015

  /// When true, the Mac is using headphones/BT output while the mic is the
  /// built-in — remote audio bleeds into the mic channel and needs aggressive dedup.
  var headphoneBleedMode = false

  /// Returns the current system-tap peak when available (headphone bleed mode).
  var systemPeakProvider: (() -> Float)?

  /// When set, resolves an elapsed timestamp to a platform (Zoom) speaker name.
  /// System-audio segments are attributed to this name instead of "them" when
  /// the platform reports an active speaker at that time.
  var platformSpeakerResolver: (@Sendable (TimeInterval) -> String?)?

  /// When set, pins both channels to this locale for the whole meeting,
  /// overriding the auto-adapting `TranscriptionLocales.primary()` pick.
  /// Nil means "auto" — the transcriber adapts mid-stream across the
  /// reserved locales. Must be set before `start()` runs.
  var localeOverride: Locale?

  init(startDate: Date, timeOffset: TimeInterval = 0) {
    self.startDate = startDate
    self.timeOffset = timeOffset
  }

  /// Sets up both channels. Throws only if no transcriber model is available at
  /// all (the caller then simply skips live transcription — recording is
  /// unaffected). Safe to call once.
  func start() async throws {
    let alreadyStarted = lock.withLock {
      let was = started
      started = true
      return was
    }
    guard !alreadyStarted else { return }

    guard SpeechTranscriber.isAvailable else {
      AyrvoConsoleLog.live("unavailable — speech model not ready")
      throw TranscriberError.modelUnavailable
    }
    // Honor an explicit per-meeting locale pin when set; otherwise fall back
    // to the auto-adapting primary pick (which code-switches across reserved
    // locales). When pinning, still reserve the full asset set so the model
    // is installed even if the override was chosen before its first run.
    let resolved: Locale
    if let override = localeOverride,
      let pinned = await SpeechTranscriber.supportedLocale(equivalentTo: override)
    {
      resolved = pinned
      AyrvoConsoleLog.locales("locale pinned to \(pinned.identifier(.bcp47))")
    } else if let primary = await TranscriptionLocales.primary() {
      resolved = primary
    } else {
      AyrvoConsoleLog.live("no supported locale found")
      throw TranscriberError.modelUnavailable
    }

    AyrvoConsoleLog.live(
      "starting locale=\(resolved.identifier(.bcp47)) offset=\(Int(timeOffset))s")
    try await TranscriptionLocales.ensureModels()

    // SpeechAnalysisChannel setup can block for a while on first-run model asset download. If
    // the second channel fails to build, tear down the first rather than leak it.
    let mic = try await makeChannel(locale: resolved, speakerID: Self.youSpeakerID)
    let system: SpeechAnalysisChannel
    do {
      system = try await makeChannel(locale: resolved, speakerID: Self.othersSpeakerID)
    } catch {
      await Self.teardown([mic])
      throw error
    }

    // stop() may have already run while we were awaiting the downloads above —
    // its `channels` was empty then, so it tore nothing down. If so, tear down
    // what we just built instead of publishing orphaned analyzer sessions.
    let published = lock.withLock {
      guard !stopped else { return false }
      channels = [mic, system]
      return true
    }
    if !published {
      await Self.teardown([mic, system])
    } else {
      AyrvoConsoleLog.live(
        "channels ready (mic + system) headphoneBleed=\(lock.withLock { headphoneBleedMode })")
    }
  }

  /// Labels each channel's in-progress fragment for the live UI.
  static func formattedVolatile(
    _ volatile: [String: String], suppressUnverifiedMic: Bool = false
  ) -> String {
    speakers.compactMap { sp -> String? in
      if suppressUnverifiedMic && sp.id == youSpeakerID { return nil }
      guard let text = volatile[sp.id], !text.isEmpty else { return nil }
      return "\(name(for: sp.id)): \(text)"
    }.joined(separator: "\n")
  }

  func feedMic(_ buffer: AVAudioPCMBuffer) { feed(buffer, speakerID: Self.youSpeakerID) }
  func feedSystem(_ buffer: AVAudioPCMBuffer) { feed(buffer, speakerID: Self.othersSpeakerID) }

  private func feed(_ buffer: AVAudioPCMBuffer, speakerID: String) {
    // The tap/engine buffer is only valid for this callback — deep-copy before
    // handing it to another task.
    guard let copy = AudioPCM.CopiedBuffer(buffer) else { return }
    let channel = lock.withLock { channels.first { $0.speakerID == speakerID } }
    channel?.rawContinuation.yield(copy)
  }

  /// Ends input and finalizes; the per-channel tasks then complete. Sets `stopped`
  /// so a still-in-flight start() tears down rather than publishes its channels.
  @discardableResult
  func stop() async -> [TranscriptSegment] {
    let chans = lock.withLock {
      stopped = true
      let c = channels
      channels = []
      return c
    }
    AyrvoConsoleLog.live("stopping — \(lock.withLock { finalized.count }) finalized segments")
    await Self.teardown(chans)
    // The remote analyzer may finalize its last sentence during teardown.
    // Resolve all staged microphone lines against the complete remote transcript
    // before the recording session persists live.json and starts batch processing.
    let (segments, vol, callback) = lock.withLock {
      for segment in pendingMic.values.sorted(by: { $0.start < $1.start }) {
        if !Self.isPlaybackEcho(segment, among: finalized) {
          Self.insertChronologically(segment, into: &finalized)
        }
      }
      pendingMic.removeAll()
      return (finalized, Self.formattedVolatile(volatile), onUpdate)
    }
    callback?(segments, vol)
    return segments
  }

  /// Finishes each channel's input and awaits its tasks to completion.
  private static func teardown(_ channels: [SpeechAnalysisChannel]) async {
    for c in channels { c.rawContinuation.finish() }
    for c in channels { await c.finish() }
  }

  // MARK: - SpeechAnalysisChannel setup

  private func makeChannel(locale: Locale, speakerID: String) async throws -> SpeechAnalysisChannel {
    try await SpeechAnalysisChannel.make(locale: locale, speakerID: speakerID) { [weak self] result in
      self?.handle(result, speakerID: speakerID)
    }
  }

  private func handle(_ result: SpeechTranscriber.Result, speakerID: String) {
    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
    let elapsed = max(0, Date().timeIntervalSince(startDate)) + timeOffset

    // Don't acquire the CoreAudio tap lock while holding the transcript lock.
    // This peak is a hint for the UI only; it never deletes local speech.
    let remotePlaybackActive = (systemPeakProvider?() ?? 0) >= Self.remoteSpeechPeakThreshold
    let platformSpeaker: String? = (speakerID == Self.othersSpeakerID)
      ? platformSpeakerResolver?(elapsed) : nil

    lock.lock()
    let effectiveSpeaker = speakerID
    let segSpeakerID = platformSpeaker ?? effectiveSpeaker
    if result.isFinal {
      volatile[effectiveSpeaker] = nil
      if !text.isEmpty {
        let segment = TranscriptSegment(
          speakerID: segSpeakerID, start: elapsed, end: elapsed, text: text)
        if speakerID == Self.youSpeakerID && systemPeakProvider != nil {
          if Self.isPlaybackEcho(segment, among: finalized) {
            AyrvoConsoleLog.live("suppressed mic echo @ \(String(format: "%.1f", elapsed))s: \(text.prefix(60))")
          } else {
            // The system ASR result often arrives AFTER the mic ASR result.
            // Wait briefly rather than showing a false "You" line and retracting
            // it once the system channel finally publishes the same sentence.
            let id = nextPendingID
            nextPendingID += 1
            pendingMic[id] = segment
            Task.detached { [weak self] in
              try? await Task.sleep(for: .seconds(Self.microphoneAttributionDelay))
              self?.publishPendingMic(id: id)
            }
          }
        } else {
          Self.insertChronologically(segment, into: &finalized)
          if speakerID != Self.youSpeakerID {
            let matched = pendingMic.filter {
              Self.isPlaybackEcho($0.value, among: finalized)
            }
            for (id, pending) in matched {
              pendingMic.removeValue(forKey: id)
              AyrvoConsoleLog.live(
                "suppressed pending mic echo @ \(String(format: "%.1f", pending.start))s")
            }
          }
          // Still handle an echo if the two ASR streams finalize more than
          // the wait apart, and recognize named remote speakers too.
          Self.removeEchoedMicSegments(
            around: segment.start, in: &finalized,
            window: Self.liveEchoWindow)
          if speakerID == Self.youSpeakerID && !finalized.contains(where: { $0.id == segment.id }) {
            AyrvoConsoleLog.live("suppressed mic echo @ \(String(format: "%.1f", elapsed))s")
          } else if let platformSpeaker, platformSpeaker != effectiveSpeaker {
            AyrvoConsoleLog.live(
              "platform→\(platformSpeaker) @ \(String(format: "%.1f", elapsed))s: \(text.prefix(80))")
          } else {
            AyrvoConsoleLog.live(
              "final \(segSpeakerID) @ \(String(format: "%.1f", elapsed))s (\(finalized.count) segments): \(text.prefix(80))")
          }
        }
      }
    } else {
      // Even partial recognition on the mic can be far-end loudspeaker bleed.
      // Avoid assigning it to "You" while output is active. The final mic text
      // is kept for verification, not discarded.
      volatile[effectiveSpeaker] = text.isEmpty ? nil : text
    }
    let segments = finalized
    let vol = Self.formattedVolatile(
      volatile, suppressUnverifiedMic: remotePlaybackActive)
    let callback = onUpdate
    lock.unlock()
    callback?(segments, vol)
  }

  private func publishPendingMic(id: UInt64) {
    lock.lock()
    // Stop resolves the pending queue itself after the system stream closes.
    guard !stopped, let segment = pendingMic.removeValue(forKey: id) else {
      lock.unlock()
      return
    }
    if !Self.isPlaybackEcho(segment, among: finalized) {
      Self.insertChronologically(segment, into: &finalized)
      AyrvoConsoleLog.live(
        "confirmed local speech @ \(String(format: "%.1f", segment.start))s (\(finalized.count) segments): \(segment.text.prefix(80))")
    } else {
      AyrvoConsoleLog.live(
        "suppressed delayed mic echo @ \(String(format: "%.1f", segment.start))s")
    }
    let segments = finalized
    let vol = Self.formattedVolatile(volatile)
    let callback = onUpdate
    lock.unlock()
    callback?(segments, vol)
  }

  /// Match a mic hypothesis against the *independent system-audio transcript*.
  /// Only near-verbatim text in a small time window can be removed. Shared
  /// topic words (or just both people speaking at once) are not enough.
  static func isPlaybackEcho(
    _ mic: TranscriptSegment, among segments: [TranscriptSegment]
  ) -> Bool {
    guard mic.speakerID == youSpeakerID else { return false }
    let words = TranscriptText.wordTokens(mic.text)
    guard words.count >= 2 else { return false }
    let nearby = segments.filter {
      $0.speakerID != youSpeakerID
        && abs($0.start - mic.start) <= liveEchoWindow
    }.sorted { $0.start < $1.start }
    guard !nearby.isEmpty else { return false }
    if words.count <= 4 {
      return nearby.contains {
        TranscriptText.wordTokens($0.text) == words
      }
    }
    return nearby.contains {
      TranscriptText.covers(mic.text, by: $0.text, atLeast: 0.82)
    } || TranscriptText.covers(
      mic.text, by: nearby.map(\.text).joined(separator: " "), atLeast: 0.82)
  }

  private static func insertChronologically(
    _ segment: TranscriptSegment, into segments: inout [TranscriptSegment]
  ) {
    var index = segments.count
    while index > 0 && segments[index - 1].start > segment.start { index -= 1 }
    segments.insert(segment, at: index)
  }

  // MARK: - Echo dedup

  /// Removes mic ("You") echoes from the neighborhood of a just-inserted segment.
  /// Live segments are point-in-time, so this matches on a time window plus word
  /// coverage rather than the batch path's interval overlap. It runs on every
  /// final segment (either channel), which makes it bidirectional: a "You" echo
  /// is dropped whether the clean system copy arrives before or after it. Only the
  /// time-window tail slice is scanned, so it stays O(k), not O(n), per update.
  ///
  /// Short backchannels (< 4 tokens, e.g. "yeah", "right") are left alone so a
  /// genuine local affirmation that happens to echo isn't nuked.
  ///
  /// The word-coverage bar is higher than the batch path's (0.75 vs 0.6): live
  /// segments are point-in-time, so this can only match on a time window, not the
  /// batch path's interval overlap. A real echo is a near-verbatim re-transcription
  /// (coverage ~1.0), so the stricter bar still catches it while sparing a genuine
  /// local line that merely shares some vocabulary with a nearby far-end line.
  static func removeEchoedMicSegments(
    around anchor: TimeInterval, in segments: inout [TranscriptSegment], window: TimeInterval,
    minCoverage: Double = 0.75
  ) {
    let lo = anchor - window
    let hi = anchor + window
    // `segments` is time-ordered, so the window is a contiguous slice ending at
    // the tail. Walk back only until we fall out of it.
    var start = segments.count
    while start > 0, segments[start - 1].start >= lo { start -= 1 }
    let others = segments[start...].filter {
      $0.speakerID != youSpeakerID && $0.start <= hi
    }
    guard !others.isEmpty else { return }
    var i = segments.count - 1
    while i >= start {
      let seg = segments[i]
      if seg.speakerID == youSpeakerID, seg.start <= hi,
        TranscriptText.wordTokens(seg.text).count >= 4,
        others.contains(where: {
          TranscriptText.covers(seg.text, by: $0.text, atLeast: minCoverage)
        })
      {
        segments.remove(at: i)
      }
      i -= 1
    }
  }

  /// Headphone bleed: built-in mic hears BT output. Far-end lines often land on
  /// the mic channel with a different transcript than the system tap, so timing
  /// plus a small shared-vocabulary check catches them when verbatim dedup cannot.
  static func removeHeadphoneBleedMic(
    around anchor: TimeInterval, othersText: String, in segments: inout [TranscriptSegment],
    window: TimeInterval, minOthersWords: Int = 4, minMicWords: Int = 4, minSharedWords: Int = 2
  ) {
    let othersWords = Set(TranscriptText.wordTokens(othersText))
    guard othersWords.count >= minOthersWords else { return }
    let lo = anchor - window
    let hi = anchor + window
    var i = segments.count - 1
    while i >= 0 {
      let seg = segments[i]
      if seg.speakerID == youSpeakerID, seg.start >= lo, seg.start <= hi {
        let micWords = TranscriptText.wordTokens(seg.text)
        if micWords.count >= minMicWords {
          let shared = micWords.filter { othersWords.contains($0) }.count
          if shared >= minSharedWords {
            segments.remove(at: i)
          }
        }
      }
      i -= 1
    }
  }
}
