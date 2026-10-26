import Testing
@testable import Ayrvo

struct SystemAudioTapTests {
    @Test func testAggregateOwnerRecognizesCurrentAndLegacyNames() {
        #expect(SystemAudioTap.creatorPID(fromName: "Ayrvo Tap Aggregate (pid 123)") == 123)
        #expect(SystemAudioTap.creatorPID(fromName: "Nutola Tap Aggregate (pid 123)") == 123)
        #expect(SystemAudioTap.creatorPID(fromName: "Other device (pid 123)") == nil)
        #expect(SystemAudioTap.creatorPID(fromName: "Ayrvo Tap Aggregate (pid invalid)") == nil)
        #expect(SystemAudioTap.creatorPID(fromName: "Ayrvo Tap Aggregate (pid 123") == nil)
    }
}
