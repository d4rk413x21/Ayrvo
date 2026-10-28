import Foundation
import Synchronization
import AppKit
import ApplicationServices

/// Polls the installed Zoom Workplace client during recording and logs who the
/// meeting UI marks as speaking. Events are written to `speaker_events.json`
/// and later correlated with the system-audio transcript.
final class ZoomSpeakerTracker: PlatformSpeakerTracker, @unchecked Sendable {
    private let meetingID: UUID
    private let archive: MeetingArchive
    private let startDate: Date
    private let elapsedOffset: TimeInterval
    private let queue = DispatchQueue(label: "io.github.d4rk413x21.Ayrvo.zoom-speakers")
    /// Interval between active-speaker polls (seconds). 400 ms balances responsiveness
    /// against AX-tree traversal cost on long calls.
    private static let zoomPollInterval: TimeInterval = 0.4
    /// Delay before the first poll after `start()` (seconds), letting Zoom settle.
    private static let zoomPollStartupDelay: TimeInterval = 0.5
    /// Shared locale-aware formatter for second values in log strings, replacing
    /// `String(format: "%.1f"/"%.0f", …)` which ignores the user's locale.
    private static let secondsFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f
    }()
    /// Formats `t` seconds with one decimal, locale-aware.
    private static func seconds(_ t: TimeInterval) -> String {
        secondsFormatter.string(from: NSNumber(value: t)) ?? "\(t)"
    }
    private static let secondsRoundedFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.maximumFractionDigits = 0
        f.roundingMode = .halfEven
        return f
    }()
    /// Formats `t` seconds with no decimals, locale-aware.
    private static func secondsRounded(_ t: TimeInterval) -> String {
        secondsRoundedFormatter.string(from: NSNumber(value: t)) ?? "\(Int(t))"
    }
    private var timer: DispatchSourceTimer?
    private var events: [PlatformSpeakerEvent] = []
    private var open: (name: String, start: TimeInterval, source: PlatformSpeakerSource)?
    private var lastPersist = Date.distantPast
    private var lastReportedName: String?
    private var tickCount = 0
    /// Count of consecutive ticks with no active speaker; surfaced in the periodic
    /// heartbeat log so a stuck/empty-scan state is visible without a separate probe.
    private var emptyTickStreak = 0
    private var lastSummary = Date.distantPast
    private var lastCaptionKey: String?
    private var lastRoster: [String] = []
    private var rosterPersisted = false
    private var lastLocalMuted: Bool?
    /// One-shot: dump the AX tree once when active speaker detection fails for
    /// several consecutive ticks despite having a roster. `logInitialScan` only
    /// fires at start(); if the meeting starts after Ayrvo launches, we'd never
    /// get a dump. This fires mid-meeting the first time emptyStreak hits 10.
    private var dumpedForEmptyActive = false

    /// Called on the main queue when the local participant's Zoom mute state changes.
    /// True = muted in Zoom (don't capture mic), false = unmuted (capture mic).
    @MainActor var onLocalMuteChanged: (@MainActor (Bool) -> Void)?

     /// Called on the main queue whenever the active remote speaker changes.
     @MainActor var onActiveSpeaker: (@MainActor (String?) -> Void)?
    /// Thread-safe snapshot of the active speaker name at a given elapsed time.
    /// Called from the LiveTranscriber's handle() to attribute system-audio
    /// segments to the Zoom-reported speaker instead of generic "Others".
    func speakerAt(_ t: TimeInterval) -> String? {
        queue.sync {
            // Check the open segment first (most recent), then walk events backward.
            if let open, t >= open.start {
                return open.name
            }
            for event in events.reversed() where t >= event.start && t < event.end {
                return event.name
            }
            return nil
        }
    }

    /// Thread-safe snapshot of the current participant roster.
    func currentRoster() -> [String] {
        queue.sync { lastRoster }
    }

    init(
        meetingID: UUID,
        archive: MeetingArchive,
        startDate: Date,
        elapsedOffset: TimeInterval = 0
    ) {
        self.meetingID = meetingID
        self.archive = archive
        self.startDate = startDate
        self.elapsedOffset = elapsedOffset
    }

    func start() {
        let trusted = AccessibilityPermission.isTrusted
        AyrvoConsoleLog.zoom(
            "start meeting=\(meetingID.uuidString.prefix(8)) accessibility=\(trusted)")
        guard trusted else {
            AyrvoConsoleLog.zoom("blocked — grant Accessibility to Ayrvo, then refocus the app")
            Task { @MainActor in AccessibilityPermission.request() }
            return
        }
        queue.async {
            guard self.timer == nil else {
                AyrvoConsoleLog.zoom("start skipped — timer already running")
                return
            }
            AyrvoConsoleLog.zoom("polling every \(Int(Self.zoomPollInterval * 1000))ms")
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + Self.zoomPollStartupDelay, repeating: Self.zoomPollInterval)
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
            self.logInitialScan()
        }
    }

    func stop() {
        queue.sync {
            self.timer?.cancel()
            self.timer = nil
            self.closeOpen(until: self.now)
            self.persist(force: true)
            // Always persist the final roster so the batch pipeline can attribute
            // speaker names even if the roster never changed during the call
            // (the tick() save is gated on roster change, which never fires for
            // a stable participant list — leaving no zoom_roster.json behind).
            if !self.lastRoster.isEmpty {
                self.archive.saveZoomRoster(self.lastRoster, for: self.meetingID)
                AyrvoConsoleLog.zoom("stop: persisted final roster (\(self.lastRoster.count) names)")
            }
            let saved = PlatformSpeakerTurnBuilder.normalized(self.events)
            AyrvoConsoleLog.zoom(
                "stop ticks=\(self.tickCount) events=\(saved.count) saved=\(saved.map { "\($0.name) \(Self.seconds($0.start))-\(Self.seconds($0.end))" }.joined(separator: ", "))")
            Task { @MainActor in self.onActiveSpeaker?(nil) }
        }
    }

    // MARK: - Internals

    private func logInitialScan() {
        let scan = ZoomActiveSpeakerReader.scan()
        AyrvoConsoleLog.zoom(
            "initial scan zoomPID=\(scan.zoomPID.map(String.init) ?? "nil") roster=[\(scan.roster.joined(separator: ", "))] active=[\(scan.active.joined(separator: ", "))] captions=\(scan.latestCaption.map { "\($0.name): \($0.text.prefix(40))" } ?? "none")")
        // Full AX tree dump for debugging — reveals tile descriptions, roles, and
        // attributes the parsers might miss. Logged at .info so it appears in Console.app.
        if scan.roster.isEmpty || (scan.active.isEmpty && !scan.roster.isEmpty) {
            AyrvoConsoleLog.zoom("no active speaker found (roster=\(scan.roster.count)) — dumping full AX tree for diagnosis")
            ZoomActiveSpeakerReader.dumpAXTree()
        }
    }

    private func tick() {
        tickCount += 1
        let scan = ZoomActiveSpeakerReader.scan()
        let names = scan.active
        let t = now

        recordCaption(scan.latestCaption, at: t)

        if names.isEmpty {
            emptyTickStreak += 1
            closeOpen(until: t)
            reportActive(nil)
        } else {
            emptyTickStreak = 0
            let primary = names[0]
            let source = scan.activeSource
            reportActive(primary)
            if let open, open.name != primary {
                events.append(PlatformSpeakerEvent(
                    name: open.name, start: open.start, end: t, source: open.source))
                AyrvoConsoleLog.zoom(
                    "segment closed \(open.name) \(Self.seconds(open.start))-\(Self.seconds(t))s → now \(primary)")
                self.open = (primary, t, source)
            } else if open == nil {
                open = (primary, t, source)
                AyrvoConsoleLog.zoom("segment opened \(primary) @ \(Self.seconds(t))s (\(source.rawValue))")
            }
            persist(force: false)
        }

        // Persist the roster whenever it changes, OR on the first non-empty scan.
        // When the scan returns empty (Zoom window temporarily not in the AX tree,
        // e.g. another app frontmost, window redrawing), keep the last known roster
        // rather than blanking it — the participants haven't actually left.
        if scan.roster.isEmpty {
            // Keep lastRoster; don't overwrite with empty.
        } else if scan.roster != lastRoster || !rosterPersisted {
            lastRoster = scan.roster
            archive.saveZoomRoster(scan.roster, for: meetingID)
            rosterPersisted = true
        }

        // Detect local participant's mute state change. When muted in Zoom,
        // the mic should stop capturing (silence anyway) and live segments
        // should not be attributed to "me". When unmuted, resume capturing.
        if let muted = scan.localParticipantMuted, muted != lastLocalMuted {
            lastLocalMuted = muted
            AyrvoConsoleLog.zoom("local participant \(muted ? "muted" : "unmuted") — \(muted ? "pausing mic capture" : "resuming mic capture")")
            DispatchQueue.main.async { self.onLocalMuteChanged?(muted) }
        }

        let now = Date()
        if now.timeIntervalSince(lastSummary) >= 5 {
            lastSummary = now
            AyrvoConsoleLog.zoom(
                "heartbeat ticks=\(tickCount) active=\(names.first ?? "none")\(names.count > 1 ? " all=[\(names.joined(separator: ", "))]" : "") roster=\(scan.roster.count) emptyStreak=\(emptyTickStreak) events=\(events.count) elapsed=\(Self.secondsRounded(t))s")
            if names.isEmpty, !scan.roster.isEmpty {
                AyrvoConsoleLog.zoom(
                    "no active speaker tile — roster: [\(scan.roster.joined(separator: ", "))]")
            }
            if scan.roster.isEmpty {
                AyrvoConsoleLog.zoom(
                    "no participant tiles found — is Zoom in a meeting? pid=\(scan.zoomPID.map(String.init) ?? "nil")")
            }
        }
        // One-shot mid-meeting diagnostic dump: if we've had 10+ consecutive
        // ticks with no active speaker but a populated roster, dump the AX tree
        // once so we can see what attributes Zoom exposes for the active speaker.
        // logInitialScan only fires at start(); this catches meetings that begin
        // after Ayrvo launches.
        if !dumpedForEmptyActive, emptyTickStreak >= 10, !scan.roster.isEmpty {
            dumpedForEmptyActive = true
            AyrvoConsoleLog.zoom("emptyStreak=\(emptyTickStreak) with roster=\(scan.roster.count) — dumping AX tree for active-speaker diagnosis")
            ZoomActiveSpeakerReader.dumpAXTree()
        }
    }

    private func reportActive(_ name: String?) {
        let previous = lastReportedName
        guard name != previous else { return }
        lastReportedName = name
        if let name {
            AyrvoConsoleLog.zoom("active speaker → \(name)")
        } else if previous != nil {
            AyrvoConsoleLog.zoom("active speaker cleared")
        }
        Task { @MainActor in onActiveSpeaker?(name) }
    }

    private func closeOpen(until end: TimeInterval) {
        guard let open else { return }
        if end > open.start {
            events.append(PlatformSpeakerEvent(
                name: open.name, start: open.start, end: end, source: open.source))
        }
        self.open = nil
    }

    /// Captures a short caption window when Zoom live transcript exposes speaker-prefixed lines.
    private func recordCaption(_ caption: ZoomActiveSpeakerReader.CaptionLine?, at t: TimeInterval) {
        guard let caption else { return }
        let key = "\(caption.name)|\(caption.text)"
        guard key != lastCaptionKey else { return }
        lastCaptionKey = key
        let start = max(0, t - 1.5)
        events.append(PlatformSpeakerEvent(
            name: caption.name, start: start, end: t, source: .caption))
        AyrvoConsoleLog.zoom("caption \(caption.name): \(caption.text.prefix(60))")
        persist(force: false)
    }

    private var now: TimeInterval {
        elapsedOffset + Date().timeIntervalSince(startDate)
    }

    private func persist(force: Bool) {
        let current = Date()
        guard force || current.timeIntervalSince(lastPersist) >= 2 else { return }
        lastPersist = current
        let normalized = PlatformSpeakerTurnBuilder.normalized(events)
        archive.savePlatformSpeakerEvents(normalized, for: meetingID)
        if force || normalized.count % 3 == 0 {
            AyrvoConsoleLog.zoom("persisted \(normalized.count) events to speaker_events.json")
        }
    }
}
