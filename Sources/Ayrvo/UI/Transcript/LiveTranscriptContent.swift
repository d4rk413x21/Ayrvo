import AppKit
import SwiftUI

struct GranolaLiveTranscriptContent: View {
  @ObservedObject var session: RecordingSession
  var priorSegments: [TranscriptSegment]
  var speakers: [Speaker]
  var searchQuery: String = ""

  @Environment(\.colorScheme) private var scheme

  private var priorTurns: [TranscriptTurn] {
    TranscriptTurnBuilder.turns(from: priorSegments)
  }

  private var liveTurns: [TranscriptTurn] {
    TranscriptTurnBuilder.turns(from: session.liveSegments)
  }

  private var filteredPriorTurns: [TranscriptTurn] {
    TranscriptSearch.filter(priorTurns, query: searchQuery)
  }

  private var filteredLiveTurns: [TranscriptTurn] {
    TranscriptSearch.filter(liveTurns, query: searchQuery)
  }

  private var isSearching: Bool {
    !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private var volatileMatchesSearch: Bool {
    guard isSearching else { return true }
    let query = searchQuery.trimmingCharacters(in: .whitespaces)
    return session.volatileText.localizedCaseInsensitiveContains(query)
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 6) {
          if isSearching, filteredPriorTurns.isEmpty, filteredLiveTurns.isEmpty,
            !volatileMatchesSearch
          {
            Text("No matches for “\(searchQuery.trimmingCharacters(in: .whitespaces))”.")
              .font(.ayrvo(12))
              .foregroundStyle(Theme.secondary(scheme))
              .frame(maxWidth: .infinity, minHeight: 120)
              .padding(.vertical, 20)
          }

          ForEach(filteredPriorTurns) { turn in
            TranscriptBubble(
              turn: turn,
              isSelf: isSelf(turn.speakerID),
              speakerName: name(for: turn.speakerID),
              searchQuery: searchQuery)
          }

          ForEach(filteredLiveTurns) { turn in
            TranscriptBubble(
              turn: turn,
              isSelf: isSelf(turn.speakerID),
              speakerName: name(for: turn.speakerID),
              searchQuery: searchQuery)
          }

          if !session.volatileText.isEmpty, volatileMatchesSearch {
            HStack {
              if isSelf(LiveTranscriber.youSpeakerID) { Spacer(minLength: 48) }
              TranscriptSearch.highlightedText(
                session.volatileText,
                query: searchQuery,
                scheme: scheme
              )
              .font(.ayrvo(12))
              .foregroundStyle(Theme.secondary(scheme))
              .italic()
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(
                Theme.bubble(scheme, isSelf: true).opacity(0.65),
                in: RoundedRectangle(cornerRadius: 14))
              if !isSelf(LiveTranscriber.youSpeakerID) { Spacer(minLength: 48) }
            }
          }

          Color.clear.frame(height: 1).id("granola-live-bottom")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
      }
      // Jump to the bottom once on appear so the latest turn is visible,
      // but don't force-scroll afterwards — the user can scroll up to
      // read earlier turns without being yanked back down on every update.
      .onAppear { proxy.scrollTo("granola-live-bottom", anchor: .bottom) }
      .onChange(of: searchQuery) {
        guard let first = filteredPriorTurns.first ?? filteredLiveTurns.first else { return }
        proxy.scrollTo(first.id, anchor: .top)
      }
    }
  }

  private func isSelf(_ speakerID: String) -> Bool {
    speakerID == LiveTranscriber.youSpeakerID
      || speakers.first(where: { $0.id == speakerID })?.isMe == true
  }

  private func name(for speakerID: String) -> String {
    if speakerID == LiveTranscriber.othersSpeakerID,
      let active = session.activeRemoteSpeaker
    {
      return active
    }
    return speakers.first(where: { $0.id == speakerID })?.name
      ?? LiveTranscriber.name(for: speakerID)
  }
}
