import Foundation

enum MeetingTitleGenerator {
    /// Cap on summary chars fed to the title-generation prompt — long notes would
    /// blow the context window without helping the title, and the CLIs charge
    /// by the token. Was a bare `2000` at both call sites; centralized here.
    private static let maxTitleSourceChars = 2000

    static func generateTitle(summary: String, provider: String) async -> String? {
        AyrvoConsoleLog.intelligence("title: generating via \(provider)")
        if provider == "apple", let title = try? await AppleSummarizer.generateTitle(fromSummary: summary) {
            AyrvoConsoleLog.intelligence("title: Apple Intelligence → \"\(title)\"")
            TokenUsageTracker.shared.record(
                promptTokens: TokenUsageTracker.estimatedTokens(summary), completionTokens: TokenUsageTracker.estimatedTokens(title))
            return cleaned(title)
        }
        if let selected = AIProvider(rawValue: provider), selected == .opencode || selected == .vibe,
           let text = try? await AgentCLI.run(
               provider: selected,
               prompt: prompt(summary: summary)) {
            TokenUsageTracker.shared.record(
                promptTokens: TokenUsageTracker.estimatedTokens(summary), completionTokens: TokenUsageTracker.estimatedTokens(text))
            return cleaned(text)
        }
        if provider == "codex", CodexCLI.isInstalled,
           let result = try? await CodexCLI.run(
               prompt: prompt(summary: summary)
           ) {
            AyrvoConsoleLog.intelligence("title: Codex → \"\(result.text)\"")
            TokenUsageTracker.shared.record(
                promptTokens: TokenUsageTracker.estimatedTokens(summary), completionTokens: TokenUsageTracker.estimatedTokens(result.text))
            return cleaned(result.text)
        }
        if ClaudeCLI.isInstalled,
           let result = try? await ClaudeCLI.run(
               prompt: prompt(summary: summary),
               model: "haiku"
           ) {
            AyrvoConsoleLog.intelligence("title: Claude → \"\(result.text)\"")
            TokenUsageTracker.shared.record(
                promptTokens: TokenUsageTracker.estimatedTokens(summary), completionTokens: TokenUsageTracker.estimatedTokens(result.text))
            return cleaned(result.text)
        }
        AyrvoConsoleLog.intelligence("title: no engine produced a title")
        return nil
    }

    static func prompt(summary: String) -> String {
        "Reply with only a specific 3–8 word title for the meeting with these notes, no quotes:\n\n\(String(summary.prefix(maxTitleSourceChars)))"
    }

    static func cleaned(_ title: String) -> String? {
        let t = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”.#"))
            .trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.count <= 80, !t.contains("\n") else { return nil }
        return t
    }
}
