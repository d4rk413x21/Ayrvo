import AppKit
import SwiftUI

/// Shared launcher: hero compose field, recents, and recipe chips for the user's assistant.
struct AILauncherView: View {
    let headline: String
    let subtitle: String?
    let suggestions: [String]
    var recentMeetings: [Meeting] = []
    var contextMeeting: Meeting?
    /// Pre-seeds and auto-submits a question on first appear (used by the
    /// floating panel's suggestion chips to route through the in-app CLI
    /// streaming UI instead of always opening the external app).
    var initialQuestion: String?
    let promptBuilder: (String) -> String
    var meetingPromptBuilder: ((Meeting, String) -> String)?

    @EnvironmentObject private var app: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.preferredAIProvider) private var preferredAIProvider: AIProvider = .apple
    @AppStorage(SettingsKey.askDeliveryMode) private var askDeliveryMode: AskDeliveryMode = .cli
    @AppStorage(SettingsKey.askMaxTurns) private var askMaxTurns = 5
    @State private var input = ""
    @State private var available = false
    @State private var deliveryModeAvailability: [AskDeliveryMode: Bool] = [:]
    @State private var launchFailed = false
    @State private var conversation = AskConversation()
    private var messages: [AskChatMessage] { conversation.messages }
    private var isAnswering: Bool { conversation.isAnswering }
    @State private var answerTask: Task<Void, Never>?
    @State private var didSubmitInitialQuestion = false
    @State private var didSaveRecipe = false
    @FocusState private var composeFocused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.ayrvoActionColor) private var actionColor
    @StateObject private var recipeStore = RecipeStore()

    private var isConversationMode: Bool {
        !messages.isEmpty
    }

    private var effectiveMode: AskDeliveryMode {
        preferredAIProvider.supportsApp ? askDeliveryMode : .cli
    }

    var body: some View {
        Group {
            if isConversationMode {
                conversationBody
            } else {
                launcherBody
            }
        }
        .background(Theme.surface(scheme))
        .onAppear {
            refreshAvailability()
            seedRecipesFromSuggestionsIfNeeded()
            submitInitialQuestionIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ayrvoCLIAvailabilityChanged)) { _ in
            refreshAvailability()
        }
        .onChange(of: preferredAIProvider) {
            refreshAvailability()
            if isAnswering { stopAnswering() }
        }
        .onChange(of: askDeliveryMode) {
            refreshAvailability()
            if isAnswering { stopAnswering() }
        }
        .onDisappear { stopAnswering() }
    }

    private var launcherBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                composer

                if showsLongTranscriptHint {
                    longTranscriptHint
                }

                if !recentMeetings.isEmpty, meetingPromptBuilder != nil {
                    AskRecentMeetings(
                        recentMeetings: recentMeetings, isEnabled: available && !isAnswering, onSelect: launchRecent)
                }

                AskRecipesView(recipeStore: recipeStore, isEnabled: available && !isAnswering, onSelect: launch)
                statusNotices
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 44)
            .contentColumn()
        }
    }

    private var conversationBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    conversationHeader
                    chatSection
                }
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .padding(.bottom, 16)
                .contentColumn()
            }

            VStack(alignment: .leading, spacing: 12) {
                composer

                if showsLongTranscriptHint {
                    longTranscriptHint
                }

                statusNotices
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .contentColumn()
        }
    }

    private var conversationHeader: some View {
        HStack(alignment: .center) {
            Text(headline)
                .font(.ayrvo(20, .bold))
                .foregroundStyle(Theme.heading(scheme))
                .lineLimit(1)
            Spacer(minLength: 12)
            Button("New conversation", action: newConversation)
                .font(.ayrvo(12, .medium))
                .buttonStyle(.plain)
                .foregroundStyle(actionColor)
            closeButton
        }
    }

    private func newConversation() {
        stopAnswering()
        conversation.messages = []
        input = ""
        launchFailed = false
        composeFocused = true
    }

    private func refreshAvailability() {
        let provider = preferredAIProvider
        let mode = effectiveMode
        Task.detached {
            var byMode: [AskDeliveryMode: Bool] = [:]
            for deliveryMode in AskDeliveryMode.allCases {
                byMode[deliveryMode] = AIAsk.isAvailable(for: deliveryMode, provider: provider)
            }
            let availability = byMode
            await MainActor.run {
                deliveryModeAvailability = availability
                available = availability[mode] ?? false
            }
        }
    }

    private var contextTranscriptChars: Int {
        guard let contextMeeting else { return 0 }
        return app.store.transcript(for: contextMeeting.id)
            .reduce(0) { $0 + $1.text.count }
    }

    private var showsLongTranscriptHint: Bool {
        askDeliveryMode == .cli
            && contextTranscriptChars > 20_000
            && askMaxTurns < 8
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.ayrvo(26, .bold))
                    .foregroundStyle(Theme.heading(scheme))
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.ayrvo(13))
                        .foregroundStyle(Theme.secondary(scheme))
                }
            }
            Spacer(minLength: 8)
            closeButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.tertiary(scheme))
        }
        .buttonStyle(.plain)
        .help("Close")
        .accessibilityLabel("Close")
    }

    private var composer: some View {
        AskComposer(
            input: $input, focus: $composeFocused, available: available,
            isAnswering: isAnswering, didSaveRecipe: didSaveRecipe,
            preferredAIProvider: preferredAIProvider, effectiveMode: effectiveMode,
            deliveryModeAvailability: deliveryModeAvailability,
            launchTyped: launchTyped, stopAnswering: stopAnswering,
            saveCurrentInputAsRecipe: saveCurrentInputAsRecipe)
    }

    private var statusNotices: some View {
        AskStatusNotices(preferredAIProvider: preferredAIProvider, askDeliveryMode: askDeliveryMode,
                         available: available, launchFailed: launchFailed)
    }

    private var chatSection: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(messages) { message in
                AskChatBubble(message: message)
            }
        }
    }

    private var longTranscriptHint: some View {
        HStack(spacing: 6) {
            Text("This meeting has a long transcript — increase context rounds for better answers.")
                .font(.ayrvo(11))
                .foregroundStyle(Theme.tertiary(scheme))
            Button("Settings") { openSettings() }
                .font(.ayrvo(11, .medium))
                .buttonStyle(.plain)
                .foregroundStyle(actionColor)
        }
    }

    private func launchRecent(_ meeting: Meeting) {
        guard let builder = meetingPromptBuilder else { return }
        let question = "What were the key takeaways?"
        submit(
            displayText: "\(meeting.title) — \(question)",
            prompt: builder(meeting, question)
        )
    }

    private func launch(_ question: String) {
        submit(displayText: question, prompt: promptBuilder(question))
    }

    private func submit(displayText: String, prompt: String) {
        launchFailed = false
        conversation.messages.append(AskChatMessage(role: .user, text: displayText))

        switch effectiveMode {
        case .app:
            launchFailed = !AIAsk.open(prompt: prompt)
            if !launchFailed { input = "" }
        case .cli:
            guard available else {
                launchFailed = true
                return
            }
            beginCLIAnswer(prompt: prompt)
        }
    }

    private func beginCLIAnswer(prompt: String) {
        answerTask?.cancel()
        let responseID = conversation.beginResponse()
        answerTask = Task { @MainActor in
            do {
                let text = try await AIAsk.answer(prompt: prompt) { delta in
                    Task { @MainActor in
                        conversation.updateResponse(responseID, text: delta)
                    }
                }
                try Task.checkCancellation()
                if conversation.updateResponse(responseID, text: text, finished: true) {
                    answerTask = nil
                }
            } catch {
                if Task.isCancelled {
                    if conversation.cancelResponse(responseID) { answerTask = nil }
                } else if conversation.updateResponse(responseID, text: error.localizedDescription,
                                                       finished: true, isError: true) {
                    AyrvoConsoleLog.ask("answer failed — \(error.localizedDescription)")
                    launchFailed = true
                    answerTask = nil
                }
            }
        }
    }

    private func stopAnswering() {
        answerTask?.cancel()
        conversation.cancelResponse()
        answerTask = nil
    }

    private func launchTyped() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isAnswering else { return }
        input = ""
        launch(text)
    }
    private func submitInitialQuestionIfNeeded() {
        guard !didSubmitInitialQuestion, let question = initialQuestion?.trimmingCharacters(in: .whitespaces), !question.isEmpty else { return }
        didSubmitInitialQuestion = true
        launch(question)
    }

    /// One-shot seed: the first time the launcher appears, copy the built-in
    /// `suggestions` into the user's recipe library so the chips look exactly
    /// as before this feature. Gated by a UserDefaults flag (`didSeedRecipes`)
    /// rather than "library is empty" so a user who deletes every recipe
    /// doesn't get the defaults silently re-added on the next appear.
    private func seedRecipesFromSuggestionsIfNeeded() {
        guard !AppSettings.defaults.bool(forKey: SettingsKey.didSeedRecipes),
              !suggestions.isEmpty else { return }
        for suggestion in suggestions {
            recipeStore.add(name: suggestion, prompt: suggestion)
        }
        AppSettings.defaults.set(true, forKey: SettingsKey.didSeedRecipes)
    }

    private func saveCurrentInputAsRecipe() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let name = String(text.prefix(40))
        recipeStore.add(name: name, prompt: text)
        didSaveRecipe = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didSaveRecipe = false }
    }
}
