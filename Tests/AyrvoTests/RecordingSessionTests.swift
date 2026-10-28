import Foundation
import Testing
@testable import Ayrvo

/// Session lifecycle checks that do not open audio devices.
@MainActor
final class RecordingSessionTests {
    private var tmp: URL!
    private var archive: MeetingArchive!

    init() {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ayrvo-session-tests-\(UUID().uuidString)")
        archive = MeetingArchive(root: tmp)
    }

    isolated deinit {
        try? FileManager.default.removeItem(at: tmp)
    }

    // #83: a session stopped with no captured audio (both files missing → 0
    // bytes) must surface a non-empty `stopNotice` so the UI can warn the user.
    @Test func testZeroBytesProducesNotice() async {
        let id = UUID()
        try? archive.createFolder(for: id)
        let session = RecordingSession(meetingID: id, archive: archive)
        // Don't call start() — no audio capture is set up. The mic/system URLs
        // point at files that don't exist, so attributesOfItem throws → 0 bytes.
        await session.stopAsync()
        #expect(session.stopNotice != nil, "stopNotice must be set when both capture files are empty")
        #expect(session.stopNotice == "No audio was captured — check your microphone and system audio settings")
    }

}
