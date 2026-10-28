import AppKit
import SwiftUI

struct AskStatusNotices: View {
    @Environment(\.colorScheme) private var scheme
    let preferredAIProvider: AIProvider
    let askDeliveryMode: AskDeliveryMode
    let available: Bool
    let launchFailed: Bool
    private var effectiveMode: AskDeliveryMode {
        preferredAIProvider.supportsApp ? askDeliveryMode : .cli
    }

    @ViewBuilder
    var body: some View {
        if launchFailed {
            Label(failureMessage, systemImage: "exclamationmark.triangle")
                .font(.ayrvo(11))
                .foregroundStyle(.orange)
        }

        if !available {
            unavailableNotice
        } else if preferredAIProvider == .apple {
            Text("Answers run on-device with your meeting summaries embedded in the prompt.")
                .font(.ayrvo(11))
                .foregroundStyle(Theme.tertiary(scheme))
        } else if effectiveMode == .app {
            Text(
                "Tip: once the ayrvo connector is set up, open \(preferredAIProvider.displayName) anytime — use $ayrvo to attach the connector."
            )
            .font(.ayrvo(11))
            .foregroundStyle(Theme.tertiary(scheme))
        } else {
            Text(
                "Answers run through the \(preferredAIProvider.displayName) CLI with meeting data included in the prompt. Tap the badge to switch assistants."
            )
            .font(.ayrvo(11))
            .foregroundStyle(Theme.tertiary(scheme))
        }
    }

    private var failureMessage: String {
        switch preferredAIProvider {
        case .apple: "Couldn't get an answer from Apple Intelligence."
        case .claude, .codex, .opencode, .vibe:
            switch effectiveMode {
            case .app: "Couldn't open \(preferredAIProvider.displayName)."
            case .cli: "Couldn't get an answer from \(preferredAIProvider.displayName)."
            }
        }
    }

    @ViewBuilder
    private var unavailableNotice: some View {
        switch preferredAIProvider {
        case .apple:
            VStack(alignment: .leading, spacing: 6) {
                Label("Apple Intelligence unavailable", systemImage: "exclamationmark.triangle")
                    .font(.ayrvo(12, .semibold))
                    .foregroundStyle(.orange)
                Text(AppleSummarizer.unavailableReason ?? "Turn on Apple Intelligence in System Settings, or pick a CLI assistant from the badge.")
                    .font(.ayrvo(11))
                    .foregroundStyle(Theme.secondary(scheme))
            }
            .padding(12)
            .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
        case .claude:
            cliUnavailableNotice(
                title: askDeliveryMode == .cli
                    ? (ClaudeCLI.isInstalled ? "Claude Code isn't logged in" : "Claude Code isn't installed")
                    : "Claude Desktop isn't installed",
                linkTitle: askDeliveryMode == .cli ? "Get Claude Code" : "Get Claude Desktop",
                linkURL: askDeliveryMode == .cli
                    ? URL(string: "https://claude.com/claude-code")!
                    : URL(string: "https://claude.ai/download")!
            )
        case .codex:
            cliUnavailableNotice(
                title: askDeliveryMode == .cli
                    ? (CodexCLI.isInstalled ? "Codex isn't logged in" : "Codex CLI isn't installed")
                    : "Codex app isn't installed",
                linkTitle: "Get Codex",
                linkURL: URL(string: "https://chatgpt.com/codex")!
            )
        case .opencode, .vibe:
            cliUnavailableNotice(
                title: "\(preferredAIProvider.displayName) CLI isn't installed",
                linkTitle: "Get \(preferredAIProvider.displayName)",
                linkURL: URL(string: preferredAIProvider == .opencode
                    ? "https://opencode.ai/docs/" : "https://docs.mistral.ai/vibe/code/overview")!)
        }
    }

    private func cliUnavailableNotice(title: String, linkTitle: String, linkURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle")
                .font(.ayrvo(12, .semibold))
                .foregroundStyle(.orange)
            HStack(spacing: 4) {
                Link(linkTitle, destination: linkURL)
                Text("— then configure the CLI and select it in Settings.")
                    .foregroundStyle(Theme.secondary(scheme))
            }
            .font(.ayrvo(11))
        }
        .padding(12)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }

}
