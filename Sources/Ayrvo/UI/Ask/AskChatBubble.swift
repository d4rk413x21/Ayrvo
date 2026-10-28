import AppKit
import SwiftUI

struct AskChatBubble: View {
    let message: AskChatMessage

    @Environment(\.colorScheme) private var scheme
    @State private var isHovering = false
    @State private var didCopy = false

    private var canCopy: Bool {
        !message.isLoading && !message.text.isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 56) }

            bubbleContent
                .onHover { isHovering = $0 }

            if message.role == .assistant { Spacer(minLength: 56) }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if message.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Asking \(AppSettings.preferredAIProvider.displayName)…")
                            .font(.ayrvo(13))
                            .foregroundStyle(Theme.secondary(scheme))
                    }
                } else if message.role == .assistant {
                    MarkdownText(markdown: message.text, style: .document)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(message.text)
                        .font(.ayrvo(14))
                        .foregroundStyle(Theme.heading(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .padding(.top, canCopy && isHovering ? 4 : 0)
            .background(
                message.isError
                    ? Color.orange.opacity(scheme == .dark ? 0.14 : 0.1)
                    : Theme.bubble(scheme, isSelf: message.role == .user),
                in: RoundedRectangle(cornerRadius: 14)
            )

            if canCopy, isHovering {
                copyButton
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var copyButton: some View {
        Button(action: copyText) {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondary(scheme))
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(scheme == .dark ? 0.22 : 0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .help(didCopy ? "Copied" : "Copy")
        .accessibilityLabel("Copy message")
        .accessibilityValue(didCopy ? "Copied" : "")
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
    }
}
