import AppKit
import SwiftUI

struct CalendarSettings: View {
    @EnvironmentObject private var app: AppState
    @AppStorage(SettingsKey.useCalendar) private var useCalendar = true
    @AppStorage(SettingsKey.upcomingCountdownHours) private var upcomingCountdownHours = 3.0
    @AppStorage(SettingsKey.showUpcomingInMenuBar) private var showUpcomingInMenuBar = true
    @AppStorage(SettingsKey.showEventsWithoutParticipants) private var showEventsWithoutParticipants = true

    @State private var calendarStatus = CalendarAuthorization.isAuthorized
    @State private var calendars: [CalendarSourceInfo] = []
    @State private var disabledIDs: Set<String> = AppSettings.disabledCalendarIDs
    @StateObject private var archivedStore = ArchivedEventStore()
    var body: some View {
        Form {
            if !calendarStatus {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        StatusDot(ok: false)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Calendar access is required to show your schedule.")
                                .font(.ayrvo(12))
                            if CalendarAuthorization.isDenied {
                                Button("Open System Settings") {
                                    NSWorkspace.shared.open(URL(
                                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                                }
                                .controlSize(.small)
                            } else {
                                Button("Grant access…") {
                                    Task { await grantAccess() }
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }

            Section("Display") {
                Toggle("Match calendar events", isOn: $useCalendar)
                    .onChange(of: useCalendar) {
                        Task { await app.calendar.refreshAgenda() }
                    }
                Text("Uses your calendar for titles, attendees, and the Coming up view.")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)
                Toggle("Show upcoming meetings in menu bar", isOn: $showUpcomingInMenuBar)
                    .disabled(!useCalendar)
                Text("Displays your next meeting and time until it starts in the macOS menu bar.")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)
                if useCalendar {
                    Stepper(value: $upcomingCountdownHours, in: 0.5...12, step: 0.5) {
                        Text("Countdown window: \(countdownLabel)")
                            .font(.ayrvo(12))
                    }
                }
                Toggle("Show events with no participants", isOn: $showEventsWithoutParticipants)
                    .disabled(!useCalendar)
                    .onChange(of: showEventsWithoutParticipants) {
                        Task { await app.calendar.refreshAgenda() }
                    }
                Text("Coming up includes events without attendees or a video link when on.")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)
            }

            if calendarStatus {
                Section {
                    HStack {
                        Text("Visible calendars")
                            .font(.ayrvo(12, .semibold))
                        Spacer()
                        Button("Reset") { resetCalendars() }
                            .buttonStyle(.plain)
                            .font(.ayrvo(11, .medium))
                            .foregroundStyle(Theme.blueberry)
                            .disabled(disabledIDs.isEmpty)
                    }
                    if calendars.isEmpty {
                        Text("No calendars found on this Mac.")
                            .font(.ayrvo(11))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(calendars) { source in
                            calendarRow(source)
                        }
                    }
                    Text("Only events from enabled calendars appear in Coming up and when matching recordings.")
                        .font(.ayrvo(11))
                        .foregroundStyle(.secondary)
                }
            }

            if useCalendar {
                Section("Archived events") {
                    if !archivedStore.hasAny {
                        Text("No archived events. Right-click an event in Coming up to hide it.")
                            .font(.ayrvo(11))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(archivedStore.archivedTitles).sorted(), id: \.self) { title in
                            HStack {
                                Label(title, systemImage: "archivebox.fill")
                                    .font(.ayrvo(12))
                                Spacer()
                                Button {
                                    archivedStore.unarchiveTitle(title)
                                    Task { await app.calendar.refreshAgenda() }
                                } label: {
                                    Image(systemName: "arrow.up.out.of.square")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.blueberry)
                                .help("Unarchive series")
                                .accessibilityLabel("Unarchive series")
                            }
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                archivedStore.unarchiveTitle(title)
                                Task { await app.calendar.refreshAgenda() }
                            }
                        }
                        ForEach(archivedStore.archivedEvents) { evt in
                            HStack {
                                Label(evt.title, systemImage: "archivebox")
                                    .font(.ayrvo(12))
                                Spacer()
                                Button {
                                    archivedStore.unarchiveEvent(id: evt.id)
                                    Task { await app.calendar.refreshAgenda() }
                                } label: {
                                    Image(systemName: "arrow.up.out.of.square")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.blueberry)
                                .help("Unarchive event")
                                .accessibilityLabel("Unarchive event")
                            }
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                archivedStore.unarchiveEvent(id: evt.id)
                                Task { await app.calendar.refreshAgenda() }
                            }
                        }
                        Divider()
                        Button {
                            archivedStore.clearAll()
                            Task { await app.calendar.refreshAgenda() }
                        } label: {
                            Label("Unarchive all", systemImage: "arrow.up.out.of.square")
                                .font(.ayrvo(11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.blueberry)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { reloadCalendars() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            calendarStatus = CalendarAuthorization.isAuthorized
            reloadCalendars()
        }
    }

    private func calendarRow(_ source: CalendarSourceInfo) -> some View {
        Toggle(isOn: calendarBinding(source.id)) {
            HStack(spacing: 8) {
                Circle()
                    .fill(source.color)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.title)
                        .font(.ayrvo(12, .medium))
                    if let account = source.sourceTitle, account != source.title {
                        Text(account)
                            .font(.ayrvo(10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .disabled(!useCalendar)
    }

    private func calendarBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !disabledIDs.contains(id) },
            set: { enabled in
                if enabled { disabledIDs.remove(id) } else { disabledIDs.insert(id) }
                AppSettings.setCalendarEnabled(id: id, enabled: enabled)
                Task { await app.calendar.refreshAgenda() }
            })
    }

    private var countdownLabel: String {
        upcomingCountdownHours == floor(upcomingCountdownHours)
            ? "\(Int(upcomingCountdownHours)) hours"
            : String(format: "%.1f hours", upcomingCountdownHours)
    }

    private func reloadCalendars() {
        calendarStatus = CalendarAuthorization.isAuthorized
        disabledIDs = AppSettings.disabledCalendarIDs
        calendars = CalendarSources.all()
    }

    private func grantAccess() async {
        calendarStatus = await CalendarAuthorization.requestAccess()
        reloadCalendars()
        await app.calendar.resetEventStoreAfterGrant()
    }

    private func resetCalendars() {
        AppSettings.resetCalendarSelection()
        disabledIDs = []
        Task { await app.calendar.refreshAgenda() }
    }
}
