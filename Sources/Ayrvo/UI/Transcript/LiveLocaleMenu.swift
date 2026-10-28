import AppKit
import SwiftUI

struct LiveLocaleMenu: View {
  @ObservedObject var session: RecordingSession
  var store: TranscriptionLocaleStore
  @Environment(\.colorScheme) private var scheme

  private var current: String? {
    store.identifier(forMeetingID: session.meetingID.uuidString)
  }

  private var label: String {
    current.map { Self.shortLabel(for: $0) } ?? "Auto"
  }

  var body: some View {
    Menu {
      Button {
        session.setTranscriptionLocale(nil, store: store)
      } label: {
        if current == nil { Label("Auto", systemImage: "checkmark") } else { Text("Auto") }
      }
      Divider()
      ForEach(Self.entries(), id: \.0) { entry in
        Button {
          session.setTranscriptionLocale(entry.locale, store: store)
        } label: {
          if current == entry.id {
            Label(entry.label, systemImage: "checkmark")
          } else {
            Text(entry.label)
          }
        }
      }
    } label: {
      HStack(spacing: 3) {
        Image(systemName: "globe")
        Text(label)
      }
      .font(.ayrvo(11, .medium))
      .foregroundStyle(Theme.secondary(scheme))
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .help("Transcription language — pin to one locale or use Auto")
    .accessibilityLabel("Transcription language")
    .accessibilityValue(label)
  }

  private static func entries() -> [(id: String, label: String, locale: Locale)] {
    var seen = Set<String>()
    var out: [(id: String, label: String, locale: Locale)] = []
    for locale in [Locale.current] + TranscriptionLocales.presetLocales {
      let id = locale.identifier(.bcp47)
      guard seen.insert(id).inserted else { continue }
      let label = locale.localizedString(forIdentifier: id) ?? id
      out.append((id: id, label: label, locale: locale))
    }
    return out
  }

  private static func shortLabel(for identifier: String) -> String {
    Locale(identifier: identifier).localizedString(forIdentifier: identifier) ?? identifier
  }
}
