import AppKit
import SwiftUI

struct TranscriptBubble: View {
  @Environment(\.colorScheme) private var scheme

  let turn: TranscriptTurn
  let isSelf: Bool
  let speakerName: String
  var searchQuery: String = ""

  var body: some View {
    HStack(alignment: .bottom, spacing: 0) {
      if isSelf { Spacer(minLength: 56) }

      VStack(alignment: isSelf ? .trailing : .leading, spacing: 3) {
        if !isSelf {
          Text(speakerName)
            .font(.ayrvo(10, .semibold))
            .foregroundStyle(Theme.tertiary(scheme))
        }
        TranscriptSearch.highlightedText(turn.text, query: searchQuery, scheme: scheme)
          .font(.ayrvo(12))
          .foregroundStyle(Theme.ink(scheme))
          .textSelection(.enabled)
          .lineSpacing(2)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(
            Theme.bubble(scheme, isSelf: isSelf),
            in: RoundedRectangle(cornerRadius: 14))
      }
      .frame(maxWidth: 340, alignment: isSelf ? .trailing : .leading)

      if !isSelf { Spacer(minLength: 56) }
    }
  }
}

/// Per-meeting transcription language picker shown in the live transcript header.
/// "Auto" = code-switching across reserved locales; selecting a specific locale
/// pins both channels to it for the rest of the call. Persists via the store so
/// the choice survives a resume.
