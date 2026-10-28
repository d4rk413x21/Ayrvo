import Foundation

enum MeetingAudioTranscriber {
    struct Channels: Sendable {
        let microphone: TranscriptionOutput?
        let system: TranscriptionOutput?
        let notices: [String]
    }

    static func transcribe(
        microphoneURL: URL?, systemURL: URL?, locale meetingLocale: Locale?,
        onProgress: @escaping @Sendable (String) -> Void
    ) async -> Channels {
        var notices: [String] = []
        onProgress("Preparing speech model…")
        try? await Transcriber.ensureModel(progress: { fraction in
            onProgress("Downloading speech model… \(Int(fraction * 100))%")
        })

        var micOut: TranscriptionOutput?
        var systemOut: TranscriptionOutput?
        if let micURL = microphoneURL {
            onProgress("Transcribing your microphone…")
            do {
                micOut = try await Transcriber.transcribeFile(
                    at: micURL, selected: AppSettings.transcriptionModel, locale: meetingLocale)
            } catch {
                AyrvoConsoleLog.pipeline("mic batch ASR unavailable — \(error.localizedDescription)")
                // Parakeet may decode remote audio successfully but return an empty
                // hypothesis for a quiet microphone track. Try the already-installed
                // Apple Speech model on the mic only; never change the remote model.
                if AppSettings.transcriptionModel != .apple {
                    do {
                        onProgress("Retrying microphone with Apple Speech…")
                        micOut = try await Transcriber.transcribeFile(
                            at: micURL, selected: .apple, locale: meetingLocale)
                        AyrvoConsoleLog.pipeline(
                            "mic recovered via Apple Speech (\(micOut?.segments.count ?? 0) segments)")
                    } catch {
                        AyrvoConsoleLog.pipeline(
                            "mic Apple fallback unavailable — \(error.localizedDescription)")
                    }
                }
                if micOut == nil {
                    notices.append(MeetingNotice.micTranscriptionFailed)
                }
            }
        }
        if let systemURL = systemURL {
            onProgress("Transcribing the call audio…")
            do { systemOut = try await Transcriber.transcribeFile(at: systemURL, selected: AppSettings.transcriptionModel, locale: meetingLocale) }
            catch {
                notices.append(MeetingNotice.callTranscriptionFailed)
                AyrvoConsoleLog.pipeline("system transcription failed — \(error.localizedDescription)")
            }
        }

        return Channels(microphone: micOut, system: systemOut, notices: notices)
    }
}
