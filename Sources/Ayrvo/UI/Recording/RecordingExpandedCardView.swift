import AppKit
import Combine
import SwiftUI

struct RecordingExpandedCardView: View {
  @ObservedObject var session: RecordingSession
  var pillPanel: NSWindow?
  var onMoved: () -> Void
  var onMinimize: () -> Void
  var onAsk: () -> Void
  var onStop: () -> Void
  var localeStore: TranscriptionLocaleStore?
  @Environment(\.colorScheme) private var scheme
  @Environment(\.ayrvoActionColor) private var actionColor

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        RecordDot()
        Text("Recording")
          .font(.ayrvo(14, .semibold))
        Spacer(minLength: 0)
        localeMenu
        Text(timeString(session.elapsed))
          .font(.system(size: 12, weight: .semibold, design: .monospaced))
          .foregroundStyle(.secondary)
        Button(action: onMinimize) {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help("Minimize")
        .accessibilityLabel("Minimize")
      }
      .background(CardDragArea(pillPanel: pillPanel, onMoved: onMoved))
      if let notice = session.speakerTrackingNotice {
        Text(notice).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      transcript
      GlassEffectContainer(spacing: 8) {
        HStack(spacing: 8) {
          Button(action: onAsk) {
            Label("Ask AI live", systemImage: "sparkles")
              .font(.ayrvo(12, .semibold))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 2)
          }
          .buttonStyle(.glassProminent)
          .tint(actionColor)
          Button("Stop", action: onStop)
            .font(.ayrvo(12))
            .buttonStyle(.glass)
        }
      }
    }
    .padding(12)
    .frame(width: 300, alignment: .leading)
    .floatingSurface(in: RoundedRectangle(cornerRadius: 16), opaque: true)
    .padding(.top, RecordingPillLayout.cardInset)
    .padding(.leading, RecordingPillLayout.cardInset)
    .padding(.bottom, RecordingPillLayout.cardInset)
    .padding(.trailing, RecordingPillLayout.gap)
  }

  private var transcript: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          if session.liveSegments.isEmpty, session.volatileText.isEmpty {
            Text("Listening…")
              .font(.ayrvo(12))
              .foregroundStyle(.tertiary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          ForEach(LiveTranscriber.turns(from: session.liveSegments)) { turn in
            VStack(alignment: .leading, spacing: 2) {
              Text(liveSpeakerName(for: turn.speakerID))
                .font(.ayrvo(10, .bold))
                .foregroundStyle(
                  turn.speakerID == LiveTranscriber.youSpeakerID
                    ? Theme.blueberry : Theme.raspberry)
              Text(turn.text)
                .font(.ayrvo(12))
                .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          if !session.volatileText.isEmpty {
            Text(session.volatileText)
              .font(.ayrvo(12))
              .italic()
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          Color.clear.frame(height: 1).id("card-bottom")
        }
        .padding(10)
      }
      .frame(height: 190)
      .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: 8))
      // Jump to the bottom once when the card appears so the latest
      // turn is in view, but don't force-scroll afterwards — the user
      // can scroll up to read earlier turns without being yanked back.
      .onAppear { proxy.scrollTo("card-bottom", anchor: .bottom) }
    }
  }

  private func timeString(_ t: TimeInterval) -> String {
    let s = Int(t)
    return String(format: "%d:%02d", s / 60, s % 60)
  }

  @ViewBuilder
  private var localeMenu: some View {
    if let store = localeStore {
      LiveLocaleMenu(session: session, store: store)
    }
  }

  private func liveSpeakerName(for speakerID: String) -> String {
    if speakerID == LiveTranscriber.othersSpeakerID,
      let active = session.activeRemoteSpeaker
    {
      return active
    }
    return LiveTranscriber.name(for: speakerID)
  }

}
