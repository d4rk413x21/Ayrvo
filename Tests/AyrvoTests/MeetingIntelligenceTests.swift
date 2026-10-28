import Foundation
import Testing
@testable import Ayrvo

struct MeetingIntelligenceTests {
    @Test func testSummaryProviderOrderPreservesPreferencesAndFallbacks() {
        let cases: [(AIProvider, Bool, Bool, [AIProvider])] = [
            (.apple, false, false, [.apple, .claude, .codex]),
            (.apple, true, true, [.apple, .claude, .codex]),
            (.claude, true, true, [.claude, .codex]),
            (.claude, true, false, [.claude, .apple, .codex]),
            (.claude, false, true, [.apple, .claude, .codex]),
            (.codex, true, true, [.codex, .claude]),
            (.codex, true, false, [.codex, .apple, .claude]),
            (.codex, false, false, [.apple, .codex, .claude]),
            (.opencode, true, true, [.opencode, .codex]),
            (.opencode, true, false, [.opencode, .apple, .codex]),
            (.opencode, false, true, [.apple, .opencode, .codex]),
            (.vibe, true, true, [.vibe, .codex]),
            (.vibe, true, false, [.vibe, .apple, .codex]),
            (.vibe, false, true, [.apple, .vibe, .codex])
        ]
        for (preferred, ready, cloudOnly, expected) in cases {
            let actual = SummaryProviderOrder.providers(
                preferred: preferred, cloudReady: ready, preferCloudOnly: cloudOnly)
            #expect(actual == expected, "Provider: \(preferred), ready: \(ready), cloud-only: \(cloudOnly)")
        }
    }

    @Test func testTitleValidationRejectsEmptyLongAndMultilineResults() {
        for title in ["", "  \n ", "\"\"", String(repeating: "a", count: 81), "First line\nSecond line"] {
            #expect(MeetingTitleGenerator.cleaned(title) == nil)
        }
        #expect(MeetingTitleGenerator.cleaned("  #\"Sprint Planning\"  ") == "Sprint Planning")
        #expect(MeetingTitleGenerator.cleaned(String(repeating: "a", count: 80))?.count == 80)
    }

    @Test func testTitlePromptBoundsTheSummaryBeforeCallingAnyProvider() {
        let prefix = String(repeating: "a", count: 2000)
        let prompt = MeetingTitleGenerator.prompt(summary: prefix + "UNSENT_SUFFIX")
        #expect(prompt.hasSuffix(prefix))
        #expect(!prompt.contains("UNSENT_SUFFIX"))
        #expect(MeetingTitleGenerator.prompt(summary: "Notes").hasSuffix("Notes"))
    }
}
