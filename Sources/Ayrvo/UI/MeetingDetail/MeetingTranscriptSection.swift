import SwiftUI

struct MeetingTranscriptSection: View {
    @Environment(\.colorScheme) private var scheme

    let hasTranscript: Bool
    let isRecording: Bool
    let isPrep: Bool
    let duration: TimeInterval

    /// Inline transcript empty-state. When the meeting has no transcript yet (and
    /// isn't being recorded live — the live transcript lives in the floating
    /// panel), show a placeholder so the document isn't silent about the missing
    /// transcript. When a transcript exists it's read via the floating Granola
    /// panel, so nothing renders inline here.
    @ViewBuilder
    var body: some View {
        if isRecording || hasTranscript {
            EmptyView()
        } else {
            VStack(spacing: 10) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.tertiary(scheme))
                Text("No transcript yet")
                    .font(.ayrvo(13, .semibold))
                    .foregroundStyle(Theme.secondary(scheme))
                Text(transcriptEmptyMessage)
                    .font(.ayrvo(11))
                    .foregroundStyle(Theme.tertiary(scheme))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var transcriptEmptyMessage: String {
        if isPrep {
            return "The transcript will appear here once the meeting starts."
        }
        if duration > 0 {
            return "Ayrvo recorded this meeting but didn't capture speech. Check that microphone access is on."
        }
        return "Record this meeting to capture a transcript."
    }
}
