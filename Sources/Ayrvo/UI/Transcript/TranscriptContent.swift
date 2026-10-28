import AppKit
import SwiftUI

struct GranolaTranscriptContent: View {
  @EnvironmentObject private var app: AppState
  @Environment(\.colorScheme) private var scheme
  @Environment(\.ayrvoActionColor) private var actionColor

  let meeting: Meeting
  let segments: [TranscriptSegment]
  @Binding var draft: String?
  var searchQuery: String = ""

  private var turns: [TranscriptTurn] {
    TranscriptTurnBuilder.turns(from: segments)
  }

  private var filteredTurns: [TranscriptTurn] {
    TranscriptSearch.filter(turns, query: searchQuery)
  }

  private var isSearching: Bool {
    !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
  }

  var body: some View {
    if draft != nil {
      TextEditor(text: Binding(get: { draft ?? "" }, set: { draft = $0 }))
        .font(.system(size: 12, design: .monospaced))
        .scrollContentBackground(.hidden)
        .padding(12)
    } else if isSearching, filteredTurns.isEmpty {
      Text("No matches for “\(searchQuery.trimmingCharacters(in: .whitespaces))”.")
        .font(.ayrvo(12))
        .foregroundStyle(Theme.secondary(scheme))
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(20)
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 6) {
            ForEach(Array(filteredTurns.enumerated()), id: \.element.id) { index, turn in
              if shouldShowTimestamp(before: turn, at: index, in: filteredTurns) {
                Text(MeetingArchive.timestamp(turn.start))
                  .font(.system(size: 10, design: .monospaced))
                  .foregroundStyle(Theme.tertiary(scheme))
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 4)
              }
              TranscriptBubble(
                turn: turn,
                isSelf: isSelf(turn.speakerID),
                speakerName: name(for: turn.speakerID),
                searchQuery: searchQuery
              )
              .id(turn.id)
            }
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
        }
        .onChange(of: searchQuery) {
          guard let first = filteredTurns.first else { return }
          proxy.scrollTo(first.id, anchor: .top)
        }
      }
    }
  }

  private func isSelf(_ speakerID: String) -> Bool {
    speakerID == LiveTranscriber.youSpeakerID
      || meeting.speakers.first(where: { $0.id == speakerID })?.isMe == true
  }

  private func name(for speakerID: String) -> String {
    meeting.speakers.first { $0.id == speakerID }?.name ?? speakerID
  }

  private func shouldShowTimestamp(
    before turn: TranscriptTurn, at index: Int, in turns: [TranscriptTurn]
  ) -> Bool {
    guard index > 0 else { return true }
    let prev = turns[index - 1]
    return turn.start - prev.end > 30
  }
}
