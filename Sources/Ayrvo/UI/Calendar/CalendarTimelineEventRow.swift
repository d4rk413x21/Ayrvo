import SwiftUI

struct CalendarTimelineEventRow: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    let event: CalendarEventSummary
    let peers: [CalendarEventSummary]
    let highlighted: Bool
    let templateNames: [String]
    @ObservedObject var archivedStore: ArchivedEventStore

    var body: some View {
        let showJoin = event.shouldShowJoinButton(among: peers)
        let folderRule = app.folders.folder(forTitle: event.title)
        return HStack(alignment: .top, spacing: 8) {
            Button {
                app.openCalendarEvent(event)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(event.title)
                            .font(.ayrvo(13, .medium))
                            .foregroundStyle(Theme.heading(scheme))
                            .lineLimit(2)
                        if event.conferenceURL != nil {
                            ConferenceVideoIcon()
                                .alignmentGuide(.firstTextBaseline) { dimensions in
                                    dimensions[.bottom] - 1
                                }
                        }
                    }
                    HStack(spacing: 6) {
                        if let countdown = app.calendar.countdownText(for: event) {
                            Text(countdown)
                                .font(.ayrvo(11, .semibold))
                                .foregroundStyle(event.isInProgress ? Theme.mint(scheme) : Theme.honey(scheme))
                        }
                        Text(CalendarTimeFormatter.timeRange(start: event.start, end: event.end))
                            .font(.ayrvo(11))
                            .foregroundStyle(Theme.secondary(scheme))
                    }
                    if let location = event.location {
                        Text(location)
                            .font(.ayrvo(10))
                            .foregroundStyle(Theme.tertiary(scheme))
                            .lineLimit(1)
                    }
                }
                .calendarEventIndicator(event.calendarColor.swiftUIColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 20)
            timelineEventActions(
                event: event,
                showJoin: showJoin,
                folderRule: folderRule
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.card(scheme).opacity(scheme == .dark ? 0.85 : 0.65))
            }
        }
        .contextMenu {
            Button {
                archivedStore.archiveTitle(event.title)
                Task { await app.calendar.refreshAgenda() }
            } label: {
                Label("Archive series (hide all \"\(event.title)\")", systemImage: "archivebox.fill")
            }
            Button {
                archivedStore.archiveEvent(id: event.id, title: event.title)
                Task { await app.calendar.refreshAgenda() }
            } label: {
                Label("Archive this event only", systemImage: "archivebox")
            }
            Divider()
            Menu("Template") { templateOptions }
            Divider()
            if archivedStore.hasAny {
                Menu("Archived events") {
                    ForEach(Array(archivedStore.archivedTitles).sorted(), id: \.self) { title in
                        Button {
                            archivedStore.unarchiveTitle(title)
                            Task { await app.calendar.refreshAgenda() }
                        } label: {
                            Label("Unarchive \(title)", systemImage: "arrow.up.out.of.square")
                        }
                    }
                    if !archivedStore.archivedTitles.isEmpty && !archivedStore.archivedEvents.isEmpty {
                        Divider()
                    }
                    ForEach(archivedStore.archivedEvents) { evt in
                        Button {
                            archivedStore.unarchiveEvent(id: evt.id)
                            Task { await app.calendar.refreshAgenda() }
                        } label: {
                            Label("Unarchive \(evt.title)", systemImage: "arrow.up.out.of.square")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        archivedStore.clearAll()
                        Task { await app.calendar.refreshAgenda() }
                    } label: {
                        Label("Clear all archived", systemImage: "trash")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func timelineEventActions(
        event: CalendarEventSummary,
        showJoin: Bool,
        folderRule: MeetingFolder?
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            FolderPickerMenu(
                currentFolderID: folderRule?.id,
                calendarTitle: event.title,
                meetingID: nil
            ) {
                folderPickerChipLabel(folder: folderRule)
            }
            .buttonStyle(.plain)

            templatePickerChip(for: event)

            if showJoin, let url = event.conferenceURL {
                ConferenceJoinButton(label: event.joinLabel, url: url, calendarEvent: event)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Per-event template assignment chip. Shows the assigned template name (or
    /// a muted "Template" hint on hover), and opens a menu of all templates
    /// plus a "Use default" entry to clear the override. The assignment is
    /// honored by PrepareMeetingUseCase and RecordingServiceImpl, so both the
    /// manual "Record" path and mic-detection auto-start use it.
    @ViewBuilder
    private func templatePickerChip(for event: CalendarEventSummary) -> some View {
        let resolved = resolvedTemplate
        Menu {
            templateOptions
        } label: {
            templateChipLabel(name: resolved)
        }
        .buttonStyle(.plain)
        .help(resolved.map { "Template: \($0)" } ?? "Assign a template for this meeting")
    }

    @ViewBuilder
    private func templateChipLabel(name: String?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "doc.text")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(name == nil ? Theme.secondary(scheme) : Theme.mint(scheme))
            if let name {
                Text(name)
                    .font(.ayrvo(11, .medium))
                    .foregroundStyle(Theme.heading(scheme))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            (name == nil ? Color.secondary.opacity(0.08) : Theme.mint(scheme).opacity(0.12)),
            in: Capsule()
        )
        .contentShape(Rectangle())
    }
    @ViewBuilder
    private func folderPickerChipLabel(folder: MeetingFolder?) -> some View {
        if let folder {
            FolderIconView(folder: folder, size: 20)
                .contentShape(Rectangle())
        } else {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondary(scheme))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
    }

    private var resolvedTemplate: String? {
        guard let assigned = app.templateOverrides.overrides[event.id], templateNames.contains(assigned) else { return nil }
        return assigned
    }

    private var templateOptions: some View {
        CalendarTemplateOptions(names: templateNames, selected: resolvedTemplate) {
            app.templateOverrides.set(eventID: event.id, templateName: $0)
        }
    }
}
