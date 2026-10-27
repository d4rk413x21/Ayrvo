import AppKit
import SwiftUI

struct MeetingDetailView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @FocusState private var isEditingTitle: Bool
    @State private var meeting: Meeting
    @State private var panelMode: GranolaPanelMode?
    @State private var title: String
    @State private var previewError: String?
    @State private var showDeleteConfirm = false
    @State private var notesDraft: String?
    @State private var transcriptDraft: String?
    @State private var sideNotesDraft = MeetingSideNotesDraft()
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
                        text: Binding(get: { sideNotes }, set: { sideNotesDraft.edit($0) }),
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
                MeetingRecordingFooter(
                    label: join.label,
                    url: join.url,
                    calendarEvent: linkedCalendarEvent,
                    canResume: canContinueRecording,
                    onResume: { Task { await app.continueRecording(meetingID: meeting.id) } })
            }
        }
        .task { await app.calendar.refreshAgenda() }
        .trackingEdits(isDirty: { hasUnsavedEdits }, save: {
            guard saveNotesEdits() else { return false }
            return saveTitle()
        }, discard: {
            title = meeting.title
            discardNotesEdits()
        })
        .onAppear {
            loadSideNotes()
            presentTranscriptIfNeeded()
        }
        .onDisappear(perform: flushSideNotes)
        .onReceive(NotificationCenter.default.publisher(for: .ayrvoFlushEdits)) { _ in
            flushSideNotes()
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

    private var sideNotes: String { sideNotesDraft.text }

    private var hasSideNotes: Bool {
        !sideNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadSideNotes() {
        sideNotesDraft.load(app.store.sideNotes(for: meeting.id))
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

    @discardableResult
    private func saveNotesEdits() -> Bool {
        guard let draft = notesDraft else { return true }
        guard app.store.saveSummarySafely(draft, for: meeting.id) else { return false }
        notesDraft = nil
        return true
    }

    private func scheduleSideNotesSave() {
        guard sideNotesDraft.needsFlush else { return }
        sideNotesSaveTask?.cancel()
        sideNotesSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            sideNotesSaveTask = nil
            flushSideNotes()
        }
    }

    private func flushSideNotes() {
        sideNotesSaveTask?.cancel()
        sideNotesSaveTask = nil
        guard app.store.meeting(id: meeting.id) != nil else { return }
        sideNotesDraft.flush { app.store.saveSideNotes($0, for: meeting.id) }
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

    private var documentScroll: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 20) {
                    MeetingDocumentHeader(
                        meeting: meeting,
                        title: $title,
                        titleFocus: $isEditingTitle,
                        showSideNotes: $showSideNotes,
                        hasSideNotes: hasSideNotes,
                        hasSummary: !summary.isEmpty,
                        hasEmptyTranscriptNotice: isEmptyTranscriptNotice,
                        join: showProminentJoinButton ? nil : joinConference,
                        processingStage: app.processingStage[meeting.id],
                        folders: app.folders,
                        onSaveTitle: { saveTitle() })
                    noticeBanner
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
                .frame(minHeight: notesLayout.centersContent ? geo.size.height : nil, alignment: .top)
                .padding(.horizontal, 28)
                .padding(.bottom, panelMode != nil ? 340 : 100)
            }
        }
    }

    // MARK: - Notes

    private var summary: String { app.store.summary(for: meeting.id) }
    private var streaming: String? { app.streamingSummaries[meeting.id] }
    private var displayed: String { streaming ?? summary }

    private var notesLayout: MeetingNotesLayout {
        MeetingNotesLayout(
            isRecording: isRecordingThisMeeting,
            isPrep: isPrepMeeting,
            isEditing: notesDraft != nil,
            hasDisplayedNotes: !displayed.isEmpty,
            isWorking: streaming != nil || app.processingStage[meeting.id] != nil,
            hasSideNotes: hasSideNotes,
            showsSideNotes: showSideNotes)
    }

    private var notesSection: some View {
        MeetingNotesSection(
            layout: notesLayout,
            sideNotes: sideNotes,
            showsSideNotes: $showSideNotes,
            draft: $notesDraft,
            processingStage: app.processingStage[meeting.id],
            reader: MeetingSummaryView(
                markdown: displayed,
                progress: app.summaryProgress[meeting.id],
                canEdit: !summary.isEmpty && streaming == nil,
                templates: app.templates,
                currentProvider: meeting.summaryProvider,
                onEdit: { notesDraft = app.store.summary(for: meeting.id) },
                onRegenerate: { template, provider in
                    Task { await app.regenerateSummary(meetingID: meeting.id, templateName: template, forceProvider: provider) }
                }),
            emptyNotes: MeetingEmptyNotesView(
                meeting: meeting,
                hasTranscript: hasTranscript,
                hasSideNotes: hasSideNotes,
                showSideNotes: $showSideNotes,
                canContinueRecording: canContinueRecording,
                resumesInFooter: showProminentJoinButton && canContinueRecording,
                joinLabel: showProminentJoinButton ? joinConference?.label : nil,
                onResume: { Task { await app.continueRecording(meetingID: meeting.id) } },
                onRetry: { Task { await app.retry(meetingID: meeting.id) } },
                onShowTranscript: { panelMode = .transcript }),
            onSave: { saveNotesEdits() },
            onCancel: discardNotesEdits)
    }

    private var hasTranscript: Bool {
        !app.store.transcript(for: meeting.id).isEmpty
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

    /// Empty-state block already shows the notice and primary action — skip the banner.
    private var emptyNotesHandlesNotice: Bool {
        notesLayout.content == .empty && noticePresentation != nil
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

    private func presentTranscriptIfNeeded() {
        guard panelMode == nil else { return }
        guard emptyNotesHandlesNotice, isEmptyTranscriptNotice else { return }
        guard app.store.transcript(for: meeting.id).isEmpty else { return }
        panelMode = .transcript
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
