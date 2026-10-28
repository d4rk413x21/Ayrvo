import AppKit
import SwiftUI

struct AskComposer: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.ayrvoActionColor) private var actionColor
    @Binding var input: String
    let focus: FocusState<Bool>.Binding
    let available: Bool
    let isAnswering: Bool
    let didSaveRecipe: Bool
    let preferredAIProvider: AIProvider
    let effectiveMode: AskDeliveryMode
    let deliveryModeAvailability: [AskDeliveryMode: Bool]
    let launchTyped: () -> Void
    let stopAnswering: () -> Void
    let saveCurrentInputAsRecipe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Ask anything…", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.ayrvo(15))
                .lineLimit(3...8)
                .focused(focus)
                .disabled(!available || isAnswering)
                .onSubmit(launchTyped)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 10)

            HStack(alignment: .center, spacing: 10) {
                AskProviderMenu(deliveryModeAvailability: deliveryModeAvailability)
                saveAsRecipeButton
                Spacer(minLength: 8)
                submitButton
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(composeBorder, lineWidth: focus.wrappedValue ? 1.5 : 1)
        }
        .shadow(
            color: actionColor.opacity(focus.wrappedValue && available ? 0.18 : 0),
            radius: focus.wrappedValue ? 16 : 0,
            y: focus.wrappedValue ? 4 : 0
        )
        .animation(.easeOut(duration: 0.18), value: focus.wrappedValue)
    }

    private var composeBorder: some ShapeStyle {
        if focus.wrappedValue, available {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [actionColor.opacity(0.65), Theme.blueberry(scheme).opacity(0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(Color.primary.opacity(scheme == .dark ? 0.14 : 0.1))
    }

    private var submitButton: some View {
        Group {
            if isAnswering {
                Button(action: stopAnswering) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(actionColor))
                }
                .buttonStyle(.plain)
                .help("Stop")
                .accessibilityLabel("Stop")
            } else {
                let canSubmit = available && !input.trimmingCharacters(in: .whitespaces).isEmpty
                Button(action: launchTyped) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(canSubmit ? actionColor : Color.secondary.opacity(0.25))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .help(submitHelp)
                .accessibilityLabel("Send question")
            }
        }
    }

    private var submitHelp: String {
        switch preferredAIProvider {
        case .apple: "Answer with Apple Intelligence"
        case .claude, .codex, .opencode, .vibe:
            switch effectiveMode {
            case .cli: "Answer with \(preferredAIProvider.displayName) CLI"
            case .app: "Open in \(preferredAIProvider.displayName)"
            }
        }
    }

    /// Small "Save as recipe" affordance next to the submit button. Only shown
    /// when the user has typed something they could save; the checkmark flips
    /// briefly after a save to confirm. Kept deliberately understated so it
    /// doesn't compete with the submit arrow.
    private var saveAsRecipeButton: some View {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        let canSave = !trimmed.isEmpty && !isAnswering
        return Button(action: saveCurrentInputAsRecipe) {
            Image(systemName: didSaveRecipe ? "checkmark" : "bookmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(didSaveRecipe ? actionColor : Theme.secondary(scheme))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0)
        .help("Save as recipe")
        .accessibilityLabel("Save as recipe")
        .animation(.easeOut(duration: 0.18), value: didSaveRecipe)
    }

}
