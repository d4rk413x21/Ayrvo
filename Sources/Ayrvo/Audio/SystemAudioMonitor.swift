import Foundation

struct SystemAudioHealth {
    private var lastCount: UInt64 = 0
    private var stalledSince: Date?

    mutating func stalledDuration(callbackCount: UInt64, at now: Date) -> TimeInterval? {
        guard callbackCount > 0 else { stalledSince = nil; return nil }
        guard callbackCount == lastCount else {
            reset(callbackCount: callbackCount)
            return nil
        }
        let since = stalledSince ?? now
        stalledSince = since
        return now.timeIntervalSince(since)
    }

    mutating func reset(callbackCount: UInt64) {
        lastCount = callbackCount
        stalledSince = nil
    }
}

/// Owns the two system-capture checks for the lifetime of an active recording.
@MainActor
final class SystemAudioMonitor {
    private static let signalCheckInterval: TimeInterval = 15
    private static let watchdogInterval: TimeInterval = 5
    private static let watchdogGrace: TimeInterval = 10
    private let tap: SystemAudioTap
    private let isCapturing: @MainActor () -> Bool
    private var signalCheck: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?

    init(tap: SystemAudioTap, isCapturing: @escaping @MainActor () -> Bool) {
        self.tap = tap
        self.isCapturing = isCapturing
    }

    isolated deinit { stop() }

    func start() {
        stop()
        signalCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.signalCheckInterval))
            guard !Task.isCancelled, let self, self.isCapturing(), !self.tap.signalDetected else { return }
            let count = self.tap.currentCallbackCount
            AyrvoConsoleLog.recording(
                count == 0
                    ? "system tap received no callbacks after \(Int(Self.signalCheckInterval))s — confirm another app is playing audio; if so, check System Audio Recording permission"
                    : "system tap received audio buffers but no audible signal after \(Int(Self.signalCheckInterval))s — confirm playback is audible and System Audio Recording is allowed")
        }
        watchdog = Task { [weak self] in
            var health = SystemAudioHealth()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.watchdogInterval))
                guard !Task.isCancelled, let self, self.isCapturing() else { return }
                let count = self.tap.currentCallbackCount
                // A tap with no callbacks may simply be waiting for another app to play audio.
                if let duration = health.stalledDuration(callbackCount: count, at: .now),
                   duration >= Self.watchdogGrace {
                    AyrvoConsoleLog.recording(
                        "system tap stalled (callbacks=\(count) for \(Int(duration))s) — rebuilding")
                    self.tap.rebuildCapture()
                    health.reset(callbackCount: self.tap.currentCallbackCount)
                }
            }
        }
    }

    func stop() {
        signalCheck?.cancel()
        signalCheck = nil
        watchdog?.cancel()
        watchdog = nil
    }
}
