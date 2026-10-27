import SwiftUI

struct MeetingDocumentHeader: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.ayrvoActionColor) private var actionColor
    @State private var showAttendees = false
    @AppStorage(SettingsKey.smartTemplatesEnabled) private var smartTemplatesEnabled = true
    @AppStorage(SettingsKey.showMeetingCost) private var showMeetingCost = false
    @AppStorage(SettingsKey.hourlyRatePerPerson) private var storedHourlyRate = 100.0

    let meeting: Meeting
    @Binding var title: String
    let titleFocus: FocusState<Bool>.Binding
    @Binding var showSideNotes: Bool
    let hasSideNotes: Bool
    let hasSummary: Bool
    let hasEmptyTranscriptNotice: Bool
    let join: (label: String, url: URL)?
    let processingStage: String?
    @ObservedObject var folders: MeetingFolderStore
    let onSaveTitle: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            TextField("Meeting title", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Theme.heading(scheme))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .focused(titleFocus)
                .onSubmit { onSaveTitle() }
                .onChange(of: titleFocus.wrappedValue) { if !titleFocus.wrappedValue { onSaveTitle() } }

            metadataChips
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .onDisappear { showAttendees = false }
    }

    private var metadataChips: some View {
        FlowLayout(spacing: 8) {
            Button { showSideNotes.toggle() } label: {
                GranolaChip(
                    icon: "note.text",
                    text: hasSideNotes ? "My notes" : "Write notes",
                    accent: showSideNotes
                        ? Theme.mint(scheme)
                        : (hasEmptyTranscriptNotice && !hasSideNotes ? Theme.honey(scheme) : actionColor))
            }
            .buttonStyle(.plain)
            .help(hasSideNotes ? "Show or hide your notes" : "Open notes to write what happened")

            if hasSummary {
                GranolaChip(icon: "sparkles", text: "Enhanced")
            }
            GranolaChip(
                icon: "calendar",
                text: meeting.createdAt.formatted(.dateTime.month(.abbreviated).day()))
            if meeting.duration > 0 {
                GranolaChip(
                    icon: "clock",
                    text: TemplateRenderer.duration(meeting.duration))
            }
            if let join {
                Button { ConferenceJoiner.open(join.url) } label: {
                    GranolaChip(
                        icon: "video.fill",
                        text: join.label,
                        accent: Theme.blueberry(scheme))
                }
                .buttonStyle(.plain)
            }
            if !meeting.attendees.isEmpty {
                Button { showAttendees = true } label: {
                    GranolaChip(
                        icon: "person.2",
                        text: attendeeChipLabel)
                }
                .buttonStyle(.plain)
                .help("Show all participants")
                .accessibilityLabel("Show all participants")
                .popover(isPresented: $showAttendees, arrowEdge: .top) {
                    attendeesPopover
                }
            }
            if let type = detectedMeetingType {
                GranolaChip(
                    icon: type.symbolName,
                    text: type.displayName,
                    accent: Theme.blueberry(scheme))
                    .help("Auto-detected meeting type. Template: \(MeetingTemplateResolver.templateName(for: type)).")
            }
            if let costChip = meetingCostChip {
                GranolaChip(
                    icon: nil,
                    text: "💰 \(costChip.formattedCost)",
                    accent: Theme.honey(scheme))
                .help("Estimated cost: \(costChip.attendeeCount) people × \(costChip.durationMinutes) min × \(MeetingCost.format(hourlyRate))/hr")
            }
            folderChipContent
            if let provider = meeting.summaryProvider {
                providerChip(provider)
            }
            if let stage = processingStage {
                GranolaChip(icon: nil, text: stage, accent: Theme.honey(scheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var folderChipContent: some View {
        if let folderID = meeting.folderID,
           let folder = folders.folder(id: folderID) {
            FolderPickerMenu(
                currentFolderID: folderID,
                calendarTitle: meeting.calendarEventTitle ?? meeting.title,
                meetingID: meeting.id
            ) {
                GranolaChip(icon: "folder", text: folder.name)
            }
            .buttonStyle(.plain)
        } else {
            FolderPickerMenu(
                currentFolderID: nil,
                calendarTitle: meeting.calendarEventTitle ?? meeting.title,
                meetingID: meeting.id
            ) {
                GranolaChip(icon: "folder.badge.plus", text: "Add to folder")
            }
            .buttonStyle(.plain)
        }
    }

    private var attendeesPopover: some View {
        ScrollView {
            FlowLayout(spacing: 6) {
                ForEach(meeting.attendees, id: \.self) { Chip(text: $0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(minWidth: 280, maxWidth: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func providerChip(_ provider: String) -> some View {
        let label: String
        switch provider {
        case "claude": label = "Claude"
        case "codex": label = "Codex"
        case "opencode": label = "OpenCode"
        case "vibe": label = "Mistral Vibe"
        case "apple": label = "Apple Intelligence"
        default: label = provider
        }
        return GranolaChip(icon: "sparkles", text: label, accent: Theme.raspberry)
    }

    private var attendeeChipLabel: String {
        meeting.attendees.count == 1 ? "1 person" : "\(meeting.attendees.count) people"
    }
    /// Meeting-type badge for the header. Resolves the type from the calendar
    /// title + attendees (the transcript isn't available at header time) and
    /// returns it only when smart templates are on and the type is specific
    /// enough to be worth showing — `.generic` is suppressed so ordinary
    /// meetings don't get a noisy "General" chip.
    private var detectedMeetingType: MeetingType? {
        guard smartTemplatesEnabled else { return nil }
        let type = MeetingTemplateResolver.resolve(for: meeting)
        return type == .generic ? nil : type
    }
    /// Estimated-meeting-cost badge for the header. Non-nil only when the user
    /// has the cost feature on AND the meeting has both attendees and a recorded
    /// duration — otherwise the badge is suppressed (no attendees ⇒ no cost basis,
    /// zero duration ⇒ a $0 chip that just adds noise).
    private var meetingCostChip: MeetingCost? {
        guard showMeetingCost,
              !meeting.attendees.isEmpty,
              meeting.duration > 0 else { return nil }
        return MeetingCostCalculator.estimate(
            attendees: meeting.attendees,
            duration: meeting.duration,
            hourlyRatePerPerson: hourlyRate)
    }

    private var hourlyRate: Double {
        storedHourlyRate > 0 ? storedHourlyRate : 100.0
    }
}
