import SwiftUI

struct MeetingRecordingFooter: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    let url: URL
    let calendarEvent: CalendarEventSummary?
    let canResume: Bool
    let onResume: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if canResume {
                HStack {
                    Spacer()
                    Button {
                        onResume()
                    } label: {
                        Label("Resume recording", systemImage: "mic.fill")
                            .font(.ayrvo(11, .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.mint(scheme))
                    .clipShape(Capsule())
                    Spacer()
                }
            }
            ConferenceJoinButton(label: label, url: url, prominent: true, calendarEvent: calendarEvent)
                .frame(maxWidth: 560)
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }
}
