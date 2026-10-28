import AppKit
import SwiftUI

struct IntelligenceSettings: View {
    @Environment(\.ayrvoActionColor) private var actionColor
    @State private var claudeInstalled = false
    @State private var claudeLoggedIn = false
    @State private var claudeCodeAvailable = false
    @State private var codexInstalled = false
    @State private var codexLoggedIn = false
    @State private var codexSetupAvailable = false
    @State private var claudeVersion: String?
    @State private var codexVersion: String?
    @State private var additionalInstalled: [AIProvider: Bool] = [:]
    @AppStorage(SettingsKey.preferClaudeSummaries) private var preferClaudeSummaries = false
    @AppStorage(SettingsKey.preferredAIProvider) private var preferredAIProvider: AIProvider = .apple
    @AppStorage(SettingsKey.askDeliveryMode) private var askDeliveryMode: AskDeliveryMode = .cli
    @AppStorage(SettingsKey.askMaxTurns) private var askMaxTurns = 5

    /// #15 — Path to the Claude Desktop MCP config file, centralized so the
    /// path string and the derived URL stay in one place.
    private static let claudeDesktopConfigPath =
        "Library/Application Support/Claude/claude_desktop_config.json"

    private var cloudAssistantReady: Bool {
        switch preferredAIProvider {
        case .apple: AppleSummarizer.isAvailable
        case .claude: claudeInstalled && claudeLoggedIn
        case .codex: codexInstalled && codexLoggedIn
        case .opencode, .vibe: additionalInstalled[preferredAIProvider] == true
        }
    }

    var body: some View {
        Form {
            Section("On-device") {
                statusRow(
                    ok: AppleSummarizer.isAvailable,
                    title: "Apple Intelligence",
                    detail: AppleSummarizer.isAvailable
                        ? "Summaries, titles, and meeting chat run entirely on this Mac."
                        : (AppleSummarizer.unavailableReason ?? "Unavailable"))
                statusRow(
                    ok: true,
                    title: "Speech transcription",
                    detail: "Apple's on-device speech model. English and Brazilian Portuguese are prepared automatically; other system languages download on first use.")
            }

            Section("CLI versions") {
                versionRow(title: "Claude Code", version: claudeVersion, installed: claudeInstalled)
                versionRow(title: "Codex CLI", version: codexVersion, installed: codexInstalled)
            }

            Section("Your Claude account") {
                statusRow(
                    ok: claudeInstalled && claudeLoggedIn,
                    title: claudeInstalled
                        ? (claudeLoggedIn ? "Claude Code — connected" : "Claude Code — not logged in")
                        : "Claude Code — not installed",
                    detail: claudeInstalled
                        ? (claudeLoggedIn
                            ? "Used as a fallback when a meeting is too long for the on-device model to summarize. Billed to your own Claude plan."
                            : "Open Claude Code and log in once to enable this.")
                        : "Install from claude.com/claude-code to unlock long-meeting summaries when Apple Intelligence can't fit the transcript.")
                if preferredAIProvider.isCloud {
                    Toggle("Always use \(preferredAIProvider.displayName) for summaries", isOn: $preferClaudeSummaries)
                        .disabled(!cloudAssistantReady)
                    Text("On: every summary via \(preferredAIProvider.displayName). Off: \(preferredAIProvider.displayName) first, with Apple Intelligence only if it fails.")
                        .font(.ayrvo(11))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Ask AI") {
                Picker("Assistant", selection: $preferredAIProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                Text("Choose which assistant Ayrvo uses for meeting chat and summaries.")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)

                if preferredAIProvider.isCloud {
                    if preferredAIProvider.supportsApp {
                        Picker("Answer with", selection: $askDeliveryMode) {
                            ForEach(preferredAIProvider.deliveryModes) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        Text(askDeliveryMode.detail)
                            .font(.ayrvo(11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Answers are shown here using your CLI's configured account and model.")
                            .font(.ayrvo(11))
                            .foregroundStyle(.secondary)
                    }

                    if preferredAIProvider.supportsApp && askDeliveryMode == .cli {
                        Stepper("Context rounds: \(askMaxTurns)", value: $askMaxTurns, in: 3...15)
                        Text("How many tool rounds the CLI can use to search and read meetings. Raise this for long transcripts.")
                            .font(.ayrvo(11))
                            .foregroundStyle(.secondary)
                    }
                }

                switch preferredAIProvider {
                case .apple:
                    statusRow(
                        ok: AppleSummarizer.isAvailable,
                        title: "Apple Intelligence",
                        detail: AppleSummarizer.isAvailable
                            ? "Summaries and titles run entirely on this Mac. Pick Claude or Codex above to ask about meetings in chat."
                            : (AppleSummarizer.unavailableReason ?? "Unavailable on this Mac."))
                case .codex:
                    statusRow(
                        ok: codexInstalled && codexLoggedIn,
                        title: aiProviderStatusDescription(
                            provider: .codex, installed: codexInstalled, loggedIn: codexLoggedIn),
                        detail: aiProviderStatusDescription(
                            provider: .codex, installed: codexInstalled, loggedIn: codexLoggedIn,
                            forDetail: true))
                case .claude:
                    statusRow(
                        ok: claudeInstalled && claudeLoggedIn,
                        title: aiProviderStatusDescription(
                            provider: .claude, installed: claudeInstalled, loggedIn: claudeLoggedIn),
                        detail: aiProviderStatusDescription(
                            provider: .claude, installed: claudeInstalled, loggedIn: claudeLoggedIn,
                            forDetail: true))
                case .opencode, .vibe:
                    statusRow(
                        ok: additionalInstalled[preferredAIProvider] == true,
                        title: aiProviderStatusDescription(provider: preferredAIProvider,
                            installed: additionalInstalled[preferredAIProvider] == true, loggedIn: false),
                        detail: aiProviderStatusDescription(provider: preferredAIProvider,
                            installed: additionalInstalled[preferredAIProvider] == true, loggedIn: false, forDetail: true))
                }
            }

            if preferredAIProvider.supportsApp {
                Section("Connect \(preferredAIProvider.displayName) to your meetings") {
                    connectAIContent
                }
            }

            Section("Token usage") {
                TokenUsageChart()
                Text("Approximate tokens used by summaries, titles, and Ask AI over the last 14 days. Counts are estimated (~4 chars/token) since the CLIs don't report billing-grade usage.")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Clear history", role: .destructive) {
                        TokenUsageTracker.shared.clear()
                    }
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            claudeInstalled = ClaudeCLI.isInstalled
            codexInstalled = CodexCLI.isInstalled
            claudeCodeAvailable = ClaudeCode.isAvailable
            codexSetupAvailable = CodexSetup.isAvailable
            Task.detached {
                let loggedIn = ClaudeCLI.isLoggedIn()
                let codexIn = CodexCLI.isLoggedIn()
                let claudeV = ClaudeCLI.version()
                let codexV = CodexCLI.version()
                var installed: [AIProvider: Bool] = [:]
                for provider in [AIProvider.opencode, .vibe] {
                    installed[provider] = AgentCLI.resolveBlocking(provider) != nil
                }
                let additional = installed
                await MainActor.run {
                    claudeLoggedIn = loggedIn
                    codexLoggedIn = codexIn
                    claudeVersion = claudeV
                    codexVersion = codexV
                    additionalInstalled = additional
                    logAssistantStatus()
                }
            }
        }
        .onChange(of: preferredAIProvider) { logAssistantStatus() }
        .onChange(of: preferClaudeSummaries) { logAssistantStatus() }
    }

    private func logAssistantStatus() {
        AyrvoConsoleLog.intelligence("── Intelligence settings ──")
        AyrvoConsoleLog.intelligence("Assistant: \(preferredAIProvider.displayName)")
        AyrvoConsoleLog.intelligence("Always use cloud for summaries: \(preferClaudeSummaries) (cloud-only when on)")
        if AppleSummarizer.isAvailable {
            AyrvoConsoleLog.intelligence("Apple Intelligence: available")
        } else {
            AyrvoConsoleLog.intelligence("Apple Intelligence: \(AppleSummarizer.unavailableReason ?? "unavailable")")
        }
        AyrvoConsoleLog.intelligence(
            "Claude: \(claudeInstalled ? "installed" : "not installed")"
                + (claudeInstalled ? ", \(claudeLoggedIn ? "logged in" : "not logged in")" : ""))
        AyrvoConsoleLog.intelligence(
            "Codex: \(codexInstalled ? "installed" : "not installed")"
                + (codexInstalled ? ", \(codexLoggedIn ? "logged in" : "not logged in")" : "")
                + ", ready: \(CodexCLI.isReady)")
    }

    // #13 — Centralizes the "connected / not logged in / not installed" status
    // strings that were previously inlined in the Ask AI switch block.
    private func aiProviderStatusDescription(
        provider: AIProvider, installed: Bool, loggedIn: Bool, forDetail: Bool = false
    ) -> String {
        switch provider {
        case .apple:
            if forDetail {
                return AppleSummarizer.isAvailable
                    ? "Summaries and titles run entirely on this Mac. Pick Claude or Codex above to ask about meetings in chat."
                    : (AppleSummarizer.unavailableReason ?? "Unavailable on this Mac.")
            }
            return AppleSummarizer.isAvailable ? "Apple Intelligence — ready" : "Apple Intelligence — unavailable"
        case .claude:
            if !installed {
                return forDetail
                    ? "Install from claude.com/claude-code to ask about your meetings through Claude."
                    : "Claude Code — not installed"
            }
            if !loggedIn {
                return forDetail
                    ? "Open Claude Code and log in once to enable this."
                    : "Claude Code — not logged in"
            }
            return forDetail
                ? "Ask about your meetings from Claude once the ayrvo connector is set up."
                : "Claude Code — connected"
        case .codex:
            if !installed {
                return forDetail
                    ? "Install from chatgpt.com/codex to ask about your meetings through Codex."
                    : "Codex CLI — not installed"
            }
            if !loggedIn {
                return forDetail
                    ? "Run `codex login` once to enable this."
                    : "Codex CLI — not logged in"
            }
            return forDetail
                ? "Ask about your meetings from Codex once the ayrvo connector is set up."
                : "Codex CLI — connected"
        case .opencode, .vibe:
            if forDetail {
                let command = provider == .opencode ? "opencode" : "vibe"
                return "Run `\(command)` in Terminal to configure its account and model. Ayrvo uses that configuration; account errors are reported when a request runs."
            }
            return "\(provider.displayName) CLI — \(installed ? "installed" : "not installed")"
        }
    }

    private var binaryPath: String {
        Bundle.main.executablePath ?? "/Applications/Ayrvo.app/Contents/MacOS/Ayrvo"
    }

    private var mcpCommand: String {
        "claude mcp add ayrvo -s user -- \"\(binaryPath)\" --mcp"
    }

    private var mcpDesktopConfigSnippet: String {
        """
        {
          "mcpServers": {
            "ayrvo": {
              "command": "\(binaryPath)",
              "args": ["--mcp"]
            }
          }
        }
        """
    }

    private var claudeDesktopConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(Self.claudeDesktopConfigPath)
    }

    private var codexConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml")
    }

    private var codexMCPCommand: String {
        "codex mcp add ayrvo -- \"\(binaryPath)\" --mcp"
    }

    @ViewBuilder
    private var connectAIContent: some View {
        switch preferredAIProvider {
        case .apple, .opencode, .vibe:
            EmptyView()
        case .claude:
            VStack(alignment: .leading, spacing: 8) {
                Text("Give Claude access to your meeting library. Everything stays local — the connector just reads Ayrvo's on-disk library.")
                    .font(.ayrvo(12))

                HStack {
                    Button("Add to Claude Code") { ClaudeCode.addMCPServer(binary: binaryPath) }
                        .buttonStyle(.borderedProminent)
                        .tint(actionColor)
                    Button("Add to Claude Desktop") {
                        ClaudeCode.addToClaudeDesktop(
                            binary: binaryPath, configPath: claudeDesktopConfigURL.path)
                    }
                }
                .controlSize(.small)
                .disabled(!claudeCodeAvailable)

                Text(claudeCodeAvailable
                     ? "Claude Code runs the setup for you and confirms it worked."
                     : "Install Claude Desktop (it includes Claude Code) to use these buttons.")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)

                DisclosureGroup("Prefer to run it yourself?") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(mcpCommand)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(mcpCommand, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .help("Copy the claude mcp add command")
                            .accessibilityLabel("Copy the claude mcp add command")
                        }
                        Text("Or add the \"ayrvo\" entry to Claude Desktop's config (merge into any existing \"mcpServers\"):")
                            .font(.ayrvo(11))
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Copy JSON") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(mcpDesktopConfigSnippet, forType: .string)
                            }
                            Button("Reveal config in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([claudeDesktopConfigURL])
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(.top, 4)
                }
                .font(.ayrvo(11))
            }
        case .codex:
            VStack(alignment: .leading, spacing: 8) {
                Text("Give Codex access to your meeting library. Everything stays local — the connector just reads Ayrvo's on-disk library. Use $ayrvo (not @) to attach it.")
                    .font(.ayrvo(12))

                HStack {
                    Button("Add with Codex") { CodexSetup.addMCPServer(binary: binaryPath) }
                        .buttonStyle(.borderedProminent)
                        .tint(actionColor)
                        .disabled(!codexSetupAvailable)
                }
                .controlSize(.small)

                Text(codexSetupAvailable
                     ? "Codex runs the setup and confirms it worked."
                     : "Install and log in to Codex CLI to use this button.")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)

                DisclosureGroup("Prefer to run it yourself?") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(codexMCPCommand)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(codexMCPCommand, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .help("Copy the codex mcp add command")
                            .accessibilityLabel("Copy the codex mcp add command")
                        }
                        Button("Reveal config in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([codexConfigURL])
                        }
                        .controlSize(.small)
                    }
                    .padding(.top, 4)
                }
                .font(.ayrvo(11))
            }
        }
    }

    private func statusRow(ok: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            StatusDot(ok: ok)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ayrvo(12, .medium))
                Text(detail).font(.ayrvo(11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    /// #97 — read-only row showing the installed CLI version (or "not installed").
    private func versionRow(title: String, version: String?, installed: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            StatusDot(ok: installed)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ayrvo(12, .medium))
                Text(installed ? (version ?? "Installed") : "Not installed")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
