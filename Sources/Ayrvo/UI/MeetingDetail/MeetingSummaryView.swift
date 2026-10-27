import SwiftUI

struct MeetingSummaryView: View {
    @Environment(\.colorScheme) private var scheme
    let markdown: String
    let progress: SummaryProgress?
    let canEdit: Bool
    let templates: TemplateStore
    let currentProvider: String?
    let onEdit: () -> Void
    let onRegenerate: (String?, AIProvider?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let progress {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small).scaleEffect(0.6)
                        Text(progress == .improving ? "Draft · improving" : "Writing…")
                            .font(.ayrvo(11))
                            .foregroundStyle(Theme.tertiary(scheme))
                    }
                }
                Spacer()
                notesEditMenu
            }
            .padding(.bottom, 8)

            if !markdown.isEmpty {
                Text("Enhanced notes")
                    .font(.ayrvo(12, .semibold))
                    .foregroundStyle(Theme.secondary(scheme))
                    .padding(.bottom, 8)
            }

            MarkdownText(markdown: markdown, style: .document)
        }
    }

    private var notesEditMenu: some View {
        Menu {
            Button {
                onEdit()
            } label: {
                Label("Edit notes", systemImage: "pencil")
            }
            .disabled(!canEdit)

            Menu("Regenerate") {
                ForEach(templates.list()) { template in
                    Button(template.name) {
                        onRegenerate(template.name, nil)
                    }
                }
                Divider()
                Button("With current template") {
                    onRegenerate(nil, nil)
                }
                if !regenerateProviderChoices.isEmpty {
                    Divider()
                    Menu("With another AI") {
                        ForEach(regenerateProviderChoices) { provider in
                            Button(provider.displayName) {
                                onRegenerate(nil, provider)
                            }
                            .disabled(!provider.isAvailableForSummary)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.tertiary(scheme))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var regenerateProviderChoices: [AIProvider] {
        AIProvider.allCases.filter { $0.rawValue != currentProvider }
    }
}
