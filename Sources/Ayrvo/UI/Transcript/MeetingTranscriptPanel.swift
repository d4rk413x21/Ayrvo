import AppKit
import SwiftUI

struct MeetingTranscriptPanel: View {
  @EnvironmentObject private var app: AppState
  @Environment(\.colorScheme) private var scheme
  @Environment(\.ayrvoActionColor) private var actionColor
  let meeting: Meeting
  @Binding var transcriptDraft: String?
  let onCollapse: () -> Void
  @State private var transcriptSearch = ""
  @State private var isTranscriptSearchPresented = false
  @FocusState private var transcriptSearchFocused: Bool

  private var segments: [TranscriptSegment] { app.store.transcript(for: meeting.id) }
  private var isLive: Bool { app.session?.meetingID == meeting.id }
  private var isPrep: Bool { meeting.state == .prep && !isLive }

  var body: some View {
    VStack(spacing: 0) {
      transcriptHeader

      if isLive, let session = app.session {
        GranolaLiveTranscriptContent(
          session: session,
          priorSegments: segments,
          speakers: meeting.speakers,
          searchQuery: transcriptSearch
        )
        .frame(height: 260)
      } else if segments.isEmpty {
        transcriptEmptyState
          .frame(maxWidth: .infinity, minHeight: 120)
          .padding(20)
      } else {
        GranolaTranscriptContent(
          meeting: meeting,
          segments: segments,
          draft: $transcriptDraft,
          searchQuery: transcriptSearch
        )
        .frame(height: 260)
      }

      if meeting.platformSpeakerAttribution {
        Text("Speaker identification is in beta and may not always be accurate.")
          .font(.ayrvo(10))
          .foregroundStyle(Theme.tertiary(scheme))
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 16)
          .padding(.bottom, 4)
      }

      transcriptFooter
    }
  }

  @ViewBuilder
  private var transcriptEmptyState: some View {
    if isPrep {
      Text("Transcript Paused")
        .font(.ayrvo(12))
        .foregroundStyle(Theme.secondary(scheme))
    } else if meeting.notice != nil {
      VStack(spacing: 8) {
        Image(systemName: "waveform.slash")
          .font(.system(size: 22, weight: .light))
          .foregroundStyle(Theme.tertiary(scheme))
        Text("No transcript")
          .font(.ayrvo(12, .semibold))
          .foregroundStyle(Theme.secondary(scheme))
        if meeting.duration > 0 {
          Text("Recorded \(TemplateRenderer.duration(meeting.duration)) — no speech detected.")
            .font(.ayrvo(11))
            .foregroundStyle(Theme.tertiary(scheme))
            .multilineTextAlignment(.center)
        } else {
          Text("Nothing was captured during this recording.")
            .font(.ayrvo(11))
            .foregroundStyle(Theme.tertiary(scheme))
            .multilineTextAlignment(.center)
        }
      }
    } else {
      Text("No transcript yet.")
        .font(.ayrvo(12))
        .foregroundStyle(Theme.secondary(scheme))
    }
  }

  private var transcriptHeader: some View {
    let searching = isTranscriptSearchPresented || !transcriptSearch.isEmpty

    return HStack(spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 12, weight: searching ? .semibold : .regular))
          .foregroundStyle(searching ? Theme.mint(scheme) : Theme.secondary(scheme))

        if searching {
          TextField("Search transcript…", text: $transcriptSearch)
            .textFieldStyle(.plain)
            .font(.ayrvo(12))
            .focused($transcriptSearchFocused)
            .onAppear { focusTranscriptSearch() }
            .onChange(of: transcriptSearchFocused) { _, focused in
              if !focused, transcriptSearch.isEmpty {
                isTranscriptSearchPresented = false
              }
            }

          if !transcriptSearch.isEmpty {
            Button {
              transcriptSearch = ""
              focusTranscriptSearch()
            } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiary(scheme))
            }
            .buttonStyle(.plain)
            .help("Clear search")
            .accessibilityLabel("Clear search")
          }
        } else {
          Button("Transcript", action: presentTranscriptSearch)
            .buttonStyle(.plain)
            .accessibilityLabel("Search transcript")
            .font(.ayrvo(12, .semibold))
            .foregroundStyle(Theme.secondary(scheme))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .help(searching ? "Search transcript" : "Search transcript (click to open)")

      if isLive, let session = app.session {
        LiveLocaleMenu(session: session, store: app.localeOverrides)
      }
      if isLive || !segments.isEmpty {
        Button {
          copyTranscript()
        } label: {
          Image(systemName: "doc.on.doc")
            .font(.system(size: 11))
            .foregroundStyle(Theme.secondary(scheme))
        }
        .buttonStyle(.plain)
        .help("Copy transcript")
        .accessibilityLabel("Copy transcript")
      }
      MeetingPanelCollapseButton(onCollapse: onCollapse)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .overlay(alignment: .bottom) { Divider().opacity(0.3) }
  }

  /// Copies the full transcript to the pasteboard — both prior (finalized)
  /// and live segments, formatted as "Speaker: text" lines.
  private func copyTranscript() {
    let session = app.session
    let text = TranscriptFormatter.clipboardText(
      meeting: meeting, saved: segments, liveMeetingID: session?.meetingID,
      live: session?.liveSegments ?? [],
      localName: LiveTranscriber.localSpeakerName, remoteName: LiveTranscriber.remoteSpeakerName)
    guard !text.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  private func presentTranscriptSearch() {
    isTranscriptSearchPresented = true
    focusTranscriptSearch()
  }

  private func focusTranscriptSearch() {
    DispatchQueue.main.async {
      transcriptSearchFocused = true
    }
  }

  @ViewBuilder
  private var transcriptFooter: some View {
    HStack(spacing: 12) {
      if isPrep {
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
      } else if meeting.canContinueRecording(isRecording: app.isRecording) {
        Button {
          Task { await app.continueRecording(meetingID: meeting.id) }
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "mic.fill")
              .font(.system(size: 11, weight: .semibold))
            Text("Resume recording")
              .font(.ayrvo(12, .semibold))
          }
          .foregroundStyle(Theme.mint(scheme))
        }
        .buttonStyle(.plain)
      } else if isLive {
        Button {
          Task { await app.stopRecording() }
        } label: {
          HStack(spacing: 6) {
            RecordDot()
            Text("Stop")
              .font(.ayrvo(12, .semibold))
          }
          .foregroundStyle(actionColor)
        }
        .buttonStyle(.plain)
      }

      Spacer()

      if isLive {
        Label("Live", systemImage: "circle.fill")
          .font(.ayrvo(10, .medium))
          .foregroundStyle(Theme.mint(scheme))
          .labelStyle(.titleAndIcon)
          .symbolRenderingMode(.palette)
          .foregroundStyle(Theme.mint(scheme), Theme.mint(scheme).opacity(0.3))
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .overlay(alignment: .top) { Divider().opacity(0.3) }
  }

}
