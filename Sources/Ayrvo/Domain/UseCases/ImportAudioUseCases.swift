import AVFAudio
import Foundation

/// Imports a local audio file (`.m4a`, `.mp4`, `.wav`, `.mp3`) as a new meeting,
/// then runs the full processing pipeline on it offline — transcription, speaker
/// diarization (when enabled), and summary generation.
///
/// The file is copied into the meeting's archive folder as `system.m4a`
/// (`AVAudioFile` reads by content, not extension, so any supported format
/// works), then `ProcessMeetingUseCase` is invoked as if the recording had just
/// stopped.
@MainActor
final class ImportAudioUseCase {
    private let meetingRepository: MeetingRepository
    private let folderRepository: FolderRepository
    private let processMeeting: ProcessMeetingUseCase
    private let settings: SettingsRepository

    init(meetingRepository: MeetingRepository,
         folderRepository: FolderRepository,
         processMeeting: ProcessMeetingUseCase,
         settings: SettingsRepository) {
        self.meetingRepository = meetingRepository
        self.folderRepository = folderRepository
        self.processMeeting = processMeeting
        self.settings = settings
    }

    /// Supported input extensions (lowercased, no leading dot).
    static let supportedExtensions: Set<String> = ["m4a", "mp4", "wav", "mp3"]

    /// Import `fileURL` as a new meeting titled `title` (or the file's name when
    /// nil), then process it. Returns the new meeting's id on success.
    /// - Parameters:
    ///   - fileURL: local URL of the audio file to import.
    ///   - title: optional title; defaults to the file's name without extension.
    func execute(fileURL: URL, title: String? = nil) async throws -> UUID {
        // Validate extension.
        let ext = fileURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw ImportError.unsupportedFormat(ext)
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ImportError.fileNotFound(fileURL.path)
        }

        // Create the meeting with a sensible title.
        let resolvedTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? title!
            : fileURL.deletingPathExtension().lastPathComponent
        var meeting = Meeting(title: resolvedTitle, createdAt: Date())
        meeting.state = .processing
        // Tag the source so the UI/pipeline can tell imported recordings apart
        // from live ones (matches Muesli's `source = audio_import` field).
        meeting.sourceApp = "Audio Import"

        // Claim a folder for the meeting if its title matches a folder rule.
        if let folder = folderRepository.folder(forTitle: resolvedTitle) {
            meeting.folderID = folder.id
        }

        // Create the archive folder and copy the audio in as `system.m4a`.
        let archive = meetingRepository.archive
        try archive.createFolder(for: meeting.id)
        let destURL = archive.systemURL(for: meeting.id)
        // Remove any stale file at the destination (a recycled id is the only way
        // this could exist).
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.copyItem(at: fileURL, to: destURL)

        // Read the duration so the UI/cost badge show something sensible.
        meeting.duration = Self.audioDuration(at: destURL)
        meetingRepository.upsert(meeting)

        // Run the standard processing pipeline. The pipeline reads `systemURL`
        // for the "Others" channel — perfect for an imported single-track file.
        // We pass the freshly-created meeting; ProcessMeetingUseCase re-reads
        // it from the repository so state stays consistent.
        await processMeeting.execute(meeting)
        return meeting.id
    }

    /// Quick duration probe without spinning up the full transcriber.
    private static func audioDuration(at url: URL) -> TimeInterval {
        if let seconds = try? Self.probeDuration(url), seconds > 0 {
            return seconds
        }
        return 0
    }

    private static func probeDuration(_ url: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }
}

enum ImportError: LocalizedError {
    case unsupportedFormat(String)
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported audio format: .\(ext). Use .m4a, .mp4, .wav, or .mp3."
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}
