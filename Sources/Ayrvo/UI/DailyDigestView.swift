import SwiftUI
import AppKit

/// The Daily Digest page — a briefing of today's or yesterday's meetings,
/// plus an Activity Tracker that turns the digest's action items into a
/// persistent, filterable todo list.
///
/// The digest is generated on demand (Start Digest); the tracker is always
/// present, auto-synced from meeting summaries, and manually editable. The
/// digest feeds the tracker: clicking "Track" on a digest action item adds
/// it to the persistent list.
struct DailyDigestView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    // Digest state
    @State private var digest: DailyDigest?
    @State private var isGenerating = false
    @State private var digestMode: DigestMode = .today
    @State private var showRenameSheet = false
    @State private var showMergeSheet = false
    @State private var renameFrom = ""
    @State private var mergeFrom = ""
    private let generator = DailyDigestGenerator()
    private var tracker: TaskTrackerStore { app.tracker }

    enum DigestMode: String, CaseIterable, Identifiable {
        case today = "Today so far"
        case yesterday = "Yesterday"
        var id: String { rawValue }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                modePicker

                // Action items list — uses cachedDigest so it persists.
                if let digest {
                    DigestActionItemsView(
                        tracker: tracker, digest: digest,
                        onRenameOwner: renameOwner, onMergeOwner: mergeOwner)
                }

                DigestTrackerView(
                    tracker: tracker, calendar: app.calendar, onRenameOwner: renameOwner)

                // Digest briefing — meetings + agenda.
                if let digest {
                    DigestBriefingView(digest: digest, digestMode: digestMode)
                } else {
                    emptyState
                }
            }
            .padding(24)
            .contentColumn()
        }
        .background(Theme.surface(scheme))
        .onAppear {
            if digest == nil { generateDigest() }
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameOwnerSheet(from: renameFrom) { newName in
                tracker.renameOwner(from: renameFrom, to: newName)
                tracker.addAlias(from: renameFrom, to: newName)
                showRenameSheet = false
            }
        }
        .sheet(isPresented: $showMergeSheet) {
            MergeOwnerSheet(
                from: mergeFrom,
                existingOwners: tracker.owners
            ) { target in
                tracker.addAlias(from: mergeFrom, to: target)
                showMergeSheet = false
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Daily Digest")
                .font(.ayrvo(22, .bold))
                .foregroundStyle(Theme.heading(scheme))
            Text("Get a quick briefing of your meetings and action items.")
                .font(.ayrvo(13))
                .foregroundStyle(Theme.secondary(scheme))
        }
    }

    // MARK: - Mode picker + Start button

    private var modePicker: some View {
        HStack(spacing: 12) {
            Picker("Mode", selection: $digestMode) {
                ForEach(DigestMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            Spacer()

            Button {
                generateDigest()
            } label: {
                Label(isGenerating ? "Generating…" : "Start Digest",
                      systemImage: isGenerating ? "arrow.clockwise" : "play.fill")
                    .font(.ayrvo(13, .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.mint(scheme))
            .clipShape(Capsule())
            .disabled(isGenerating)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.tertiary(scheme))
            Text("No digest generated yet")
                .font(.ayrvo(14, .semibold))
                .foregroundStyle(Theme.secondary(scheme))
            Text("Click **Start Digest** to get a summary of your "
                + "\(digestMode == .today ? "day so far" : "yesterday").")
                .font(.ayrvo(12))
                .foregroundStyle(Theme.tertiary(scheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func renameOwner(_ owner: String) {
        renameFrom = owner
        showRenameSheet = true
    }

    private func mergeOwner(_ owner: String) {
        mergeFrom = owner
        showMergeSheet = true
    }

    // MARK: - Generation

    private func generateDigest() {
        isGenerating = true
        let meetings = app.store.meetings
        let agenda = app.calendar.upcomingDays(limit: 10).flatMap(\.events)
        let summaries = Dictionary(
            uniqueKeysWithValues: meetings.map { ($0.id, app.store.summary(for: $0.id)) })

        let result: DailyDigest
        switch digestMode {
        case .today:
            result = generator.generateToday(
                for: Date(), meetings: meetings, agenda: agenda, summaries: summaries)
        case .yesterday:
            result = generator.generate(
                for: Date(), meetings: meetings, agenda: agenda, summaries: summaries)
        }
        digest = result
        isGenerating = false
    }
}
