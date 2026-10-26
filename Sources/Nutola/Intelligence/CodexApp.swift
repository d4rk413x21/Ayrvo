import AppKit
import Foundation

/// Deep-link launcher for the Codex desktop app.
enum CodexApp {
    static let maxPromptLength = 4000

    static var isInstalled: Bool {
        guard let probe = URL(string: "codex://") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
    }

    static func newThreadURL(prompt: String) -> URL? {
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/new"
        components.queryItems = [
            URLQueryItem(name: "prompt", value: String(prompt.prefix(maxPromptLength))),
        ]
        return components.url
    }

    @discardableResult
    static func openNewThread(prompt: String) -> Bool {
        guard let url = newThreadURL(prompt: prompt) else { return false }
        return NSWorkspace.shared.open(url)
    }
}

enum CodexPrompt {
    private static let defaultMeetingQuestion =
        "Give me a quick overview of this meeting — key decisions and action items."
    private static let defaultLibraryQuestion =
        "What have I been talking about across my recent meetings?"

    static func meeting(id: UUID, title: String, question: String) -> String {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Answer a question about my Ayrvo meeting "\(title)" (id: \(id.uuidString)) using the $ayrvo connector.

        \(q.isEmpty ? defaultMeetingQuestion : q)
        """
    }

    static func library(question: String) -> String {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Answer using my Ayrvo meetings via the $ayrvo connector:

        \(q.isEmpty ? defaultLibraryQuestion : q)
        """
    }

    static func live(question: String) -> String {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let ask = q.isEmpty ? "What's being discussed, and is there anything I should add or ask?" : q
        return "I'm in an Ayrvo meeting happening right now — use $ayrvo for the live transcript. \(ask)"
    }
}

enum CodexSetup {
    static var isAvailable: Bool { CodexCLI.isReady }

    @discardableResult
    static func addMCPServer(binary: String) -> Bool {
        CodexApp.openNewThread(prompt: """
        Connect Ayrvo to Codex as an MCP server so you can read my meeting library. Run:

        codex mcp add ayrvo -- "\(binary)" --mcp

        Then confirm with `codex mcp list`. Remind me to use $ayrvo (not @) to access meetings.
        """)
    }
}
