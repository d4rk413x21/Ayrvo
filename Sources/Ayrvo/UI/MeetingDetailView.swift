import AppKit
import SwiftUI

struct MeetingDetailView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.ayrvoActionColor) private var actionColor

    @State private var meeting: Meeting
    @State private var panelMode: GranolaPanelMode?
    @State private var title: String
    @State private var previewError: String?
    @State private var showDeleteConfirm = false
    @State private var notesDraft: String?
    @State private var transcriptDraft: String?
    @State private var showAttendees = false
    @State private var sideNotes = ""
    @State private var showSideNotes = false
    @State private var sideNotesSaveTask: Task<Void, Never>?
    @State private var showShareNotes = false
    @State private var showDevelopmentTasks = false
    @AppStorage(SettingsKey.sideNotesPanelWidth) private var sideNotesWidth = 280.0

    var backTitle: String?
    var onBack: (() -> Void)?

    init(meeting: Meeting, backTitle: String? = nil, onBack: (() -> Void)? = nil) {
        _meeting = State(initialValue: meeting)
        _title = State(initialValue: meeting.title)
        self.backTitle = backTitle
        self.onBack = onBack
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .top, spacing: 0) {
                if showSideNotes {
                    SideNotesPanel(
                        text: $sideNotes,
                        isRecording: isRecordingThisMeeting,
                        onTextChange: scheduleSideNotesSave)
                        .frame(width: sideNotesWidth)

                    SideNotesResizeHandle(width: $sideNotesWidth)
                }

                documentScroll
            }

            GranolaFloatingPanel(
                meeting: meeting,
                mode: $panelMode,
                transcriptDraft: $transcriptDraft)
        }
        .background(Theme.surface(scheme))
        .navigationTitle(meeting.title)
        .toolbar { meetingToolbar }
        .safeAreaInset(edge: .bottom) {
            if showProminentJoinButton, let join = joinConference {
                VStack(spacing: 8) {
                    if canContinueRecording {
                        HStack {
                            Spacer()
                            Button {
                                Task { await app.continueRecording(meetingID: meeting.id) }
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
                    ConferenceJoinButton(label: join.label, url: join.url, prominent: true, calendarEvent: linkedCalendarEvent)
                        .frame(maxWidth: 560)
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .task { await app.calendar.refreshAgenda() }
        .trackingEdits(isDirty: { hasUnsavedEdits }, save: {
            if let draft = notesDraft {
                guard app.store.saveSummarySafely(draft, for: meeting.id) else { return false }
                notesDraft = nil
            }
            return saveTitle()
        }, discard: {
            title = meeting.title
            discardNotesEdits()
        })
        .onAppear {
            loadSideNotes()
            presentTranscriptIfNeeded()
        }
        .onDisappear {
            showAttendees = false
            sideNotesSaveTask?.cancel()
            if sideNotesSaveTask != nil, app.store.meeting(id: meeting.id) != nil {
                app.store.saveSideNotes(sideNotes, for: meeting.id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ayrvoFlushEdits)) { _ in
            sideNotesSaveTask?.cancel()
            if sideNotesSaveTask != nil, app.store.meeting(id: meeting.id) != nil {
                app.store.saveSideNotes(sideNotes, for: meeting.id)
            }
        }
        .onChange(of: app.store.meetings) {
            if let fresh = app.store.meetings.first(where: { $0.id == meeting.id }) {
                meeting = fresh
                if !isEditingTitle { title = fresh.title }
            }
        }
        .onChange(of: app.session?.meetingID) { _, id in
            if id == meeting.id {
                panelMode = .transcript
                showSideNotes = true
            }
        }
        .confirmationDialog("Move “\(meeting.title)” to trash?", isPresented: $showDeleteConfirm) {
            Button("Move to trash", role: .destructive) { app.store.delete(id: meeting.id) }
                .tint(.red)
        } message: {
            Text("This permanently removes the audio, transcript, and notes from your Mac.")
        }
        .sheet(isPresented: $showShareNotes) {
            MeetingShareNotesSheet(meeting: meeting, store: app.store)
        }
        .sheet(isPresented: $showDevelopmentTasks) {
            DevelopmentTasksSheet(meeting: meeting)
        }
    }

    private var isRecordingThisMeeting: Bool {
        app.session?.meetingID == meeting.id
    }

    private var isPrepMeeting: Bool {
        meeting.state == .prep && !isRecordingThisMeeting
    }

    private var hasSideNotes: Bool {
        !sideNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadSideNotes() {
        sideNotes = app.store.sideNotes(for: meeting.id)
        showSideNotes = isRecordingThisMeeting || isPrepMeeting || hasSideNotes
    }

    private var hasUnsavedEdits: Bool {
        if title.trimmingCharacters(in: .whitespacesAndNewlines) != meeting.title { return true }
        guard let draft = notesDraft else { return false }
        let file = app.store.archive.folder(for: meeting.id).appendingPathComponent("summary.md")
        return draft != summary || FilePersistence.failure(at: file)?.data == Data(draft.utf8)
    }

    private func discardNotesEdits() {
        let file = app.store.archive.folder(for: meeting.id).appendingPathComponent("summary.md")
        if let draft = notesDraft, FilePersistence.failure(at: file)?.data == Data(draft.utf8) {
            FilePersistence.discard(file)
        }
        notesDraft = nil
    }

    private func scheduleSideNotesSave() {
        sideNotesSaveTask?.cancel()
        let text = sideNotes
        let id = meeting.id
        sideNotesSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            app.store.saveSideNotes(text, for: id)
        }
    }

    // MARK: - Window toolbar

    @ToolbarContentBuilder
    private var meetingToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if let onBack {
                Button("Back to \(backTitle ?? "previous view")", systemImage: "chevron.left", action: onBack)
                    .labelStyle(.iconOnly)
                    .help("Back to \(backTitle ?? "previous view")")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Development tasks", systemImage: "checklist") { showDevelopmentTasks = true }
                .labelStyle(.iconOnly)
                .disabled(isRecordingThisMeeting || meeting.state == .processing)
                .help("Review development tasks and create Linear issues")
            Button("Copy transcript", systemImage: "doc.on.doc", action: copyTranscript)
                .labelStyle(.iconOnly)
                .disabled(app.store.transcript(for: meeting.id).isEmpty)
                .help("Copy transcript")
            Button("Share notes", systemImage: "square.and.arrow.up") { showShareNotes = true }
                .labelStyle(.iconOnly)
                .help("Share notes")
            MeetingActionsMenu(
                meeting: meeting,
                store: app.store,
                previewError: $previewError,
                onDelete: { showDeleteConfirm = true })
        }
    }

    private var shouldCenterEmptyNotes: Bool {
        !isRecordingThisMeeting
            && !isPrepMeeting
            && notesDraft == nil
            && displayed.isEmpty
            && (showSideNotes || !hasSideNotes)
    }

    private var documentScroll: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 20) {
                    documentHeader
                    notesSection
                    MeetingDecisionsSection(
                        segments: app.store.transcript(for: meeting.id),
                        speakers: meeting.speakers,
                        isRecording: isRecordingThisMeeting)
                    MeetingTranscriptSection(
                        hasTranscript: hasTranscript,
                        isRecording: isRecordingThisMeeting,
                        isPrep: isPrepMeeting,
                        duration: meeting.duration)
                }
                .contentColumn()
                .frame(minHeight: shouldCenterEmptyNotes ? geo.size.height : nil, alignment: .top)
                .padding(.horizontal, 28)
                .padding(.bottom, panelMode != nil ? 340 : 100)
            }
        }
    }

    // MARK: - Document header

    @FocusState private var isEditingTitle: Bool

    private var documentHeader: some View {
        VStack(spacing: 14) {
            TextField("Meeting title", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Theme.heading(scheme))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .focused($isEditingTitle)
                .onSubmit { saveTitle() }
                .onChange(of: isEditingTitle) { if !isEditingTitle { saveTitle() } }

            metadataChips
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
    }

    private var metadataChips: some View {
        FlowLayout(spacing: 8) {
            Button { showSideNotes.toggle() } label: {
                GranolaChip(
                    icon: "note.text",
                    text: hasSideNotes ? "My notes" : "Write notes",
                    accent: showSideNotes
                        ? Theme.mint(scheme)
                        : (isEmptyTranscriptNotice && !hasSideNotes ? Theme.honey(scheme) : actionColor))
            }
            .buttonStyle(.plain)
            .help(hasSideNotes ? "Show or hide your notes" : "Open notes to write what happened")

            if !summary.isEmpty {
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
            if let join = joinConference, !showProminentJoinButton {
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
                .help("Estimated cost: \(costChip.attendeeCount) people × \(costChip.durationMinutes) min × \(MeetingCost.format(AppSettings.hourlyRatePerPerson))/hr")
            }
            folderChipContent
            if let provider = meeting.summaryProvider {
                providerChip(provider)
            }
            if let stage = app.processingStage[meeting.id] {
                GranolaChip(icon: nil, text: stage, accent: Theme.honey(scheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var folderChipContent: some View {
        if let folderID = meeting.folderID,
           let folder = app.folders.folder(id: folderID) {
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

    // MARK: - Notes

    private var summary: String { app.store.summary(for: meeting.id) }
    private var streaming: String? { app.streamingSummaries[meeting.id] }
    private var displayed: String { streaming ?? summary }

    private var notesSection: some View {
        VStack(alignment: shouldCenterEmptyNotes ? .center : .leading, spacing: 12) {
            if isRecordingThisMeeting {
                if notesDraft != nil {
                    notesEditor
                } else if !displayed.isEmpty {
                    if !showSideNotes, hasSideNotes {
                        myNotesReader
                            .padding(.bottom, 16)
                    }
                    notesReader
                } else if streaming != nil || app.processingStage[meeting.id] != nil {
                    emptyNotes
                } else {
                    recordingPlaceholder
                }
            } else if isPrepMeeting {
                prepPlaceholder
            } else if notesDraft != nil {
                notesEditor
            } else if displayed.isEmpty {
                if !showSideNotes, hasSideNotes {
                    myNotesReader
                } else {
                    emptyNotes
                }
            } else {
                if !showSideNotes, hasSideNotes {
                    myNotesReader
                        .padding(.bottom, 16)
                }
                notesReader
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: shouldCenterEmptyNotes ? .infinity : nil,
            alignment: shouldCenterEmptyNotes ? .center : .leading)
    }

    private var prepPlaceholder: some View {
        Text("Write notes")
            .font(.ayrvo(14))
            .foregroundStyle(Theme.tertiary(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 40)
    }

    private var recordingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showSideNotes {
                Text("Enhanced notes will appear here as the meeting is summarized. The live transcript is in the Transcript panel below.")
                    .font(.ayrvo(13))
                    .foregroundStyle(Theme.tertiary(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 40)
            } else {
                Button {
                    showSideNotes = true
                } label: {
                    Text("Enhanced notes will appear here. Open My notes on the left, or use the Transcript panel below for the live transcript.")
                    .font(.ayrvo(14))
                    .foregroundStyle(Theme.tertiary(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open My notes")
            }
        }
    }

    private var myNotesReader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("My notes")
                .font(.ayrvo(12, .semibold))
                .foregroundStyle(Theme.secondary(scheme))
            Text(sideNotes)
                .font(.ayrvo(13))
                .foregroundStyle(Theme.secondary(scheme))
                .textSelection(.enabled)
                .lineSpacing(4)
        }
    }

    private var notesReader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let progress = app.summaryProgress[meeting.id] {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small).scaleEffect(0.6)
                        Text(progress == .improving ? "Draft · improving" : "Writing…")
                            .font(.ayrvo(11))
                            .foregroundStyle(Theme.tertiary(scheme))
                    }
                }
                Spacer()
                notesEditMenu
            }
            .padding(.bottom, 8)

            if !displayed.isEmpty {
                Text("Enhanced notes")
                    .font(.ayrvo(12, .semibold))
                    .foregroundStyle(Theme.secondary(scheme))
                    .padding(.bottom, 8)
            }

            MarkdownText(markdown: displayed, style: .document)
        }
    }

    private var notesEditor: some View {
        MeetingNotesEditor(
            text: Binding(get: { notesDraft ?? "" }, set: { notesDraft = $0 }),
            onSave: {
                if let notesDraft, !app.store.saveSummarySafely(notesDraft, for: meeting.id) { return }
                notesDraft = nil
            },
            onCancel: discardNotesEdits)
    }

    @ViewBuilder
    private var emptyNotes: some View {
        if streaming != nil || app.processingStage[meeting.id] != nil {
            EmptyStateView(
                title: "Working on it…",
                message: app.processingStage[meeting.id] ?? "Writing your notes…")
        } else {
            EmptyStateView(
                title: emptyNotesTitle,
                message: emptyNotesMessage,
                // When resume is available, the action lives in the bottom
                // safeAreaInset — don't duplicate it here.
                actionTitle: canContinueRecording ? nil : emptyNotesActionTitle,
                actionIcon: canContinueRecording ? nil : emptyNotesActionIcon,
                action: canContinueRecording ? nil : emptyNotesAction,
                secondaryActionTitle: emptyNotesSecondaryActionTitle,
                secondaryAction: emptyNotesSecondaryAction,
                tips: emptyNotesTips)
        }
    }

    private var notesEditMenu: some View {
        Menu {
            Button {
                notesDraft = app.store.summary(for: meeting.id)
            } label: {
                Label("Edit notes", systemImage: "pencil")
            }
            .disabled(summary.isEmpty || streaming != nil)

            Menu("Regenerate") {
                ForEach(app.templates.list()) { template in
                    Button(template.name) {
                        Task {
                            await app.regenerateSummary(
                                meetingID: meeting.id, templateName: template.name)
                        }
                    }
                }
                Divider()
                Button("With current template") {
                    Task { await app.regenerateSummary(meetingID: meeting.id) }
                }
                if !regenerateProviderChoices.isEmpty {
                    Divider()
                    Menu("With another AI") {
                        ForEach(regenerateProviderChoices) { provider in
                            Button(provider.displayName) {
                                Task {
                                    await app.regenerateSummary(
                                        meetingID: meeting.id, forceProvider: provider)
                                }
                            }
                            .disabled(!provider.isAvailableForSummary)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.tertiary(scheme))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var hasTranscript: Bool {
        !app.store.transcript(for: meeting.id).isEmpty
    }

    private var regenerateProviderChoices: [AIProvider] {
        AIProvider.allCases.filter { $0.rawValue != meeting.summaryProvider }
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = meeting.notice,
           !isRecordingThisMeeting,
           !emptyNotesHandlesNotice,
           let presentation = MeetingNotice.effectivePresentation(
               for: notice, hasTranscript: hasTranscript) {
            MeetingNoticeBanner(
                presentation: presentation,
                primaryActionTitle: noticePrimaryActionTitle,
                primaryActionIcon: noticePrimaryActionIcon,
                primaryAction: noticePrimaryAction)
        } else if let previewError {
            MeetingNoticeBanner(
                presentation: MeetingNotice.Presentation(
                    title: "Couldn't preview",
                    message: previewError,
                    systemImage: "xmark.circle",
                    isEmptyTranscript: false))
        }
    }

    // MARK: - Helpers

    private var attendeeChipLabel: String {
        meeting.attendees.count == 1 ? "1 person" : "\(meeting.attendees.count) people"
    }
    /// Meeting-type badge for the header. Resolves the type from the calendar
    /// title + attendees (the transcript isn't available at header time) and
    /// returns it only when smart templates are on and the type is specific
    /// enough to be worth showing — `.generic` is suppressed so ordinary
    /// meetings don't get a noisy "General" chip.
    private var detectedMeetingType: MeetingType? {
        guard AppSettings.smartTemplatesEnabled else { return nil }
        let type = MeetingTemplateResolver.resolve(for: meeting)
        return type == .generic ? nil : type
    }
    /// Estimated-meeting-cost badge for the header. Non-nil only when the user
    /// has the cost feature on AND the meeting has both attendees and a recorded
    /// duration — otherwise the badge is suppressed (no attendees ⇒ no cost basis,
    /// zero duration ⇒ a $0 chip that just adds noise).
    private var meetingCostChip: MeetingCost? {
        guard AppSettings.showMeetingCost,
              !meeting.attendees.isEmpty,
              meeting.duration > 0 else { return nil }
        return MeetingCostCalculator.estimate(
            attendees: meeting.attendees,
            duration: meeting.duration,
            hourlyRatePerPerson: AppSettings.hourlyRatePerPerson)
    }

    /// Empty-state block already shows the notice and primary action — skip the banner.
    private var emptyNotesHandlesNotice: Bool {
        !isRecordingThisMeeting
            && !isPrepMeeting
            && displayed.isEmpty
            && streaming == nil
            && app.processingStage[meeting.id] == nil
            && noticePresentation != nil
    }

    private var emptyNotesTitle: String {
        noticePresentation?.title ?? "No notes yet"
    }

    private var emptyNotesMessage: String {
        if let presentation = noticePresentation {
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

    private var isEmptyTranscriptNotice: Bool {
        MeetingNotice.effectivePresentation(for: meeting.notice, hasTranscript: hasTranscript)?
            .isEmptyTranscript == true
    }

    private var noticePresentation: MeetingNotice.Presentation? {
        MeetingNotice.effectivePresentation(for: meeting.notice, hasTranscript: hasTranscript)
    }

    private var noticePrimaryActionTitle: String? {
        // When resume is available, the action lives in the bottom safeAreaInset.
        if canContinueRecording { return nil }
        if meeting.state == .failed { return "Retry" }
        if meeting.notice != nil { return "Regenerate" }
        return nil
    }

    private var noticePrimaryActionIcon: String? {
        // Resume icon lives in the bottom bar now; only show icons for other actions.
        canContinueRecording ? nil : (noticePrimaryActionTitle != nil ? "arrow.clockwise" : nil)
    }

    private var noticePrimaryAction: (() -> Void)? {
        if canContinueRecording { return nil }
        if meeting.state == .failed || meeting.notice != nil {
            return { Task { await app.retry(meetingID: meeting.id) } }
        }
        return nil
    }

    private var emptyNotesTips: [String] {
        guard isEmptyTranscriptNotice else { return [] }
        var tips: [String] = []
        if showProminentJoinButton, let join = joinConference {
            tips.append("Join \(join.label.replacingOccurrences(of: "Join ", with: "")) and resume recording to capture the call.")
        }
        if !hasSideNotes {
            tips.append("Use My notes to jot down what happened — they stay with this meeting.")
        }
        if meeting.displaySourceApp != nil {
            tips.append("Make sure Ayrvo has microphone and system audio access in Settings.")
        }
        return Array(tips.prefix(2))
    }

    private var emptyNotesActionTitle: String? {
        if canContinueRecording { return "Resume recording" }
        if meeting.state == .failed { return "Retry" }
        return nil
    }

    private var emptyNotesActionIcon: String? {
        emptyNotesActionTitle == "Resume recording" ? "mic.fill" : nil
    }

    private var emptyNotesSecondaryActionTitle: String? {
        if isEmptyTranscriptNotice {
            return showSideNotes ? nil : "Write notes"
        }
        if displayed.isEmpty, app.store.transcript(for: meeting.id).isEmpty {
            return "View transcript"
        }
        return nil
    }

    private var emptyNotesSecondaryAction: (() -> Void)? {
        if isEmptyTranscriptNotice, !showSideNotes {
            return { showSideNotes = true }
        }
        if displayed.isEmpty, app.store.transcript(for: meeting.id).isEmpty {
            return { panelMode = .transcript }
        }
        return nil
    }

    private func presentTranscriptIfNeeded() {
        guard panelMode == nil else { return }
        guard emptyNotesHandlesNotice, isEmptyTranscriptNotice else { return }
        guard app.store.transcript(for: meeting.id).isEmpty else { return }
        panelMode = .transcript
    }

    private var emptyNotesAction: (() -> Void)? {
        if canContinueRecording {
            return { Task { await app.continueRecording(meetingID: meeting.id) } }
        }
        if meeting.state == .failed {
            return { Task { await app.retry(meetingID: meeting.id) } }
        }
        return nil
    }

    private var canContinueRecording: Bool {
        meeting.canContinueRecording(isRecording: app.isRecording)
    }

    private var eventHasEnded: Bool {
        if let end = meeting.calendarEventEnd ?? linkedCalendarEvent?.end {
            return end < .now
        }
        return meeting.duration > 0 && (meeting.state == .ready || meeting.state == .failed)
    }

    private var showProminentJoinButton: Bool {
        joinConference != nil && !eventHasEnded
    }

    private var linkedCalendarEvent: CalendarEventSummary? {
        guard let id = meeting.calendarEventID else { return nil }
        return app.calendar.event(id: id, start: meeting.calendarEventStart)
    }

    private var joinConference: (label: String, url: URL)? {
        guard let event = linkedCalendarEvent,
              let url = event.conferenceURL else { return nil }
        let peers = app.calendar.agenda.flatMap(\.events)
        guard event.shouldShowJoinButton(among: peers) else { return nil }
        return (event.joinLabel, url)
    }

    @discardableResult
    private func saveTitle() -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t != meeting.title else { return true }
        guard !t.isEmpty else {
            PersistenceStatus.shared.operationError = "A meeting needs a title."
            return false
        }
        guard var m = app.store.meeting(id: meeting.id) else { return false }
        m.title = t
        app.store.upsert(m)
        return FilePersistence.failure(at: app.store.archive.folder(for: m.id)
            .appendingPathComponent("meeting.json")) == nil
    }

    private func copyTranscript() {
        let segments = app.store.transcript(for: meeting.id)
        guard !segments.isEmpty else { return }
        let text = TranscriptFormatter.plainText(segments, speakers: meeting.speakers)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
