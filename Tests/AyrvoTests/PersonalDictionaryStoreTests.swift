import Foundation
import Testing
@testable import Ayrvo

final class PersonalDictionaryStoreTests {
    private var defaults: UserDefaults!
    private let suiteName = "test-personal-dict-\(UUID().uuidString)"

    init() {
        defaults = UserDefaults(suiteName: suiteName)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore() -> PersonalDictionaryStore {
        PersonalDictionaryStore(defaults: defaults, key: "test-personal-dict")
    }

    @Test func testEmptyStoreLeavesTextUntouched() {
        let store = makeStore()
        #expect(store.apply(to: "hello world") == "hello world")
    }

    @Test func testPhraseMatchExactReplacement() {
        let store = makeStore()
        store.add(.init(word: "AI", phraseMatch: "artificial intelligence", replacement: "AI"))
        #expect(store.apply(to: "We discussed artificial intelligence today.") == "We discussed AI today.")
    }

    @Test func testPhraseMatchCaseInsensitive() {
        let store = makeStore()
        store.add(.init(word: "AI", phraseMatch: "Artificial Intelligence", replacement: "AI"))
        #expect(store.apply(to: "we talked about artificial intelligence") == "we talked about AI")
    }

    @Test func testWordFuzzyReplacementCatchesTypo() {
        let store = makeStore()
        store.add(.init(word: "Violet", replacement: "Violet", minSimilarity: 0.85))
        #expect(store.apply(to: "I use Violt every day") == "I use Violet every day")
    }

    @Test func testWordOnlyEntryIsNoOp() {
        // A word with no replacement is a vocabulary hint — text unchanged.
        let store = makeStore()
        store.add(.init(word: "Violet", replacement: nil))
        #expect(store.apply(to: "I use Violet") == "I use Violet")
    }

    @Test func testDoesNotReplaceBelowSimilarityThreshold() {
        let store = makeStore()
        store.add(.init(word: "Violet", replacement: "Violet", minSimilarity: 0.95))
        // "banana" is far below 0.95 — must stay.
        #expect(store.apply(to: "I ate a banana") == "I ate a banana")
    }

    @Test func testRoundTripPersistence() {
        let store = makeStore()
        store.add(.init(word: "DD", phraseMatch: "DoorDash", replacement: "DoorDash"))
        let store2 = makeStore()
        #expect(store2.hasAny)
        #expect(store2.entries.first?.replacement == "DoorDash")
    }
}
