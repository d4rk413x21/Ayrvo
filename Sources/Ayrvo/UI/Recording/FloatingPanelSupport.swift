import AppKit
import Combine
import SwiftUI

/// A borderless, non-activating floating panel so the "Record this meeting?" card can appear on
/// its own (SwiftUI's MenuBarExtra popover can't be opened programmatically) without stealing
/// focus from whatever the user is doing. canBecomeKey stays true so the SwiftUI buttons inside
/// react to clicks; nonactivatingPanel keeps the app itself from coming forward.
final class FloatingPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

/// Persists and applies floating-panel placement. Auto-position only until the user drags.
@MainActor
final class FloatingPanelPlacement {
  private let originXKey: String
  private let originYKey: String
  private var moveObserver: NSObjectProtocol?
  private(set) var userPlaced: Bool
  private var suppressMoveSaves = false
  var onUserMoved: ((NSWindow) -> Void)?

  init(originXKey: String, originYKey: String) {
    self.originXKey = originXKey
    self.originYKey = originYKey
    userPlaced = AppSettings.defaults.object(forKey: originXKey) != nil
  }

  func place(_ panel: NSWindow, defaultFrame: () -> NSRect) {
    let size = panel.frame.size
    if userPlaced, let origin = savedOrigin {
      panel.setFrameOrigin(clamped(origin, size: size))
    } else {
      panel.setFrame(defaultFrame(), display: false)
    }
  }

  func bindMoveNotifications(for panel: NSWindow) {
    guard moveObserver == nil else { return }
    moveObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didMoveNotification, object: panel, queue: .main
    ) { [weak self, weak panel] _ in
      Task { @MainActor in
        guard let self, let panel, !self.suppressMoveSaves else { return }
        self.save(panel.frame.origin)
        self.userPlaced = true
        self.onUserMoved?(panel)
      }
    }
  }

  func clampedOrigin(_ origin: NSPoint, size: NSSize) -> NSPoint {
    clamped(origin, size: size)
  }

  private func save(_ origin: NSPoint) {
    AppSettings.defaults.set(origin.x, forKey: originXKey)
    AppSettings.defaults.set(origin.y, forKey: originYKey)
  }

  private var savedOrigin: NSPoint? {
    guard AppSettings.defaults.object(forKey: originXKey) != nil else { return nil }
    return NSPoint(
      x: AppSettings.defaults.double(forKey: originXKey),
      y: AppSettings.defaults.double(forKey: originYKey))
  }

  private func clamped(_ origin: NSPoint, size: NSSize) -> NSPoint {
    guard let screen = panelScreen(for: origin) ?? NSScreen.main else { return origin }
    let visible = screen.visibleFrame
    let x = min(max(origin.x, visible.minX), visible.maxX - size.width)
    let y = min(max(origin.y, visible.minY), visible.maxY - size.height)
    return NSPoint(x: x, y: y)
  }

  private func panelScreen(for origin: NSPoint) -> NSScreen? {
    NSScreen.screens.first { NSMouseInRect(origin, $0.frame, false) }
  }
}

/// Layout metrics for the recording pill — shared with panel placement so the handle
/// doesn't shift when the expanded card is shown or hidden.
enum RecordingPillLayout {
  static let inset: CGFloat = 6
  static let cardInset: CGFloat = 8
  /// Visual space between the expanded card and the pill.
  static let gap: CGFloat = 2
  static let width: CGFloat = 44
  /// Stripes (19) + spacing (14) + indicator (16) + vertical padding (24).
  static let height: CGFloat = 73
  /// Matches `RecordingExpandedCardView` (300 + 12 padding each side).
  static let cardWidth: CGFloat = 324
  /// Header + transcript (190) + buttons + spacing + card padding.
  static let cardHeight: CGFloat = 286

  static var minimizedSize: NSSize {
    NSSize(width: gap + width + inset, height: inset + height + inset)
  }

  static var cardPanelSize: NSSize {
    NSSize(
      width: cardInset + cardWidth + gap,
      height: cardInset + cardHeight + cardInset)
  }

  static func cardOrigin(leftOf pillFrame: NSRect, cardSize: NSSize = cardPanelSize) -> NSPoint {
    NSPoint(x: pillFrame.minX - cardSize.width, y: pillFrame.maxY - cardSize.height)
  }

  static func pillFrame(anchor: NSPoint) -> NSRect {
    let size = minimizedSize
    return NSRect(
      x: anchor.x + inset - size.width,
      y: anchor.y + inset - size.height,
      width: size.width,
      height: size.height)
  }

  static func pillAnchor(in panelFrame: NSRect) -> NSPoint {
    NSPoint(x: panelFrame.maxX - inset, y: panelFrame.maxY - inset)
  }

  static func defaultPillAnchor(on screen: NSScreen) -> NSPoint {
    let visible = screen.visibleFrame
    return NSPoint(
      x: visible.maxX - 16 - inset,
      y: visible.midY + height / 2)
  }
}
