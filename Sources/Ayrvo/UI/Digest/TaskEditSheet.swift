import SwiftUI
import AppKit

struct TaskEditSheet: View {
    let task: TrackedTask?
    let onSave: (TrackedTask) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var detail: String
    @State private var owner: String
    @State private var isMine: Bool
    @State private var priority: TaskPriority
    @State private var tags: [String]
    @State private var dueDate: Date?

    init(task: TrackedTask?, onSave: @escaping (TrackedTask) -> Void) {
        self.task = task
        self.onSave = onSave
        _text = State(initialValue: task?.text ?? "")
        _detail = State(initialValue: task?.detail ?? "")
        _owner = State(initialValue: task?.owner ?? AppSettings.currentUserName)
        _isMine = State(initialValue: task?.isMine ?? true)
        _priority = State(initialValue: task?.priority ?? .normal)
        _tags = State(initialValue: task?.tags ?? [])
        _dueDate = State(initialValue: task?.dueDate)
    }

    private var isEditing: Bool { task != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "Edit Task" : "New Task")
                .font(.ayrvo(16, .bold))
                .foregroundStyle(Theme.heading(scheme))

            VStack(alignment: .leading, spacing: 8) {
                TextField("Task", text: $text)
                    .textFieldStyle(.roundedBorder)

                TextField("Description (optional)", text: $detail, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...)

                HStack(spacing: 12) {
                    TextField("Owner", text: $owner)
                        .textFieldStyle(.roundedBorder)

                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Toggle("This is my task", isOn: $isMine)
                    .font(.ayrvo(12))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save") { saveAndDismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.mint(scheme))
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func saveAndDismiss() {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        guard !trimmedText.isEmpty else { return }

        if var existing = task {
            existing.text = trimmedText
            existing.detail = detail.isEmpty ? nil : detail
            existing.owner = owner.isEmpty ? nil : owner
            existing.isMine = isMine
            if existing.priority != priority {
                existing.priority = priority
                existing.priorityOverridden = true
            }
            existing.tags = tags
            existing.dueDate = dueDate
            onSave(existing)
        } else {
            let newTask = TrackedTask(
                text: trimmedText,
                detail: detail.isEmpty ? nil : detail,
                owner: owner.isEmpty ? nil : owner,
                isMine: isMine,
                priority: priority,
                priorityOverridden: true,
                isChecked: false,
                source: nil,
                tags: tags,
                createdAt: Date(),
                completedAt: nil,
                dueDate: dueDate,
                calendarEventID: nil)
            onSave(newTask)
        }
        dismiss()
    }
}
