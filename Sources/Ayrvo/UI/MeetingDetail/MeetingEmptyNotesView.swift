import SwiftUI

struct MeetingEmptyNotesView: View {
    let meeting: Meeting
    let hasTranscript: Bool
    let hasSideNotes: Bool
    @Binding var showSideNotes: Bool
    let canContinueRecording: Bool
    let resumesInFooter: Bool
    let joinLabel: String?
    let onResume: () -> Void
    let onRetry: () -> Void
    let onShowTranscript: () -> Void

    var body: some View {
        EmptyStateView(
            title: presentation?.title ?? "No notes yet",
            message: emptyNotesMessage,
            actionTitle: primaryTitle,
            actionIcon: primaryAction == .resume ? "mic.fill" : nil,
            action: primaryCallback,
            secondaryActionTitle: secondaryTitle,
            secondaryAction: secondaryCallback,
            tips: tips)
    }

    private var presentation: MeetingNotice.Presentation? {
        MeetingNotice.effectivePresentation(for: meeting.notice, hasTranscript: hasTranscript)
    }

    private var emptyNotesMessage: String {
        if let presentation {
            if presentation.isEmptyTranscript {
                if meeting.duration > 0 {
                    let duration = TemplateRenderer.duration(meeting.duration)
                    if hasSideNotes {
                        return "Ayrvo recorded \(duration) but didn't detect speech. Your notes are in My notes — resume recording if the call is still going."
                    }
                    return "Ayrvo recorded \(duration) but didn't detect speech. Resume if the meeting is still live, or write notes manually."
                }
                if hasSideNotes {
                    return "Nothing was transcribed, but you have notes in My notes. Resume recording if the call is still going."
                }
            }
            return presentation.message
        }
        return "Notes appear here once transcription finishes."
    }

    private var primaryAction: MeetingNotesLayout.PrimaryAction? {
        MeetingNotesLayout.primaryAction(
            canContinueRecording: canContinueRecording,
            resumesInFooter: resumesInFooter,
            isFailed: meeting.state == .failed)
    }

    private var primaryTitle: String? {
        switch primaryAction {
        case .resume: "Resume recording"
        case .retry: "Retry"
        case nil: nil
        }
    }

    private var primaryCallback: (() -> Void)? {
        switch primaryAction {
        case .resume: onResume
        case .retry: onRetry
        case nil: nil
        }
    }

    private var secondaryTitle: String? {
        if presentation?.isEmptyTranscript == true {
            return showSideNotes ? nil : "Write notes"
        }
        return hasTranscript ? nil : "View transcript"
    }

    private var secondaryCallback: (() -> Void)? {
        if presentation?.isEmptyTranscript == true, !showSideNotes {
            return { showSideNotes = true }
        }
        return hasTranscript ? nil : onShowTranscript
    }

    private var tips: [String] {
        guard presentation?.isEmptyTranscript == true else { return [] }
        var tips: [String] = []
        if let joinLabel {
            tips.append("Join \(joinLabel.replacingOccurrences(of: "Join ", with: "")) and resume recording to capture the call.")
        }
        if !hasSideNotes {
            tips.append("Use My notes to jot down what happened — they stay with this meeting.")
        }
        if meeting.displaySourceApp != nil {
            tips.append("Make sure Ayrvo has microphone and system audio access in Settings.")
        }
        return Array(tips.prefix(2))
    }
}
