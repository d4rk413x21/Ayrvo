import AppKit
import Combine
import SwiftUI

/// Transparent click target that works on the first mouse-down in a non-activating panel.
struct FirstMouseClickArea: NSViewRepresentable {
  var onClick: () -> Void

  func makeNSView(context: Context) -> ClickView {
    let view = ClickView()
    view.onClick = onClick
    return view
  }

  func updateNSView(_ nsView: ClickView, context: Context) {
    nsView.onClick = onClick
  }

  final class ClickView: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
  }
}

/// Drag handle that moves the hosting NSPanel without stealing button clicks elsewhere.
struct WindowDragArea: NSViewRepresentable {
  func makeNSView(context: Context) -> DragAreaView { DragAreaView() }
  func updateNSView(_ nsView: DragAreaView, context: Context) {}

  final class DragAreaView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
      window?.performDrag(with: event)
    }
  }
}

/// Pill handle: drag anywhere, click without moving toggles expand/collapse.
struct PillHandleArea: NSViewRepresentable {
  var onClick: () -> Void

  func makeNSView(context: Context) -> PillHandleView {
    let view = PillHandleView()
    view.onClick = onClick
    return view
  }

  func updateNSView(_ nsView: PillHandleView, context: Context) {
    nsView.onClick = onClick
  }

  final class PillHandleView: NSView {
    var onClick: (() -> Void)?
    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var dragged = false
    private let clickThreshold: CGFloat = 4

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
      dragged = false
      dragStartMouse = NSEvent.mouseLocation
      dragStartOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
      guard let window else { return }
      let current = NSEvent.mouseLocation
      let delta = NSPoint(
        x: current.x - dragStartMouse.x,
        y: current.y - dragStartMouse.y)
      if hypot(delta.x, delta.y) >= clickThreshold { dragged = true }
      window.setFrameOrigin(
        NSPoint(
          x: dragStartOrigin.x + delta.x,
          y: dragStartOrigin.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
      if !dragged { onClick?() }
    }
  }
}

/// Drag handle that moves the pill panel; the expanded card follows.
struct CardDragArea: NSViewRepresentable {
  var pillPanel: NSWindow?
  var onMoved: () -> Void

  func makeNSView(context: Context) -> CardDragView {
    let view = CardDragView()
    view.pillPanel = pillPanel
    view.onMoved = onMoved
    return view
  }

  func updateNSView(_ nsView: CardDragView, context: Context) {
    nsView.pillPanel = pillPanel
    nsView.onMoved = onMoved
  }

  final class CardDragView: NSView {
    weak var pillPanel: NSWindow?
    var onMoved: (() -> Void)?
    private var dragStartMouse = NSPoint.zero
    private var dragStartOrigin = NSPoint.zero

    override func mouseDown(with event: NSEvent) {
      dragStartMouse = NSEvent.mouseLocation
      dragStartOrigin = pillPanel?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
      guard let pillPanel else { return }
      let current = NSEvent.mouseLocation
      pillPanel.setFrameOrigin(
        NSPoint(
          x: dragStartOrigin.x + current.x - dragStartMouse.x,
          y: dragStartOrigin.y + current.y - dragStartMouse.y))
      onMoved?()
    }
  }
}
