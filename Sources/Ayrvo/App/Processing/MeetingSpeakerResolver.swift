import Foundation

enum MeetingSpeakerResolver {
    struct Result: Sendable {
        let segments: [TranscriptSegment]
        let speakers: [Speaker]
        let roster: [String]
        let platformSpeakerAttribution: Bool
        let notices: [String]
    }

    /// Shared locale-aware formatter for one-decimal second values in log strings,
    /// replacing `String(format: "%.1f", …)` which ignores the user's locale.
    private static let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f
    }()

    /// Formats a speaker turn's range as `"name 12.3-45.6"`, locale-aware.
    private static func formatTurnRange(speaker: String, start: TimeInterval, end: TimeInterval) -> String {
        let s = decimalFormatter.string(from: NSNumber(value: start)) ?? "\(start)"
        let e = decimalFormatter.string(from: NSNumber(value: end)) ?? "\(end)"
        return "\(speaker) \(s)-\(e)"
    }

    static func resolve(
        meeting: Meeting, archive: MeetingArchive,
        channels: MeetingAudioTranscriber.Channels, hasSystem: Bool,
        onProgress: @escaping @Sendable (String) -> Void
    ) async -> Result {
        let id = meeting.id
        let systemURL = archive.systemURL(for: id)
        let micOut = channels.microphone
        let systemOut = channels.system
        var notices: [String] = []
        var platformSpeakerAttribution = false
        // 2. Speakers — hybrid: Zoom AX timeline + on-device diarization for gaps.
        var turns: [DiarizedTurn]?
        var namedSpeakers = false
        let participants = archive.platformParticipants(for: id)
        let explicitIdentity = participants != nil
        let platformEvents = archive.platformSpeakerEvents(for: id)
            .filter { explicitIdentity || !ZoomActiveSpeakerReader.isLocalParticipant($0.name) }
        let roster = participants?.map(\.name) ?? archive.zoomRoster(for: id)
        AyrvoConsoleLog.pipeline(
            "speakers meeting=\(id.uuidString.prefix(8)) platformEvents=\(platformEvents.count)"
                + " roster=\(roster.count) identifySpeakers=\(AppSettings.identifySpeakers)")

        var diarizedTurns: [DiarizedTurn]?
        if AppSettings.identifySpeakers, hasSystem {
            onProgress(platformEvents.isEmpty ? "Identifying speakers…" : "Identifying speakers (hybrid)…")
            do {
                // A browser panel can expose only a visible subset; it is not an upper bound.
                let maxSpeakers = explicitIdentity ? nil : (meeting.attendees.isEmpty
                    ? (roster.isEmpty ? nil : roster.count)
                    : meeting.attendees.count)
                diarizedTurns = try await Diarizer.diarize(fileURL: systemURL, maxSpeakers: maxSpeakers)
            } catch {
                notices.append(MeetingNotice.speakerIdentificationUnavailable)
                AyrvoConsoleLog.pipeline("diarization failed — \(error.localizedDescription)")
            }
        }

        if !platformEvents.isEmpty {
            if let diarizedTurns, !diarizedTurns.isEmpty {
                let merged = SpeakerTurnMerger.merge(
                    platformEvents: platformEvents,
                    diarized: diarizedTurns,
                    roster: explicitIdentity ? [] : roster,
                    attendees: explicitIdentity ? [] : meeting.attendees)
                turns = merged.turns
                namedSpeakers = merged.hasNamedSpeakers
                platformSpeakerAttribution = true
                AyrvoConsoleLog.pipeline(
                    "hybrid timeline: \(merged.turns.map { formatTurnRange(speaker: $0.speaker, start: $0.start, end: $0.end) }.joined(separator: ", "))")
            } else {
                onProgress("Labeling speakers from the meeting…")
                turns = PlatformSpeakerTurnBuilder.turns(
                    from: PlatformSpeakerTurnBuilder.normalized(platformEvents))
                namedSpeakers = true
                platformSpeakerAttribution = true
                AyrvoConsoleLog.pipeline(
                    "using meeting timeline only: \(turns?.map { formatTurnRange(speaker: $0.speaker, start: $0.start, end: $0.end) }.joined(separator: ", ") ?? "")")
            }
        } else if let diarizedTurns {
            turns = diarizedTurns
            AyrvoConsoleLog.pipeline("using diarization only (\(diarizedTurns.count) turns)")
        }

        // Inspect the recorded audio before attributing microphone duplicates
        // to the local speaker. Errors leave the original transcript intact.
        let echoEvidence: AcousticEchoEvidence?
        if micOut != nil && systemOut != nil {
            do {
                echoEvidence = try AcousticEchoEvidence.load(
                    microphoneURL: micURL, systemURL: systemURL)
            } catch {
                echoEvidence = nil
                AyrvoConsoleLog.pipeline(
                    "acoustic echo check unavailable — \(error.localizedDescription)")
            }
        } else {
            echoEvidence = nil
        }

        let myName = participants?.first(where: \.isLocal)?.name
            ?? (NSFullUserName().isEmpty ? "Me" : NSFullUserName())
        let (segments, speakers) = SpeakerLabeler.label(
            mic: micOut,
            system: systemOut,
            systemTurns: turns,
            myName: myName,
            namedSpeakers: namedSpeakers,
            echoEvidence: echoEvidence)
        return Result(
            segments: segments, speakers: speakers, roster: roster,
            platformSpeakerAttribution: platformSpeakerAttribution, notices: notices)
    }
}
