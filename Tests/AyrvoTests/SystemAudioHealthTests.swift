import Foundation
import Testing
@testable import Ayrvo

struct SystemAudioHealthTests {
    private let start = Date(timeIntervalSince1970: 1000)

    @Test func testWaitingForFirstAudioNeverCountsAsAStall() {
        var health = SystemAudioHealth()
        #expect(health.stalledDuration(callbackCount: 0, at: start) == nil)
        #expect(health.stalledDuration(callbackCount: 0, at: start.addingTimeInterval(120)) == nil)
    }

    @Test func testGraceStartsOnlyAfterAnActiveCountStopsAdvancing() {
        var health = SystemAudioHealth()
        #expect(health.stalledDuration(callbackCount: 1, at: start) == nil)
        #expect(health.stalledDuration(callbackCount: 1, at: start.addingTimeInterval(5)) == 0)
        #expect(health.stalledDuration(callbackCount: 1, at: start.addingTimeInterval(14)) == 9)
        #expect(health.stalledDuration(callbackCount: 1, at: start.addingTimeInterval(15)) == 10)
    }

    @Test func testNewCallbacksClearAStall() {
        var health = SystemAudioHealth()
        _ = health.stalledDuration(callbackCount: 1, at: start)
        _ = health.stalledDuration(callbackCount: 1, at: start.addingTimeInterval(5))
        #expect(health.stalledDuration(callbackCount: 2, at: start.addingTimeInterval(10)) == nil)
        #expect(health.stalledDuration(callbackCount: 2, at: start.addingTimeInterval(15)) == 0)
    }

    @Test func testZeroCountClearsPreviousStallHistory() {
        var health = SystemAudioHealth()
        _ = health.stalledDuration(callbackCount: 1, at: start)
        _ = health.stalledDuration(callbackCount: 1, at: start.addingTimeInterval(5))
        #expect(health.stalledDuration(callbackCount: 0, at: start.addingTimeInterval(10)) == nil)
        #expect(health.stalledDuration(callbackCount: 1, at: start.addingTimeInterval(15)) == 0)
    }

    @Test func testRebuildResetsTheGraceWindow() {
        var health = SystemAudioHealth()
        _ = health.stalledDuration(callbackCount: 1, at: start)
        _ = health.stalledDuration(callbackCount: 1, at: start.addingTimeInterval(5))
        health.reset(callbackCount: 1)
        #expect(health.stalledDuration(callbackCount: 1, at: start.addingTimeInterval(100)) == 0)
        #expect(health.stalledDuration(callbackCount: 1, at: start.addingTimeInterval(110)) == 10)
    }
}
