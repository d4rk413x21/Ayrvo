import AppKit
import SwiftUI

struct DebugSettings: View {
    var body: some View {
        Form {
            Section("Crashes") {
                CrashHistoryPanel()
            }
            Section("Logs") {
                AIDebugLogPanel()
                    .frame(minHeight: 320)
                HStack {
                    Text("Persisted logs are stored in the library’s Logs folder.")
                        .font(.ayrvo(11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Export Logs") { exportLogs() }
                        .buttonStyle(.plain)
                        .font(.ayrvo(11))
                        .foregroundStyle(Theme.blueberry)
                    Button("Reveal in Finder") { revealLogs() }
                        .buttonStyle(.plain)
                        .font(.ayrvo(11))
                        .foregroundStyle(Theme.blueberry)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func exportLogs() {
        let text = AyrvoFileLog.exportAll()
        guard !text.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ayrvo-logs-\(Int(Date().timeIntervalSince1970)).txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? FilePersistence.write(Data(text.utf8), to: url)
        }
    }

    private func revealLogs() {
        NSWorkspace.shared.activateFileViewerSelecting([AyrvoFileLog.logDirectoryURL])
    }
}
