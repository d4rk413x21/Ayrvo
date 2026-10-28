import AppKit
import SwiftUI

struct MeetingLauncherView: View {
    let meeting: Meeting
    var initialQuestion: String?

    private var suggestions: [String] {
        MeetingAISuggestions.forMeeting(meeting)
    }
    var body: some View {
        AILauncherView(
            headline: "Ask about this meeting",
            subtitle: "Summarize, pull action items, or draft a follow-up.",
            suggestions: suggestions,
            contextMeeting: meeting,
            initialQuestion: initialQuestion,
            promptBuilder: { question in
                switch AppSettings.preferredAIProvider {
                case .apple, .opencode, .vibe:
                    ClaudeDesktopPrompt.meeting(
                        id: meeting.id, title: meeting.title, question: question)
                case .claude:
                    ClaudeDesktopPrompt.meeting(
                        id: meeting.id, title: meeting.title, question: question)
                case .codex:
                    CodexPrompt.meeting(
                        id: meeting.id, title: meeting.title, question: question)
                }
            }
        )
    }
}

struct LibraryLauncherView: View {
    @EnvironmentObject private var app: AppState

    private var recentMeetings: [Meeting] {
        app.store.meetings
            .filter { $0.state == .ready }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        AILauncherView(
            headline: "Hi \(UserGreeting.firstName), ask anything",
            subtitle: "Ask questions across all your recorded meetings.",
            suggestions: MeetingAISuggestions.library,
            recentMeetings: recentMeetings,
            promptBuilder: { question in
                switch AppSettings.preferredAIProvider {
                case .apple, .claude, .opencode, .vibe:
                    ClaudeDesktopPrompt.library(question: question)
                case .codex:
                    CodexPrompt.library(question: question)
                }
            },
            meetingPromptBuilder: { meeting, question in
                switch AppSettings.preferredAIProvider {
                case .apple, .claude, .opencode, .vibe:
                    ClaudeDesktopPrompt.meeting(
                        id: meeting.id, title: meeting.title, question: question)
                case .codex:
                    CodexPrompt.meeting(
                        id: meeting.id, title: meeting.title, question: question)
                }
            }
        )
        .navigationTitle("Ask")
    }
}

private enum UserGreeting {
    static var firstName: String {
        let full = NSFullUserName()
        guard !full.isEmpty else { return "there" }
        return full.split(separator: " ").first.map(String.init) ?? full
    }
}
