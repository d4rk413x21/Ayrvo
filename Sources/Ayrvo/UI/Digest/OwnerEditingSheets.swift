import SwiftUI
import AppKit

struct RenameOwnerSheet: View {
    let from: String
    let onRename: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newName: String

    init(from: String, onRename: @escaping (String) -> Void) {
        self.from = from
        self.onRename = onRename
        _newName = State(initialValue: from)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename owner")
                .font(.ayrvo(16, .bold))
            Text("This will update all tasks assigned to \(from).")
                .font(.ayrvo(12))
                .foregroundStyle(.secondary)
            TextField("New name", text: $newName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Rename") {
                    let trimmed = newName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { onRename(trimmed) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}

// MARK: - Merge owner sheet

struct MergeOwnerSheet: View {
    let from: String
    let existingOwners: [String]
    let onMerge: (String) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var target: String
    @State private var useExisting = false

    init(
        from: String,
        existingOwners: [String],
        onMerge: @escaping (String) -> Void
    ) {
        self.from = from
        self.existingOwners = existingOwners
        self.onMerge = onMerge
        let others = existingOwners.filter { $0.lowercased() != from.lowercased() }
        _target = State(initialValue: others.first ?? "")
        _useExisting = State(initialValue: !others.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Merge owners")
                .font(.ayrvo(16, .bold))
                .foregroundStyle(Theme.heading(scheme))
            Text("Merge \"\(from)\" into another owner. All their tasks will be reassigned.")
                .font(.ayrvo(12))
                .foregroundStyle(.secondary)

            let others = existingOwners.filter {
                $0.lowercased() != from.lowercased()
            }
            if !others.isEmpty {
                Toggle("Merge into existing owner", isOn: $useExisting)
                    .font(.ayrvo(12))
                if useExisting {
                    Picker("Owner", selection: $target) {
                        ForEach(others, id: \.self) { owner in
                            Text(owner).tag(owner)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    TextField("New owner name", text: $target)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                TextField("New owner name", text: $target)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Merge") {
                    let trimmed = target.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { onMerge(trimmed) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.mint(scheme))
                .disabled(target.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
