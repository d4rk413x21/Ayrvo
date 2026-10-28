import AppKit
import SwiftUI

enum GranolaPanelMode: Equatable {
  case transcript
  case ask
}

struct GranolaFloatingPanel: View {
  @EnvironmentObject private var app: AppState
  @Environment(\.colorScheme) private var scheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.ayrvoActionColor) private var actionColor

  let meeting: Meeting
  @Binding var mode: GranolaPanelMode?
  @Binding var transcriptDraft: String?

  @State private var askInput = ""

  @State private var askAvailable = false
  @State private var showAskSheet = false
  @State private var askSheetQuestion: String?
  @AppStorage(SettingsKey.preferredAIProvider) private var preferredAIProvider: AIProvider = .apple
  @AppStorage(SettingsKey.askDeliveryMode) private var askDeliveryMode: AskDeliveryMode = .cli

  private var isExpanded: Bool { mode != nil }
  private var segments: [TranscriptSegment] { app.store.transcript(for: meeting.id) }
  private var isLive: Bool {
    app.session?.meetingID == meeting.id
  }

  private var isPrep: Bool {
    meeting.state == .prep && !isLive
  }

  private var summaryText: String { app.store.summary(for: meeting.id) }

  private var canAskAboutMeeting: Bool {
    askAvailable && (!segments.isEmpty || !summaryText.isEmpty)
  }

  private func refreshAskAvailability() {
    let provider = preferredAIProvider
    let mode = AppSettings.askDeliveryMode
    Task.detached {
      let available = AIAsk.isAvailable(for: mode, provider: provider)
      await MainActor.run { askAvailable = available }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      if isExpanded {
        expandedContent
          .transition(.move(edge: .bottom).combined(with: .opacity))
      } else {
        collapsedBar
      }
    }
    .frame(maxWidth: 560)
    .floatingSurface(in: RoundedRectangle(cornerRadius: isExpanded ? 20 : 28), opaque: isExpanded)
    .padding(.horizontal, 24)
    .padding(.bottom, 16)
    // Respect "Reduce Motion": skip the spring when the user has it enabled.
    .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: mode)
    .onAppear { refreshAskAvailability() }
    .onReceive(NotificationCenter.default.publisher(for: .ayrvoCLIAvailabilityChanged)) { _ in
      refreshAskAvailability()
    }
    .onChange(of: preferredAIProvider) { refreshAskAvailability() }
    .onChange(of: askDeliveryMode) { refreshAskAvailability() }
    .sheet(isPresented: $showAskSheet) {
      MeetingLauncherView(meeting: meeting, initialQuestion: askSheetQuestion)
        .frame(minWidth: 560, minHeight: 480)
    }
  }

  // MARK: Expanded body

  @ViewBuilder
  private var expandedContent: some View {
    switch mode {
    case .transcript:
      MeetingTranscriptPanel(
        meeting: meeting, transcriptDraft: $transcriptDraft, onCollapse: { mode = nil })
    case .ask:
      MeetingAskPanel(
        meeting: meeting, canAskAboutMeeting: canAskAboutMeeting,
        preferredAIProvider: preferredAIProvider, askInput: $askInput,
        onAsk: launchAsk, onCollapse: { mode = nil })
    case nil:
      EmptyView()
    }
  }

  // MARK: Collapsed bar

  private var collapsedBar: some View {
    Group {
      if isPrep {
        prepCollapsedBar
      } else {
        activeCollapsedBar
      }
    }
  }

  private var activeCollapsedBar: some View {
    HStack(spacing: 12) {
      transcriptToggle

      Button {
        askSheetQuestion = nil
        showAskSheet = true
      } label: {
        Text(canAskAboutMeeting ? "Ask anything" : "Ask (needs transcript)")
          .font(.ayrvo(13))
          .foregroundStyle(
            canAskAboutMeeting ? Theme.tertiary(scheme) : Theme.tertiary(scheme).opacity(0.55)
          )
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .disabled(!canAskAboutMeeting)
      .help(
        canAskAboutMeeting
          ? "Ask questions about this meeting"
          : "Record or add notes before asking questions"
      )
      .accessibilityAddTraits(.isButton)
      .accessibilityAddTraits(mode == .ask ? .isSelected : [])

      if showCollapsedResume {
        Button {
          Task { await app.continueRecording(meetingID: meeting.id) }
        } label: {
          HStack(spacing: 5) {
            Image(systemName: "mic.fill")
              .font(.system(size: 10, weight: .semibold))
            Text("Resume")
              .font(.ayrvo(11, .semibold))
          }
          .foregroundStyle(Theme.mint(scheme))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  private var prepCollapsedBar: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: "waveform")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Theme.tertiary(scheme))

        Text("Transcript Paused")
          .font(.ayrvo(13))
          .foregroundStyle(Theme.tertiary(scheme))
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      HStack(spacing: 12) {
        if let start = meeting.calendarEventStart, start > .now {
          Text("Starts \(CalendarTimeFormatter.time(start))")
            .font(.ayrvo(12, .medium))
            .foregroundStyle(Theme.secondary(scheme))
        }

        Button {
          Task { await app.continueRecording(meetingID: meeting.id) }
        } label: {
          Text("Start now")
            .font(.ayrvo(12, .semibold))
            .foregroundStyle(Theme.honey(scheme))
        }
        .buttonStyle(.plain)
        .disabled(app.isRecording)

        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .overlay(alignment: .top) { Divider().opacity(0.3) }
    }
  }

  private var canContinueRecording: Bool {
    meeting.canContinueRecording(isRecording: app.isRecording)
  }

  /// Resume lives in the empty-state hero when notes are still blank.
  private var showCollapsedResume: Bool {
    guard canContinueRecording else { return false }
    let summaryEmpty =
      app.store.summary(for: meeting.id).isEmpty
      && app.streamingSummaries[meeting.id] == nil
    return !summaryEmpty
  }

  private var transcriptToggle: some View {
    Button {
      mode = mode == .transcript ? nil : .transcript
    } label: {
      HStack(spacing: 6) {
        // Icon signals the listening state beyond color: waveform while
        // the transcript is open, a resting moon when idle.
        Image(systemName: mode == .transcript ? "waveform" : "moon.zzz")
          .font(.system(size: 11, weight: .semibold))
        Text("Transcript")
          .font(.ayrvo(12, .medium))
      }
      .foregroundStyle(mode == .transcript ? Theme.mint(scheme) : Theme.secondary(scheme))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(.isButton)
    .accessibilityAddTraits(mode == .transcript ? .isSelected : [])
  }

  private func launchAsk(_ question: String) {
    // Mirrors AILauncherView.submit: "Answer here" (CLI) streams in-app via the
    // Ask sheet; "Open in app" deep-links the external assistant. Apple
    // Intelligence is always CLI (on-device), so it routes through the sheet too.
    let effectiveMode: AskDeliveryMode = preferredAIProvider.supportsApp ? askDeliveryMode : .cli
    switch effectiveMode {
    case .cli:
      askSheetQuestion = question
      showAskSheet = true
    case .app:
      let prompt: String
      switch preferredAIProvider {
      case .apple, .opencode, .vibe:
        return
      case .claude:
        prompt = ClaudeDesktopPrompt.meeting(
          id: meeting.id, title: meeting.title, question: question)
      case .codex:
        prompt = CodexPrompt.meeting(
          id: meeting.id, title: meeting.title, question: question)
      }
      _ = AIAsk.open(prompt: prompt)
    }
  }
}
