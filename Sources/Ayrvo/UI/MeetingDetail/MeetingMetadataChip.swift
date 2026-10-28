import SwiftUI

struct GranolaChip: View {
  @Environment(\.colorScheme) private var scheme
  let icon: String?
  let text: String
  var accent: Color?

  var body: some View {
    HStack(spacing: 5) {
      if let icon {
        Image(systemName: icon)
          .font(.system(size: 10, weight: .semibold))
          .accessibilityHidden(true)
      }
      Text(text)
        .font(.ayrvo(11, .medium))
        .lineLimit(1)
    }
    .foregroundStyle(accent ?? Theme.secondary(scheme))
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(Theme.chip(scheme), in: Capsule())
    .overlay {
      Capsule().strokeBorder(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}

