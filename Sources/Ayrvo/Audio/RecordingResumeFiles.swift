import Foundation

/// Retains the previous capture until the replacement has actually started.
struct RecordingResumeFiles {
    private let backup: URL
    private var entries: [(source: URL, saved: URL, hadOriginal: Bool)] = []

    init(archive: MeetingArchive, meetingID: UUID) throws {
        let folder = archive.folder(for: meetingID)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw MeetingArchive.ArchiveError.meetingDeleted
        }
        backup = folder.appendingPathComponent(".resume-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        do {
            for name in ["mic.m4a", "system.m4a", "live.json", "speaker_events.json", "zoom_roster.json", "platform_participants.json"] {
                let source = folder.appendingPathComponent(name)
                let saved = backup.appendingPathComponent(name)
                if let pending = FilePersistence.failure(at: source) {
                    try pending.data.write(to: saved, options: .atomic)
                    entries.append((source, saved, true))
                    if FileManager.default.fileExists(atPath: source.path) { try FileManager.default.removeItem(at: source) }
                } else {
                    let exists = FileManager.default.fileExists(atPath: source.path)
                    if exists { try FileManager.default.moveItem(at: source, to: saved) }
                    entries.append((source, saved, exists))
                }
            }
            for entry in entries { FilePersistence.discard(entry.source) }
        } catch {
            do { try rollback() }
            catch { PersistenceStatus.record(error) }
            throw error
        }
    }

    func commit() throws {
        try FileManager.default.removeItem(at: backup)
    }

    mutating func rollback() throws {
        while let entry = entries.first {
            if entry.hadOriginal && !FileManager.default.fileExists(atPath: entry.saved.path) {
                throw CocoaError(.fileNoSuchFile)
            }
            if FileManager.default.fileExists(atPath: entry.source.path) {
                try FileManager.default.removeItem(at: entry.source)
            }
            if entry.hadOriginal { try FileManager.default.moveItem(at: entry.saved, to: entry.source) }
            FilePersistence.discard(entry.source)
            entries.removeFirst()
        }
        try FileManager.default.removeItem(at: backup)
    }
}
