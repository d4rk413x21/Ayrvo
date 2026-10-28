import AppKit
import SwiftUI

struct SideNotesResizeHandle: View {
  @Environment(\.colorScheme) private var scheme
  @Binding var width: Double

  @State private var dragStartWidth: Double?
  @State private var isHovering = false

  private let minWidth = 200.0
  private let maxWidth = 520.0

  var body: some View {
    Rectangle()
      .fill(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06))
      .frame(width: 1)
      .frame(maxHeight: .infinity)
      .overlay {
        Rectangle()
          .fill(isHovering ? Theme.mint(scheme).opacity(0.35) : Color.clear)
          .frame(width: 6)
          .contentShape(Rectangle())
          .onHover { hovering in
            isHovering = hovering
            if hovering {
              NSCursor.resizeLeftRight.push()
            } else {
              NSCursor.pop()
            }
          }
          .gesture(
            DragGesture(minimumDistance: 1)
              .onChanged { value in
                if dragStartWidth == nil { dragStartWidth = width }
                let proposed = (dragStartWidth ?? width) + value.translation.width
                width = min(max(proposed, minWidth), maxWidth)
              }
              .onEnded { _ in dragStartWidth = nil }
          )
      }
  }
}

struct SideNotesPanel: View {
  @Environment(\.colorScheme) private var scheme
  @Binding var text: String
  let isRecording: Bool
  var onTextChange: () -> Void

  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider().opacity(0.25)

      ZStack(alignment: .topLeading) {
        TextEditor(text: $text)
          .font(.ayrvo(14))
          .foregroundStyle(Theme.heading(scheme))
          .scrollContentBackground(.hidden)
          .focused($focused)
          .onChange(of: text) { onTextChange() }

        if text.isEmpty {
          Text("Write notes")
            .font(.ayrvo(14))
            .foregroundStyle(Theme.tertiary(scheme))
            .padding(.leading, 5)
            .allowsHitTesting(false)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxHeight: .infinity)
    }
    .background(Theme.panel(scheme))
    .onAppear {
      if isRecording { focused = true }
    }
    .onChange(of: isRecording) { _, recording in
      if recording { focused = true }
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      if isRecording {
        RecordDot()
          .accessibilityLabel("Ayrvo is listening")
      }
      Text("My notes")
        .font(.ayrvo(13, .semibold))
        .foregroundStyle(Theme.heading(scheme))
      Spacer()
      if isRecording {
        Text("Live")
          .font(.ayrvo(10, .semibold))
          .foregroundStyle(Theme.mint(scheme))
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(Theme.mint(scheme).opacity(0.12), in: Capsule())
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}
