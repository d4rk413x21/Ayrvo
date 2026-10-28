import SwiftUI

struct CalendarTimelineView: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var calendar: CalendarStore
    let timelineDays: [CalendarAgendaDay]
    let agendaOffsetDays: Int
    let nextEventRowID: String?
    let templateNames: [String]
    let archivedStore: ArchivedEventStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if agendaOffsetDays == 0, let first = timelineDays.flatMap(\.events).first {
                if first.isInProgress, let endsIn = calendar.endsInText(for: first) {
                    Text("Ends \(endsIn)")
                        .font(.ayrvo(13, .semibold))
                        .foregroundStyle(Theme.secondary(scheme))
                } else if let startsIn = calendar.startsInText(for: first) {
                    Text("Starts \(startsIn)")
                        .font(.ayrvo(13, .semibold))
                        .foregroundStyle(Theme.secondary(scheme))
                }
            }

            ForEach(Array(timelineDays.enumerated()), id: \.element.id) { index, day in
                timelineDaySection(day)
                if index < timelineDays.count - 1 {
                    timelineDivider
                }
            }
        }
        .cardStyle()
    }

    private func timelineDaySection(_ day: CalendarAgendaDay) -> some View {
        HStack(alignment: .top, spacing: 16) {
            timelineDateColumn(for: day.date)
            VStack(alignment: .leading, spacing: 8) {
                if day.events.isEmpty {
                    Text("No more events today")
                        .font(.ayrvo(13))
                        .foregroundStyle(Theme.secondary(scheme))
                        .padding(.vertical, 4)
                } else {
                    ForEach(day.events, id: \.rowID) { event in
                        CalendarTimelineEventRow(
                            event: event,
                            peers: day.events,
                            highlighted: event.rowID == nextEventRowID,
                            templateNames: templateNames, archivedStore: archivedStore
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timelineDateColumn(for date: Date) -> some View {
        let parts = AgendaTimelineFormatter.parts(for: date)
        return HStack(alignment: .top, spacing: 8) {
            Text(parts.dayNumber)
                .font(.ayrvo(34, .bold))
                .foregroundStyle(Theme.heading(scheme))
                .lineLimit(1)
                .frame(minWidth: 44, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(parts.month)
                Text(parts.weekday)
            }
            .font(.ayrvo(12))
            .foregroundStyle(Theme.secondary(scheme))
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: 96, alignment: .leading)
    }

    private var timelineDivider: some View {
        Rectangle()
            .fill(Theme.tertiary(scheme).opacity(0.35))
            .frame(height: 1)
            .padding(.leading, 96)
    }

}
