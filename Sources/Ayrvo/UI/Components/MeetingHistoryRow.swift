import AppKit
import SwiftUI

// MARK: - Meeting history list

enum MeetingListMetadata {
    case attendees(String)
    case duration(String)
    case source(String)

    var icon: String {
        switch self {
        case .attendees: "person.2"
        case .duration: "clock"
        case .source: "app.badge"
        }
    }

    var text: String {
        switch self {
        case .attendees(let text), .duration(let text), .source(let text): text
        }
    }

    static func from(_ meeting: Meeting) -> MeetingListMetadata? {
        if !meeting.attendees.isEmpty {
            let names = meeting.attendees.prefix(2).joined(separator: ", ")
            let extra = meeting.attendees.count - 2
            let text = extra > 0 ? "\(names) & \(extra) others" : names
            return .attendees(text)
        }
        if meeting.duration > 0 {
            return .duration(TemplateRenderer.duration(meeting.duration))
        }
        if let app = meeting.displaySourceApp {
            return .source(app)
        }
        return nil
    }
}

private struct MeetingRowButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    var isHovered: Bool
    var isFailed: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(backgroundColor(configuration))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private func backgroundColor(_ configuration: Configuration) -> Color {
        if isFailed {
            return Color.orange.opacity(scheme == .dark ? 0.12 : 0.08)
        }
        if configuration.isPressed || isHovered {
            return Theme.chip(scheme)
        }
        return Color.clear
    }
}

struct MeetingHistoryRow: View {
    @Environment(\.colorScheme) private var scheme
    let meeting: Meeting
    var stage: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    private var metadata: MeetingListMetadata? { MeetingListMetadata.from(meeting) }

    private var displayTitle: String {
        meeting.calendarEventTitle ?? meeting.title
    }

    /// Time shown in the list — see `Meeting.displayTime`.

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(displayTitle)
                            .font(.ayrvo(14, .medium))
                            .foregroundStyle(Theme.heading(scheme))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if meeting.calendarEventID != nil {
                            Image(systemName: "calendar")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.blueberry(scheme))
                        }
                    }
                    if let metadata {
                        HStack(spacing: 4) {
                            Image(systemName: metadata.icon)
                                .font(.system(size: 9, weight: .semibold))
                            Text(metadata.text)
                                .font(.ayrvo(11))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Theme.secondary(scheme))
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(meeting.displayTime.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.tertiary(scheme))
                    if meeting.state != .ready {
                        StateBadge(meeting: meeting, stage: stage)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.tertiary(scheme))
                    .opacity(isHovered ? 0.7 : 0)
                    .frame(width: 10)
            }
        }
        .buttonStyle(MeetingRowButtonStyle(
            isHovered: isHovered,
            isFailed: meeting.state == .failed))
        .onHover { isHovered = $0 }
    }
}
