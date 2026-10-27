import SwiftUI

struct MeetingNotesEditor: View {
    @Environment(\.ayrvoActionColor) private var actionColor
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .tint(actionColor)
                    .keyboardShortcut("s", modifiers: .command)
            }
            .controlSize(.small)

            TextEditor(text: $text)
                .accessibilityLabel("Meeting notes")
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 200)
        }
    }
}
