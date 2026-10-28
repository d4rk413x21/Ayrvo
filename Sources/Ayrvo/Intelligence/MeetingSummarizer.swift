import Foundation

enum MeetingSummarizer {
    /// Routes to the user's chosen assistant first. Apple Intelligence is the default
    /// on-device path; Claude/Codex run first when selected. When `onDelta` is given,
    /// the chosen engine streams its markdown as it's generated.
    static func summarize(
        meeting: Meeting,
        transcript: String,
        userNotes: String = "",
        forceProvider: AIProvider? = nil,
        onDelta: (@Sendable (String) -> Void)? = nil
    ) async -> SummaryOutcome {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("The transcript was empty, so there is nothing to summarize.")
        }
        let templates = TemplateStore()
        let template = templates.template(named: meeting.templateName ?? AppSettings.defaultTemplate)
            ?? TemplateStore.builtins[0]
        let filled = TemplateRenderer.fill(template.body, meeting: meeting)
        var prompt = """
        Write meeting notes from the transcript provided as input, following this \
        template exactly (keep its headings; omit sections that would be empty):

        \(filled)
        """
        let trimmedNotes = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            prompt += """


            The meeting organizer took these notes during the call — treat them as \
            authoritative context and weave them into the summary where relevant:

            \(trimmedNotes)
            """
        }
        let systemPrompt = "You are Ayrvo, a meeting notetaker. Output only clean Markdown notes — no preamble, no code fences."

        // Each engine returns a summary, or nil if it's unavailable or errors (so we
        // fall through to the other). Claude records its error so a Claude-only
        // failure still surfaces a useful message.
        func apple() async -> SummaryOutcome? {
            guard AppleSummarizer.isAvailable else { return nil }
            let summary: String?
            if let onDelta {
                summary = try? await AppleSummarizer.summarizeStreaming(
                    transcript: transcript, filledTemplate: filled, onDelta: onDelta)
            } else {
                summary = try? await AppleSummarizer.summarize(
                    transcript: transcript, filledTemplate: filled)
            }
            if let summary {
                TokenUsageTracker.shared.record(
                    promptTokens: TokenUsageTracker.estimatedTokens(transcript + filled),
                    completionTokens: TokenUsageTracker.estimatedTokens(summary))
                return .success(summary, provider: "apple")
            }
            return nil
        }
        var claudeError: String?
        var codexError: String?
        var agentError: String?
        func claude() async -> SummaryOutcome? {
            guard ClaudeCLI.isInstalled else { return nil }
            do {
                let result: ClaudeCLI.RunResult
                if let onDelta {
                    // Fall back to the buffered run if the streaming path itself fails
                    // (e.g. a stream-json parse issue) — same CLI, same result shape.
                    do {
                        result = try await ClaudeCLI.stream(
                            prompt: prompt, stdin: transcript, systemPrompt: systemPrompt, onDelta: onDelta)
                    } catch {
                        result = try await ClaudeCLI.run(
                            prompt: prompt, stdin: transcript, systemPrompt: systemPrompt)
                    }
                } else {
                    result = try await ClaudeCLI.run(
                        prompt: prompt, stdin: transcript, systemPrompt: systemPrompt)
                }
                TokenUsageTracker.shared.record(
                    promptTokens: TokenUsageTracker.estimatedTokens(prompt + transcript),
                    completionTokens: TokenUsageTracker.estimatedTokens(result.text))
                return .success(result.text, provider: "claude")
            } catch {
                claudeError = error.localizedDescription
                AyrvoConsoleLog.intelligence("claude: \(error.localizedDescription)")
                return nil
            }
        }
        func codex() async -> SummaryOutcome? {
            guard CodexCLI.isReady else { return nil }
            do {
                let result = try await CodexCLI.run(
                    prompt: prompt, stdin: transcript, systemPrompt: systemPrompt)
                if let onDelta { onDelta(result.text) }
                TokenUsageTracker.shared.record(
                    promptTokens: TokenUsageTracker.estimatedTokens(prompt + transcript),
                    completionTokens: TokenUsageTracker.estimatedTokens(result.text))
                return .success(result.text, provider: "codex")
            } catch {
                codexError = error.localizedDescription
                AyrvoConsoleLog.intelligence("codex: \(error.localizedDescription)")
                return nil
            }
        }

        func agent(_ provider: AIProvider) async -> SummaryOutcome? {
            guard AgentCLI.isInstalled(provider) else { return nil }
            do {
                let text = try await AgentCLI.run(provider: provider, prompt: prompt, stdin: transcript, systemPrompt: systemPrompt)
                if let onDelta { onDelta(text) }
                TokenUsageTracker.shared.record(
                    promptTokens: TokenUsageTracker.estimatedTokens(prompt + transcript), completionTokens: TokenUsageTracker.estimatedTokens(text))
                return .success(text, provider: provider.rawValue)
            } catch {
                agentError = error.localizedDescription
                AyrvoConsoleLog.intelligence("\(provider.displayName): \(error.localizedDescription)")
                return nil
            }
        }

        func runProvider(_ provider: AIProvider) async -> SummaryOutcome? {
            switch provider {
            case .apple: await apple()
            case .claude: await claude()
            case .codex: await codex()
            case .opencode, .vibe: await agent(provider)
            }
        }

        if let forceProvider {
            let name = forceProvider.displayName
            AyrvoConsoleLog.intelligence("summarize: forced \(name)")
            if let outcome = await runProvider(forceProvider) {
                if case .success(_, let provider) = outcome {
                    AyrvoConsoleLog.intelligence("summarize: succeeded via \(provider)")
                }
                return outcome
            }
            switch forceProvider {
            case .apple:
                let reason = AppleSummarizer.unavailableReason ?? "Apple Intelligence is unavailable"
                return .failure("\(reason) — couldn't regenerate with Apple Intelligence.")
            case .claude:
                if let claudeError {
                    return .failure("Summary failed via Claude: \(claudeError)")
                }
                return .failure("Claude isn't ready — install the CLI and sign in, then try again.")
            case .codex:
                if let codexError {
                    return .failure("Summary failed via Codex: \(codexError)")
                }
                return .failure("Codex isn't ready — install the CLI and sign in, then try again.")
            case .opencode, .vibe:
                return .failure(agentError.map { "Summary failed via \(name): \($0)" }
                    ?? "\(name) isn't ready — install and configure its CLI, then try again.")
            }
        }

        let preferred = AppSettings.preferredAIProvider
        let cloudReady = preferred.isCloud && preferred.isAvailableForSummary
        let order = SummaryProviderOrder.providers(
            preferred: preferred, cloudReady: cloudReady,
            preferCloudOnly: AppSettings.preferClaudeSummaries)
        let orderNames = order.map(\.displayName)
        let modeLabel = preferred.isCloud && cloudReady
            ? (AppSettings.preferClaudeSummaries ? " · cloud-only" : " · cloud-first")
            : ""
        AyrvoConsoleLog.intelligence(
            "summarize: \(transcript.count) chars · preferred \(preferred.displayName)\(modeLabel)"
                + " · order: \(orderNames.joined(separator: " → "))")

        for provider in order {
            let name = provider.displayName
            AyrvoConsoleLog.intelligence("summarize: trying \(name)…")
            if let outcome = await runProvider(provider) {
                if case .success(_, let provider) = outcome {
                    AyrvoConsoleLog.intelligence("summarize: succeeded via \(provider)")
                }
                return outcome
            }
            AyrvoConsoleLog.intelligence("summarize: \(name) unavailable or failed")
        }

        if preferred == .apple {
            let reason = AppleSummarizer.unavailableReason ?? "Apple Intelligence is unavailable"
            AyrvoConsoleLog.intelligence("summarize: failed — \(reason)")
            return .failure("\(reason) — transcript saved, summary skipped. Enable Apple Intelligence and press Regenerate.")
        }
        if preferred == .codex, let codexError {
            AyrvoConsoleLog.intelligence("summarize: failed via Codex — \(codexError)")
            return .failure("Summary failed via Codex: \(codexError)")
        }
        if let agentError, preferred == .opencode || preferred == .vibe {
            return .failure("Summary failed via \(preferred.displayName): \(agentError)")
        }
        if let claudeError {
            AyrvoConsoleLog.intelligence("summarize: failed via Claude — \(claudeError)")
            return .failure("Summary failed via Claude: \(claudeError)")
        }
        let cloudName = preferred.displayName
        let reason = AppleSummarizer.unavailableReason ?? "Apple Intelligence is unavailable"
        AyrvoConsoleLog.intelligence("summarize: failed — \(reason); \(cloudName) not ready")
        return .failure("\(reason), and \(cloudName) isn't ready — transcript saved, summary skipped. Fix either one and press Regenerate.")
    }

}
