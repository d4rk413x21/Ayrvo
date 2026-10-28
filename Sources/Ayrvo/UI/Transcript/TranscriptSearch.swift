import AppKit
import SwiftUI

enum TranscriptSearch {
  static func filter(_ turns: [TranscriptTurn], query: String) -> [TranscriptTurn] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return turns }
    return turns.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
  }

  static func highlightedText(_ text: String, query: String, scheme: ColorScheme) -> Text {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return Text(text) }

    var attributed = AttributedString(text)
    var searchStart = attributed.startIndex
    while searchStart < attributed.endIndex,
      let range = attributed[searchStart..<attributed.endIndex].range(
        of: trimmed,
        options: .caseInsensitive
      )
    {
      attributed[range].foregroundColor = Theme.mint(scheme)
      attributed[range].font = .body.weight(.semibold)
      searchStart = range.upperBound
    }
    return Text(attributed)
  }
}
