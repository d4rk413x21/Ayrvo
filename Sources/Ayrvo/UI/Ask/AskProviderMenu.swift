import AppKit
import SwiftUI

struct AskProviderMenu: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsKey.preferredAIProvider) private var preferredAIProvider: AIProvider = .apple
    @AppStorage(SettingsKey.askDeliveryMode) private var askDeliveryMode: AskDeliveryMode = .cli
    @AppStorage(SettingsKey.askMaxTurns) private var askMaxTurns = 5
    let deliveryModeAvailability: [AskDeliveryMode: Bool]
    private var effectiveMode: AskDeliveryMode {
        preferredAIProvider.supportsApp ? askDeliveryMode : .cli
    }

    @ViewBuilder
    var body: some View {
        Menu {
            Section("Assistant") {
                ForEach(AIProvider.askChoices) { provider in
                    Button {
                        preferredAIProvider = provider
                    } label: {
                        if preferredAIProvider == provider {
                            Label(provider.displayName, systemImage: "checkmark")
                        } else {
                            Text(provider.displayName)
                        }
                    }
                }
            }
            Section("How to answer") {
                ForEach(preferredAIProvider.deliveryModes) { mode in
                    Button {
                        askDeliveryMode = mode
                    } label: {
                        if effectiveMode == mode {
                            Label(mode.displayName, systemImage: "checkmark")
                        } else {
                            Text(mode.displayName)
                        }
                    }
                    .disabled(!(deliveryModeAvailability[mode] ?? false))
                }
            }
            .disabled(preferredAIProvider == .apple)

            if askDeliveryMode == .cli, preferredAIProvider != .apple {
                Section("Context") {
                    Button("More tool rounds (\(askMaxTurns) → \(min(askMaxTurns + 2, 15)))") {
                        askMaxTurns = min(askMaxTurns + 2, 15)
                    }
                    .disabled(askMaxTurns >= 15)
                    Button("Fewer tool rounds (\(askMaxTurns) → \(max(askMaxTurns - 2, 3)))") {
                        askMaxTurns = max(askMaxTurns - 2, 3)
                    }
                    .disabled(askMaxTurns <= 3)
                    Button("Open Intelligence settings…") { openSettings() }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: badgeIcon)
                    .font(.system(size: 10, weight: .semibold))
                Text(badgeLabel)
                    .font(.ayrvo(11, .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.55)
            }
            .foregroundStyle(Theme.secondary(scheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Change assistant or how questions are answered")
        .accessibilityLabel("Change assistant or how questions are answered")
    }

    private var badgeIcon: String {
        switch preferredAIProvider {
        case .apple: "apple.intelligence"
        case .opencode, .vibe: "terminal"
        case .codex where askDeliveryMode == .cli: "terminal"
        case .claude where askDeliveryMode == .cli: "terminal"
        default: "sparkles"
        }
    }

    private var badgeLabel: String {
        switch preferredAIProvider {
        case .apple:
            return "Apple Intelligence"
        case .claude, .codex, .opencode, .vibe:
            if effectiveMode == .cli {
                return "\(preferredAIProvider.displayName) · CLI"
            }
            return preferredAIProvider.displayName
        }
    }

}
