import SwiftUI

struct ComingUpView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var agendaOffsetDays = 0
    @StateObject private var archivedStore = ArchivedEventStore()
    private var timelineDays: [CalendarAgendaDay] {
        app.calendar.timelineDays(offsetDays: agendaOffsetDays)
    }

    private var nextEventRowID: String? {
        guard agendaOffsetDays == 0 else { return nil }
        return app.calendar.nextUpcomingEvent?.rowID
    }

    var body: some View {
        let templateNames = app.templates.list().map(\.name)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                agendaSection(templateNames: templateNames)
            }
            .padding(24)
            .contentColumn()
        }
        .background(Theme.surface(scheme))
        .task { await app.calendar.refreshAgenda() }
        .onChange(of: templateNames) { _, names in
            app.templateOverrides.pruneUnavailable(available: names)
        }
    }

    private func agendaSection(templateNames: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            agendaHeader

            if !AppSettings.useCalendar {
                emptyCalendarCard("Turn on calendar matching in Settings to see your schedule.")
            } else if CalendarAuthorization.isDenied {
                emptyCalendarCard("Calendar access was denied. Open Settings to allow Ayrvo to read your schedule.") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
            } else if !CalendarAuthorization.isAuthorized {
                emptyCalendarCard("Grant calendar access in Settings to see your schedule.") {
                    Task {
                        _ = await CalendarAuthorization.requestAccess()
                        await app.calendar.resetEventStoreAfterGrant()
                    }
                }
            } else if timelineDays.isEmpty {
                emptyCalendarCard(agendaOffsetDays == 0 ? "No upcoming events." : "No events in this range.")
            } else {
                CalendarTimelineView(
                    calendar: app.calendar, timelineDays: timelineDays, agendaOffsetDays: agendaOffsetDays,
                    nextEventRowID: nextEventRowID, templateNames: templateNames, archivedStore: archivedStore)
            }
            ArchivedCalendarSection(archivedStore: archivedStore, calendar: app.calendar)
        }
    }

    private var agendaHeader: some View {
        HStack(alignment: .center) {
            Text("Coming up")
                .font(.ayrvo(22, .bold))
                .foregroundStyle(Theme.heading(scheme))
            Spacer()
            if AppSettings.useCalendar, CalendarAuthorization.isAuthorized {
                HStack(spacing: 8) {
                    Button("Today") {
                        Task { await jumpToToday() }
                    }
                    .buttonStyle(.plain)
                    .font(.ayrvo(13, .medium))
                    .foregroundStyle(agendaOffsetDays == 0 ? Theme.tertiary(scheme) : Theme.blueberry(scheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .disabled(agendaOffsetDays == 0)

                    HStack(spacing: 0) {
                        agendaNavButton(
                            systemName: "chevron.left",
                            foreground: agendaOffsetDays == 0 ? Theme.tertiary(scheme) : Theme.secondary(scheme),
                            disabled: agendaOffsetDays == 0
                        ) {
                            Task { await pageBackward() }
                        }

                        agendaNavButton(
                            systemName: "chevron.right",
                            foreground: canPageForward ? Theme.secondary(scheme) : Theme.tertiary(scheme),
                            disabled: !canPageForward
                        ) {
                            Task { await pageForward() }
                        }
                    }
                }
            }
        }
    }

    private var canPageForward: Bool {
        agendaOffsetDays < app.calendar.maxTimelineOffset()
            || agendaOffsetDays + UpcomingMeetings.timelinePageDays < app.calendar.fetchHorizonDays
    }

    private func agendaNavButton(
        systemName: String,
        foreground: Color,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .disabled(disabled)
    }

    @ViewBuilder
    private func emptyCalendarCard(_ message: String, action: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.ayrvo(13))
                .foregroundStyle(Theme.secondary(scheme))
            if let action {
                Button("Open Settings", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func jumpToToday() async {
        agendaOffsetDays = 0
    }

    private func pageBackward() async {
        agendaOffsetDays = max(0, agendaOffsetDays - UpcomingMeetings.timelinePageDays)
    }

    private func pageForward() async {
        let next = agendaOffsetDays + UpcomingMeetings.timelinePageDays
        await app.calendar.ensureHorizon(forOffsetDays: next)
        agendaOffsetDays = next
    }
}
