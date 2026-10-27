import AppKit
import SwiftUI

struct TemplateSettings: View {
    @Environment(\.ayrvoActionColor) private var actionColor
    @EnvironmentObject private var app: AppState
    @State private var templates: [SummaryTemplate] = []
    @State private var selected: String?
    @State private var draftName = ""
    @State private var draftBody = ""
    @State private var saveError: String?
    @State private var deleteError: String?
    @State private var showAISheet = false
    @State private var aiPrompt = ""
    @State private var aiError: String?
    @State private var isGenerating = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                List(templates, id: \.name, selection: $selected) { template in
                    Text(template.name).font(.ayrvo(12)).tag(template.name)
                }
                HStack(spacing: 8) {
                    Button {
                        var name = "New Template"
                        var n = 2
                        while templates.contains(where: { $0.name == name }) {
                            name = "New Template \(n)"; n += 1
                        }
                        do {
                            try app.templates.save(SummaryTemplate(
                                name: name,
                                body: "# {{title}}\n\n## Highlights\nWhat mattered most.\n"))
                            reload(select: name)
                        } catch { saveError = error.localizedDescription }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("New template")
                    .accessibilityLabel("New template")
                    Button {
                        guard let selected else {
                            AyrvoConsoleLog.app("[TemplateSettings] delete: no selection")
                            return
                        }
                        AyrvoConsoleLog.app("[TemplateSettings] delete: \(selected)")
                        do {
                            try app.templates.delete(named: selected)
                            AyrvoConsoleLog.app("[TemplateSettings] delete succeeded, reloading")
                            reload(select: nil)
                            deleteError = nil
                        } catch {
                            AyrvoConsoleLog.app("[TemplateSettings] delete failed: \(error)")
                            deleteError = error.localizedDescription
                        }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selected == nil)
                    .help("Delete template")
                    .accessibilityLabel("Delete template")
                    Button {
                        aiError = nil; showAISheet = true
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .help("Generate template with AI")
                    .accessibilityLabel("Generate template with AI")
                    Spacer()
                }
                .buttonStyle(.plain)
                .padding(8)
            }
            .frame(minWidth: 150, maxWidth: 200)

            VStack(alignment: .leading, spacing: 10) {
                if selected != nil {
                    TextField("Template name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .font(.ayrvo(13, .medium))
                    TextEditor(text: $draftBody)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    Text("Placeholders: {{title}} {{date}} {{attendees}} {{duration}} {{app}} — headings guide the AI; text under a heading tells it what belongs there.")
                        .font(.ayrvo(10))
                        .foregroundStyle(.secondary)
                    HStack {
                        if let saveError {
                            Label(saveError, systemImage: "exclamationmark.triangle")
                                .font(.ayrvo(11))
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Button {
                            aiError = nil; showAISheet = true
                        } label: {
                            Label("Generate with AI", systemImage: "sparkles")
                                .font(.ayrvo(12, .medium))
                        }
                        .buttonStyle(.bordered)
                        .tint(actionColor)
                        .help("Generate a new template with AI")
                        .accessibilityLabel("Generate a new template with AI")
                        Button("Save") { save() }
                            .buttonStyle(.borderedProminent)
                            .tint(actionColor)
                            .disabled(!TemplateStore.isValid(name: draftName))
                    }
                } else {
                    EmptyStateView(
                        title: "Templates",
                        message: "Pick a template to edit, or add one. Templates shape every summary Ayrvo writes.")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { reload(select: selected ?? templates.first?.name) }
        .onChange(of: selected) { loadDraft() }
        .sheet(isPresented: $showAISheet) {
            aiTemplateSheet
        }
    }

    private var aiTemplateSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Generate Template with AI")
                    .font(.ayrvo(15, .bold))
                Spacer()
                Button("Cancel") { showAISheet = false }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Text("Describe what kind of meeting template you need:")
                .font(.ayrvo(12))
                .foregroundStyle(.secondary)
            TextEditor(text: $aiPrompt)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .frame(height: 80)
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            Text("Available placeholders: {{title}} {{date}} {{attendees}} {{duration}} {{app}}")
                .font(.ayrvo(10))
                .foregroundStyle(.secondary)
            HStack {
                if let aiError {
                    Label(aiError, systemImage: "exclamationmark.triangle")
                        .font(.ayrvo(11))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button(isGenerating ? "Generating…" : "Generate") {
                    generateTemplate()
                }
                .buttonStyle(.borderedProminent)
                .tint(actionColor)
                .disabled(isGenerating || aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func generateTemplate() {
        let promptText = aiPrompt.trimmingCharacters(in: .whitespaces)
        guard !promptText.isEmpty else { return }
        aiError = nil
        isGenerating = true
        let prompt = """
        Create a meeting notes template in Markdown. \(promptText)
        Use these placeholders: {{title}} {{date}} {{attendees}} {{duration}} {{app}}.
        Use ## headings to guide the AI summarizer — text under a heading tells it what belongs there.
        Return ONLY the markdown template, no explanation.
        """
        Task {
            do {
                let result = try await AIAsk.answer(prompt: prompt)
                // Sanitize the prompt into a valid template name — TemplateStore
                // rejects "/" and ":" (used as path separators), and we prefix
                // with "AI " so generated templates group together in the list.
                var raw = String(promptText.prefix(40)).trimmingCharacters(in: .whitespaces)
                raw = raw.replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                    .replacingOccurrences(of: "\n", with: " ")
                let baseName = raw.isEmpty ? "AI Template" : "AI - \(raw)"
                let finalName = nextUniqueTemplateName(baseName)
                try app.templates.save(SummaryTemplate(name: finalName, body: result))
                await MainActor.run {
                    isGenerating = false
                    showAISheet = false
                    aiPrompt = ""
                    reload(select: finalName)
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    aiError = error.localizedDescription
                }
            }
        }
    }

    /// Returns `baseName`, or `baseName 2`, `baseName 3`, … — whatever isn't
    /// already in `templates`. Avoids TemplateError.nameTaken on AI generation.
    private func nextUniqueTemplateName(_ baseName: String) -> String {
        let existing = Set(templates.map { $0.name.lowercased() })
        guard existing.contains(baseName.lowercased()) else { return baseName }
        var n = 2
        while existing.contains("\(baseName) \(n)".lowercased()) { n += 1 }
        return "\(baseName) \(n)"
    }

    private func reload(select: String?) {
        templates = app.templates.list()
        selected = select ?? templates.first?.name
        loadDraft()
    }

    private func loadDraft() {
        saveError = nil // don't carry a rename error onto another template
        guard let selected, let t = templates.first(where: { $0.name == selected }) else {
            draftName = ""; draftBody = ""
            return
        }
        draftName = t.name
        draftBody = t.body
    }

    private func save() {
        guard let selected else { return }
        let newName = draftName.trimmingCharacters(in: .whitespaces)
        do {
            try app.templates.rename(from: selected, to: newName, body: draftBody)
            saveError = nil
            reload(select: newName)
        } catch {
            saveError = error.localizedDescription
        }
    }
}
