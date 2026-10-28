import AppKit
import SwiftUI

struct AskRecentMeetings: View {
    @Environment(\.colorScheme) private var scheme
    let recentMeetings: [Meeting]
    let isEnabled: Bool
    let onSelect: (Meeting) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recents")
                .font(.ayrvo(13, .semibold))
                .foregroundStyle(Theme.secondary(scheme))

            VStack(spacing: 0) {
                ForEach(recentMeetings) { meeting in
                    Button {
                        onSelect(meeting)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(meeting.title)
                                .font(.ayrvo(13, .medium))
                                .foregroundStyle(Theme.heading(scheme))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(PastRelativeFormatter.ago(meeting.createdAt))
                                .font(.ayrvo(11))
                                .foregroundStyle(Theme.tertiary(scheme))
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)

                    if meeting.id != recentMeetings.last?.id {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: 12))
        }
    }

}

private enum PastRelativeFormatter {
    static func ago(_ date: Date, now: Date = .now) -> String {
        let interval = max(0, now.timeIntervalSince(date))
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(max(minutes, 1))m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 7 { return "\(days)d" }
        let weeks = days / 7
        if weeks < 5 { return "\(weeks)w" }
        let months = days / 30
        if months < 12 { return "\(months)mo" }
        return "\(days / 365)y"
    }
}
