import SwiftUI
import AppKit

struct DigestTrackerView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.ayrvoActionColor) private var actionColor
    @ObservedObject var tracker: TaskTrackerStore
    @ObservedObject var calendar: CalendarStore
    let onRenameOwner: (String) -> Void

    @State private var showAddSheet = false
    @State private var editingTask: TrackedTask?
    @State private var filterOwner: String? // nil = "mine"
    @State private var filterTag: String?
    @State private var showCompleted = false
    @State private var showPrepSection = true

    private var filteredTasks: [TrackedTask] {
        tracker.sortedTasks.filter { task in
            if !showCompleted && task.isChecked { return false }
            if let filterOwner, task.owner != filterOwner { return false }
            if let filterTag, !task.tags.contains(filterTag) { return false }
            if filterOwner == nil && !task.isMine { return false }
            return true
        }
    }

    private var prepTasks: [TrackedTask] {
        tracker.sortedTasks.filter { $0.calendarEventID != nil && !$0.isChecked }
    }

    private var upcomingForPrep: [CalendarEventSummary] {
        let agenda = calendar.upcomingDays(limit: 5).flatMap(\.events)
        let existingIDs = Set(tracker.tasks.compactMap { $0.calendarEventID })
        return agenda.filter { event in
            event.start >= Date() && !existingIDs.contains(event.id)
        }
    }

    private var unknownOwners: [String] {
        tracker.owners.filter { owner in
            owner.lowercased().hasPrefix("speaker ") || owner.lowercased().contains("unknown")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            trackerHeader
            insightsCard
            if !prepTasks.isEmpty || !upcomingForPrep.isEmpty {
                prepSection
            }
            filterBar
            taskList
        }
        .sheet(isPresented: $showAddSheet) {
            TaskEditSheet(task: nil) { newTask in
                tracker.add(
                    text: newTask.text,
                    detail: newTask.detail,
                    owner: newTask.owner,
                    isMine: newTask.isMine,
                    priority: newTask.priority,
                    tags: newTask.tags,
                    dueDate: newTask.dueDate)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingTask != nil },
            set: { if !$0 { editingTask = nil } })
        ) {
            if let task = editingTask {
                TaskEditSheet(task: task) { updated in
                    tracker.update(updated)
                    editingTask = nil
                }
            }
        }
    }

    private var trackerHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Activity Tracker")
                .font(.ayrvo(16, .bold))
                .foregroundStyle(Theme.heading(scheme))
            Spacer()
            Button {
                showAddSheet = true
            } label: {
                Label("Add Task", systemImage: "plus")
                    .font(.ayrvo(12, .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(actionColor)
            .clipShape(Capsule())
        }
    }

    private var insightsCard: some View {
        let insights = tracker.dailyInsights(for: 7)
        let totalOpen = tracker.openCount
        let totalDone = tracker.completedCount
        let rate = tracker.completionRate

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .font(.ayrvo(13, .medium))
                    .foregroundStyle(Theme.blueberry(scheme))
                Text("This Week")
                    .font(.ayrvo(14, .semibold))
                    .foregroundStyle(Theme.heading(scheme))
                Spacer()
                Text("\(totalDone) done \u{00B7} \(totalOpen) open \u{00B7} \(Int(rate * 100))%")
                    .font(.ayrvo(11, .medium))
                    .foregroundStyle(Theme.secondary(scheme))
            }
            TaskInsightsChart(insights: insights, accent: actionColor)
                .frame(height: 80)
        }
        .padding(16)
        .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Mine") { filterOwner = nil }
                ForEach(tracker.owners, id: \.self) { owner in
                    Button(owner) { filterOwner = owner }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10))
                    Text(filterOwner ?? "Mine")
                        .font(.ayrvo(12, .medium))
                }
                .foregroundStyle(Theme.heading(scheme))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if !tracker.allTags.isEmpty {
                Menu {
                    Button("All tags") { filterTag = nil }
                    ForEach(tracker.allTags, id: \.self) { tag in
                        Button(tag) { filterTag = tag }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 10))
                        Text(filterTag ?? "All tags")
                            .font(.ayrvo(12, .medium))
                    }
                    .foregroundStyle(Theme.heading(scheme))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Toggle(isOn: $showCompleted) {
                Text("Show completed")
                    .font(.ayrvo(11, .medium))
            }
            .toggleStyle(.checkbox)
            .font(.ayrvo(11))

            Spacer()

            if !unknownOwners.isEmpty {
                Menu {
                    ForEach(unknownOwners, id: \.self) { owner in
                        Button("Rename \(owner)\u{2026}") {
                            onRenameOwner(owner)
                        }
                    }
                } label: {
                    Label("Fix names", systemImage: "person.text.rectangle")
                        .font(.ayrvo(11, .medium))
                }
                .menuStyle(.borderlessButton)
            }

            if tracker.completedCount > 0 {
                Button {
                    tracker.clearCompleted()
                } label: {
                    Text("Clear done")
                        .font(.ayrvo(11, .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var taskList: some View {
        Group {
            if filteredTasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Theme.tertiary(scheme))
                    Text(tracker.tasks.isEmpty ? "No tasks yet" : "Nothing matches your filters")
                        .font(.ayrvo(14, .semibold))
                        .foregroundStyle(Theme.secondary(scheme))
                    Text(tracker.tasks.isEmpty
                        ? "Tasks from your meeting summaries will appear here automatically. You can also add one manually."
                        : "Try changing the owner filter or showing completed tasks.")
                        .font(.ayrvo(12))
                        .foregroundStyle(Theme.tertiary(scheme))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredTasks) { task in
                        TrackerTaskRow(task: task, onTap: {
                            tracker.toggle(id: task.id)
                        }, onEdit: {
                            editingTask = task
                        }, onDelete: {
                            tracker.delete(id: task.id)
                        }, onClaim: {
                            tracker.claimOwnership(id: task.id)
                        })
                    }
                }
            }
        }
    }

    private var prepSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar.badge.plus")
                    .font(.ayrvo(13, .medium))
                    .foregroundStyle(Theme.honey(scheme))
                Text("Prep for upcoming meetings")
                    .font(.ayrvo(14, .semibold))
                    .foregroundStyle(Theme.heading(scheme))
                Spacer()
                Button {
                    withAnimation { showPrepSection.toggle() }
                } label: {
                    Image(systemName: showPrepSection
                        ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.secondary(scheme))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(showPrepSection ? "Collapse meeting preparation" : "Expand meeting preparation")
            }
            if showPrepSection {
                VStack(alignment: .leading, spacing: 8) {
                    // Existing prep tasks
                    if !prepTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(prepTasks) { task in
                                TrackerTaskRow(task: task, onTap: {
                                    tracker.toggle(id: task.id)
                                }, onEdit: {
                                    editingTask = task
                                }, onDelete: {
                                    tracker.delete(id: task.id)
                                }, onClaim: {
                                    tracker.claimOwnership(id: task.id)
                                })
                            }
                        }
                    }
                    // Add-prep buttons for upcoming events without one yet
                    if !upcomingForPrep.isEmpty {
                        if !prepTasks.isEmpty {
                            Divider().padding(.vertical, 2)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Quick add")
                                .font(.ayrvo(9, .semibold))
                                .foregroundStyle(Theme.tertiary(scheme))
                                .textCase(.uppercase)
                            ForEach(upcomingForPrep, id: \.rowID) { event in
                                Button {
                                    tracker.add(
                                        text: "Prep for \(event.title)",
                                        detail: nil,
                                        isMine: true,
                                        priority: .normal,
                                        tags: ["prep"],
                                        source: nil,
                                        calendarEventID: event.id)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 9))
                                            .foregroundStyle(actionColor)
                                        Text(event.title)
                                            .font(.ayrvo(11, .medium))
                                            .foregroundStyle(
                                                Theme.secondary(scheme))
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                        Text(event.start,
                                            format: .dateTime
                                                .month().day().hour().minute())
                                            .font(.ayrvo(9))
                                            .foregroundStyle(
                                                Theme.tertiary(scheme))
                                    }
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

}
