import AppKit
import SwiftUI

struct MeetingPanelCollapseButton: View {
  @Environment(\.colorScheme) private var scheme
  let onCollapse: () -> Void

  var body: some View {
    Button {
      onCollapse()
    } label: {
      Image(systemName: "chevron.down")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.tertiary(scheme))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.trailing, -12)
    .help("Collapse panel")
    .accessibilityLabel("Collapse panel")
  }

}
