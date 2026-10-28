import AppKit
import Combine
import SwiftUI

struct RecordingPillPanelView: View {
  @ObservedObject var session: RecordingSession
  @Binding var minimized: Bool
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    pillHandle
      .padding(.top, RecordingPillLayout.inset)
      .padding(.trailing, RecordingPillLayout.inset)
      .padding(.bottom, RecordingPillLayout.inset)
      .padding(.leading, RecordingPillLayout.gap)
  }

  private var pillHandle: some View {
    VStack(spacing: 14) {
      AyrvoMark(size: 19)
        .accessibilityHidden(true)
      Group {
        if minimized {
          MeterBars(levels: session.micBarLevels, barCount: 3)
        } else {
          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.tertiary)
        }
      }
      .frame(height: 16)
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 8)
    .frame(width: RecordingPillLayout.width)
    .floatingSurface(in: Capsule())
    .overlay { PillHandleArea(onClick: { minimized.toggle() }) }
    .help(minimized ? "Expand live transcript" : "Minimize")
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Live recording")
    .accessibilityValue(minimized ? "Collapsed" : "Expanded")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction(named: Text("Expand or minimize transcript")) { minimized.toggle() }
    .focusable()
    .onKeyPress(.return) { minimized.toggle(); return .handled }
    .onKeyPress(.space) { minimized.toggle(); return .handled }
  }
}
