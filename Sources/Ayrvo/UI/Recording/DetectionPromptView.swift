import AppKit
import Combine
import SwiftUI

struct DetectionPromptView: View {
  let appName: String
  let onRecord: () -> Void
  let onDismiss: () -> Void
  let onAutoDismiss: () -> Void
  @Environment(\.colorScheme) private var scheme
  @Environment(\.ayrvoActionColor) private var actionColor
  @State private var progress: CGFloat = 0
  @State private var closeHovered = false
  @State private var recordHovered = false

  private let cardWidth: CGFloat = 360
  private static let autoDismissSeconds: TimeInterval = 15

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      closeButton
      headerCard
    }
    .frame(width: cardWidth + 32)
    .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.16), radius: 20, y: 8)
    .padding(20)  // transparent margin so the shadow isn't clipped by the panel bounds
    .task(id: appName) {
      progress = 0
      await Task.yield()
      withAnimation(.linear(duration: Self.autoDismissSeconds)) {
        progress = 1
      }
      try? await Task.sleep(for: .seconds(Self.autoDismissSeconds))
      guard !Task.isCancelled else { return }
      onAutoDismiss()
    }
  }

  private var closeButton: some View {
    Button(action: onDismiss) {
      Image(systemName: "xmark")
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(closeHovered ? Theme.heading(scheme) : Theme.tertiary(scheme))
        .frame(width: 26, height: 26)
        .background(
          closeHovered ? Theme.card(scheme) : Theme.panel(scheme),
          in: Circle()
        )
        .overlay(Circle().strokeBorder(.primary.opacity(closeHovered ? 0.14 : 0.08)))
    }
    .buttonStyle(.plain)
    .onHover { closeHovered = $0 }
    .help("Dismiss")
    .accessibilityLabel("Dismiss")
  }

  private var headerCard: some View {
    let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    return HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Call detected")
          .font(.ayrvo(17, .semibold))
          .foregroundStyle(Theme.heading(scheme))
        Text(appName)
          .font(.ayrvo(12))
          .foregroundStyle(Theme.secondary(scheme))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(WindowDragArea())
      takeNotesButton
    }
    .padding(.horizontal, 16)
    .padding(.top, 16)
    .padding(.bottom, 15)
    .background(Theme.panel(scheme), in: shape)
    .overlay(shape.strokeBorder(.primary.opacity(0.09)))
    .overlay(alignment: .top) { progressBar }
    .clipShape(shape)
  }

  private var progressBar: some View {
    GeometryReader { geo in
      let fillWidth = geo.size.width * progress
      HStack(spacing: 0) {
        Rectangle()
          .fill(Theme.blueberry(scheme))
          .frame(width: fillWidth)
        Rectangle()
          .fill(Theme.blueberry(scheme).opacity(0.14))
      }
    }
    .frame(height: 2)
    .allowsHitTesting(false)
  }

  private var takeNotesButton: some View {
    takeNotesButtonLabel
      .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay { FirstMouseClickArea(onClick: onRecord) }
      .onHover { recordHovered = $0 }
      .help("Start recording")
      .accessibilityLabel("Start recording")
  }

  private var takeNotesButtonLabel: some View {
    HStack(spacing: 9) {
      AyrvoMark(size: 24)
        .accessibilityHidden(true)
      Text("Take notes")
        .font(.ayrvo(13, .semibold))
        .foregroundStyle(Theme.heading(scheme))
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 7)
    .background(
      recordHovered ? Theme.surface(scheme) : Theme.card(scheme),
      in: RoundedRectangle(cornerRadius: 10, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(
          recordHovered ? actionColor.opacity(0.35) : .primary.opacity(0.07),
          lineWidth: recordHovered ? 1.5 : 1))
  }
}
