import AVFoundation
import Foundation

/// Post-recording pipeline: transcribe both channels → identify speakers →
/// label segments → summarize + title. Pure orchestration; every stage is
/// resilient — a meeting with any transcript at all ends up .ready.
enum ProcessingPipeline {
    static func run(
        meeting: Meeting,
        archive: MeetingArchive,
        onProgress: @escaping @Sendable (String) -> Void,
        onSummary: @escaping @Sendable (SummaryUpdate) -> Void = { _ in }
    ) async -> ProcessingOutcome {
        let id = meeting.id
        let storedTranscript = archive.transcript(for: id)
        let liveSegments = archive.liveTranscript(for: id)
        // ProcessingUseCase preserves the live draft in transcript.json before
        // starting ASR. It is provisional, NOT a previous recording. Remove
        // only an exact shifted suffix, so final ASR replaces rather than
        // duplicates it; earlier sessions and user-edited turns remain intact.
        let priorSegments = Self.priorSegmentsExcludingPromotedLive(
            storedTranscript, live: liveSegments)
        let appendOffset = Self.appendOffset(meeting: meeting, prior: priorSegments)
        let micURL = archive.micURL(for: id)
        let systemURL = archive.systemURL(for: id)
        let hasMic = Self.hasUsableAudio(at: micURL)
        let hasSystem = Self.hasUsableAudio(at: systemURL)
        if !hasSystem && FileManager.default.fileExists(atPath: systemURL.path) {
            AyrvoConsoleLog.pipeline(
                "system audio has no decodable samples (recording may have contained no playback); skipping ASR and diarization")
        }
        var notices: [String] = meeting.notice.map { [$0] } ?? []
        var outcome = ProcessingOutcome(state: .ready)

        // 0. Draft the notes from the live transcript first, so they appear seconds
        //    after Stop (streamed token by token) while the accurate transcript is
        //    still being built. A failed draft just falls through to the batch pass.
        AyrvoConsoleLog.pipeline(
            "run meeting=\(id.uuidString.prefix(8)) title=\"\(meeting.title)\" mic=\(hasMic) system=\(hasSystem)"
                + " live=\(liveSegments.count) prior=\(priorSegments.count) duration=\(Int(meeting.duration))s")
        let liveText = TranscriptFormatter.plainText(liveSegments, speakers: LiveTranscriber.speakers)
        let priorText = priorSegments.isEmpty
            ? ""
            : TranscriptFormatter.plainText(priorSegments, speakers: meeting.speakers)
        let draftInput = [priorText, liveText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        var draft: (text: String, provider: String)?
        var expectedSummary = archive.summary(for: id)
        let userNotes = archive.sideNotes(for: id)
        if !draftInput.isEmpty {
            AyrvoConsoleLog.pipeline("drafting from live transcript (\(draftInput.count) chars)")
            onSummary(.streaming(""))
            switch await MeetingSummarizer.summarize(
                meeting: meeting, transcript: draftInput, userNotes: userNotes,
                onDelta: { onSummary(.streaming($0)) }) {
            case .success(let text, let provider):
                // Only treat the draft as real if it actually persisted. If the write
                // fails, leaving `draft` nil lets the improvement pass save normally
                // rather than the edit-guard (disk == draft.text) blocking it too.
                do {
                    try archive.saveSummary(text, for: id, replacing: expectedSummary)
                    expectedSummary = text
                    draft = (text, provider)
                    outcome.summaryProvider = provider
                    onSummary(.draftSaved)
                    AyrvoConsoleLog.pipeline("draft saved via \(provider) (\(text.count) chars)")
                } catch MeetingArchive.ArchiveError.summaryChanged {
                    onSummary(.done)
                } catch {
                    expectedSummary = text
                    AyrvoConsoleLog.pipeline("draft save failed — \(error.localizedDescription)")
                    onSummary(.done)
                }
            case .failure:
                AyrvoConsoleLog.pipeline("draft summarization failed")
                // No draft — clear the transient streaming UI so it doesn't linger
                // through transcription; the batch pass will write the notes.
                onSummary(.done)
            }
        }

        // 1. Transcribe. Honor the locale chosen for this meeting, even
        // if it differs from the system language used by the batch pipeline.
        let meetingLocale = TranscriptionLocales.storedLocale(forMeetingID: id, root: archive.root)
        let channels = await MeetingAudioTranscriber.transcribe(
            microphoneURL: hasMic ? micURL : nil, systemURL: hasSystem ? systemURL : nil,
            locale: meetingLocale, onProgress: onProgress)
        let micOut = channels.microphone
        let systemOut = channels.system
        notices += channels.notices

        guard micOut != nil || systemOut != nil else {
            // No accurate transcript from this session. If a draft (and any live
            // transcript AppState already surfaced) exist, keep them rather than
            // failing the meeting — and still name the meeting from the draft.
            if let draft, meeting.calendarEventTitle == nil {
                onProgress("Naming the meeting…")
                outcome.generatedTitle = await MeetingTitleGenerator.generateTitle(summary: draft.text, provider: draft.provider)
            }
            onSummary(.done)
            outcome.state = (draft == nil && priorSegments.isEmpty) ? .failed : .ready
            outcome.summaryProvider = draft?.provider
            let hasTranscriptContent = !priorSegments.isEmpty || !liveSegments.isEmpty || draft != nil
            outcome.notice = notices.isEmpty
                ? ((draft == nil && priorSegments.isEmpty) ? MeetingNotice.noAudioTranscribed : nil)
                : MeetingNotice.finalizedNotice(notices, hasTranscriptContent: hasTranscriptContent)
            AyrvoConsoleLog.pipeline("run finished state=\(outcome.state) (no audio transcribed)")
            return outcome
        }

        let resolved = await MeetingSpeakerResolver.resolve(
            meeting: meeting, archive: archive, channels: channels,
            hasSystem: hasSystem, onProgress: onProgress)
        let segments = resolved.segments
        let speakers = resolved.speakers
        let roster = resolved.roster
        notices += resolved.notices
        outcome.platformSpeakerAttribution = resolved.platformSpeakerAttribution
        let offsetSegments = Self.offsetSegments(segments, by: appendOffset)
        let mergedSegments = priorSegments + offsetSegments
        do { try archive.saveTranscript(mergedSegments, for: id) }
        catch {
            outcome.state = .failed
            outcome.notice = "The transcript could not be saved. Keep Ayrvo open and retry saving."
            onSummary(.done)
            return outcome
        }
        // The meeting may still hold provisional live speakers ("me"/"them").
        // Once the final transcript replaces live.json, never keep speaker
        // identities that are absent from the saved transcript.
        let allSpeakers = Self.mergingSpeakers(existing: meeting.speakers, new: speakers)
        outcome.speakers = Self.speakersPresent(in: mergedSegments, from: allSpeakers)
        var labeled = meeting
        labeled.speakers = outcome.speakers ?? meeting.speakers

        // 3. Improve the notes off the accurate transcript (or write them for the
        //    first time if there was no draft).
        onProgress("Summarizing…")
        let accurateText = TranscriptFormatter.plainText(mergedSegments, speakers: labeled.speakers)
        // Optional transcript cleanup applies ONLY to the text we send the
        // summarizer — the saved transcript stays verbatim so the user's record
        // is faithful. Filler removal + personal dictionary substitutions.
        var summaryText = accurateText
        if AppSettings.fillerRemoval {
            summaryText = FillerWordRemover.clean(summaryText)
        }
        let dictionary = PersonalDictionaryStore()
        if dictionary.hasAny {
            summaryText = dictionary.apply(to: summaryText)
        }
        let finalOutcome: SummaryOutcome
        if let draft, priorSegments.isEmpty, sameContent(liveSegments, segments) {
            // The accurate transcript carries the same words as the live one, so the
            // draft already reflects them — skip a second model call.
            finalOutcome = .success(draft.text, provider: draft.provider)
        } else if draft != nil {
            // Improve quietly: the draft stays on screen (badge: "Draft · improving")
            // and is replaced atomically when the better version lands.
            finalOutcome = await MeetingSummarizer.summarize(
                meeting: labeled, transcript: summaryText, userNotes: userNotes)
        } else {
            // No draft — stream the sole pass into the notes.
            onSummary(.streaming(""))
            finalOutcome = await MeetingSummarizer.summarize(
                meeting: labeled, transcript: summaryText, userNotes: userNotes,
                onDelta: { onSummary(.streaming($0)) })
        }

        // Track the summary text we persisted so the naming stage can reuse it
        // instead of re-reading `archive.summary(for:)` from disk. Stays nil in
        // the edit-guard-blocked and failure paths, where we still must read the
        // (possibly user-edited) file to name the meeting accurately.
        var savedSummary: String?
        switch finalOutcome {
        case .success(let summary, let provider):
            // Edit-guard: if the user edited the draft while we were transcribing,
            // keep their version rather than clobbering it with the improvement.
            if archive.summary(for: id) == expectedSummary {
                // Annotate the notes with Zoom participants who joined but weren't
                // on the calendar invite — the call host can see who actually
                // showed up even when the invite didn't list them. Only when the
                // roster has names and extras exist; otherwise no-op.
                let annotated = AdditionalParticipantsAnnotator.annotation(
                    roster: roster,
                    attendees: meeting.attendees)
                    .map { summary + "\n\n" + $0 }
                    ?? summary
                do {
                    try archive.saveSummary(annotated, for: id, replacing: expectedSummary)
                    savedSummary = annotated
                    outcome.summaryProvider = provider
                } catch MeetingArchive.ArchiveError.summaryChanged {
                    // A user edit won the race; keep it.
                } catch {
                    outcome.state = .failed
                    notices.append("The summary could not be saved. Keep Ayrvo open and retry saving.")
                }
            }
        case .failure(let why):
            // Improvement failed but the draft (if any) stands.
            if draft == nil { notices.append(why) }
        }

        // Name the meeting from whatever notes we ended up with — the improvement,
        // the draft it fell back to, or the user's own edit — so a draft-only or
        // improve-failed meeting still gets a title, not just the happy path.
        // Reuse the just-saved summary when we have it; only re-read from disk
        // when the edit-guard blocked the save (user edited) or the pass failed.
        let finalText = savedSummary ?? archive.summary(for: id)
        if meeting.calendarEventTitle == nil, !finalText.isEmpty {
            onProgress("Naming the meeting…")
            outcome.generatedTitle = await MeetingTitleGenerator.generateTitle(
                summary: finalText, provider: outcome.summaryProvider ?? "apple")
        }

        onSummary(.done)
        let hasTranscriptContent = !mergedSegments.isEmpty
        outcome.notice = MeetingNotice.finalizedNotice(notices, hasTranscriptContent: hasTranscriptContent)
        AyrvoConsoleLog.pipeline(
            "run finished meeting=\(id.uuidString.prefix(8)) state=\(outcome.state)"
                + " segments=\(mergedSegments.count) speakers=\(outcome.speakers?.count ?? 0)"
                + (outcome.generatedTitle.map { " title=\"\($0)\"" } ?? ""))
        return outcome
    }

    /// True when two transcripts carry the same words (ignoring speaker labels and
    /// timing) — used to skip a redundant improvement pass.
    static func sameContent(_ a: [TranscriptSegment], _ b: [TranscriptSegment]) -> Bool {
        func signature(_ segs: [TranscriptSegment]) -> [String] {
            TranscriptText.wordTokens(segs.map(\.text).joined(separator: " "))
        }
        return signature(a) == signature(b)
    }

    /// Detect the exact live segment suffix promoted by ProcessMeetingUseCase.
    /// Never fuzzy-match text: two genuinely repeated utterances must not be
    /// discarded just because their words look similar.
    static func priorSegmentsExcludingPromotedLive(
        _ stored: [TranscriptSegment], live: [TranscriptSegment]
    ) -> [TranscriptSegment] {
        guard !live.isEmpty, stored.count >= live.count else { return stored }
        let suffix = Array(stored.suffix(live.count))
        guard let firstStored = suffix.first, let firstLive = live.first else {
            return stored
        }
        let shift = firstStored.start - firstLive.start
        guard shift >= 0 else { return stored }
        let matches = zip(suffix, live).allSatisfy { pair in
            let saved = pair.0
            let provisional = pair.1
            return saved.speakerID == provisional.speakerID
                && saved.text == provisional.text
                && abs(saved.start - provisional.start - shift) < 0.001
                && abs(saved.end - provisional.end - shift) < 0.001
        }
        return matches ? Array(stored.dropLast(live.count)) : stored
    }

    /// AAC containers can exist on disk with no decoded audio frames (~557 B).
    /// Test the decoded frame count rather than the file's byte size. Parakeet
    /// requires at least 300 ms of audio at 16 kHz.
    static func hasUsableAudio(at url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate.isFinite, sampleRate > 0 else { return false }
        return Double(file.length) / sampleRate >= 0.3
    }

    static func appendOffset(meeting: Meeting, prior: [TranscriptSegment]) -> TimeInterval {
        guard !prior.isEmpty else { return 0 }
        return max(meeting.duration, prior.map(\.end).max() ?? 0)
    }

    static func offsetSegments(
        _ segments: [TranscriptSegment], by offset: TimeInterval
    ) -> [TranscriptSegment] {
        segments.map { seg in
            var s = seg
            s.start += offset
            s.end += offset
            return s
        }
    }

    static func speakersPresent(
        in segments: [TranscriptSegment], from speakers: [Speaker]
    ) -> [Speaker] {
        let present = Set(segments.map(\.speakerID))
        return speakers.filter { present.contains($0.id) }
    }

    static func mergingSpeakers(existing: [Speaker], new: [Speaker]) -> [Speaker] {
        var merged = existing
        for speaker in new where !merged.contains(where: { $0.id == speaker.id }) {
            merged.append(speaker)
        }
        return merged
    }
}
