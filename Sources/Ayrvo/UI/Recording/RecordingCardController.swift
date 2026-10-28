import AppKit
import Combine
import SwiftUI

/// Shows/hides separate pill + expanded-card panels in lockstep with `AppState.session`.
@MainActor
final class RecordingCardController {
  private var pillPanel: FloatingPanel?
  private var cardPanel: FloatingPanel?
  private var shownID: UUID?
  private var placedForSession = false
  private var cardVisible = false
  private var cancellable: AnyCancellable?
  private let placement = FloatingPanelPlacement(
    originXKey: SettingsKey.recordingCardOriginX,
    originYKey: SettingsKey.recordingCardOriginY)

  init() {
    placement.onUserMoved = { [weak self] _ in self?.syncCardPanel(animated: false) }
    cancellable = AppState.shared.$session
      .combineLatest(
        AppState.shared.$recordingCardDismissed,
        AppState.shared.$recordingCardMinimized,
        AppState.shared.$showLiveRecordingCard
      )
      .removeDuplicates {
        $0.0?.meetingID == $1.0?.meetingID
          && $0.1 == $1.1
          && $0.2 == $1.2
          && $0.3 == $1.3
      }
      .sink { [weak self] session, dismissed, minimized, showCard in
        self?.update(
          session: session,
          dismissed: dismissed,
          minimized: minimized,
          showCard: showCard)
      }
  }

  private func update(
    session: RecordingSession?,
    dismissed: Bool,
    minimized: Bool,
    showCard: Bool
  ) {
    guard let session else {
      shownID = nil
      placedForSession = false
      cardVisible = false
      hidePanels()
      return
    }
    guard showCard, !dismissed else {
      hidePanels(keepSession: true)
      return
    }

    let pill = ensurePillPanel()
    let card = ensureCardPanel()

    if session.meetingID != shownID {
      shownID = session.meetingID
      placedForSession = false
      cardVisible = false
      rebuildContent(session: session)
    }

    if !placedForSession {
      pill.setContentSize(RecordingPillLayout.minimizedSize)
      if placement.userPlaced {
        placement.place(pill) { pill.frame }
      } else {
        defaultPillPosition(pill)
      }
      placedForSession = true
    }

    let targetVisible = !minimized
    let animate = cardVisible != targetVisible && placedForSession
    setCardVisible(targetVisible, animated: animate)
    pill.orderFrontRegardless()
    if !minimized {
      card.orderFrontRegardless()
      pill.orderFrontRegardless()
    }
  }

  private func setCardVisible(_ visible: Bool, animated: Bool) {
    guard let card = cardPanel, pillPanel != nil else { return }
    guard visible != cardVisible else {
      if visible { syncCardPanel(animated: false) }
      return
    }
    cardVisible = visible

    if visible {
      syncCardPanel(animated: false)
      card.alphaValue = animated ? 0 : 1
      card.orderFrontRegardless()
      guard animated else { return }
      let target = card.frame
      var start = target
      start.origin.x += 16
      card.setFrame(start, display: false)
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.2
        ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
        card.animator().alphaValue = 1
        card.animator().setFrame(target, display: true)
      }
    } else {
      guard animated, card.isVisible else {
        card.orderOut(nil)
        card.alphaValue = 1
        return
      }
      let start = card.frame
      var end = start
      end.origin.x += 16
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.15
        ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
        card.animator().alphaValue = 0
        card.animator().setFrame(end, display: true)
      } completionHandler: {
        card.orderOut(nil)
        card.alphaValue = 1
        card.setFrame(start, display: false)
      }
    }
  }

  private func syncCardPanel(animated: Bool) {
    guard let card = cardPanel, let pill = pillPanel else { return }
    let size = RecordingPillLayout.cardPanelSize
    let origin = placement.clampedOrigin(
      RecordingPillLayout.cardOrigin(leftOf: pill.frame, cardSize: size),
      size: size)
    let frame = NSRect(origin: origin, size: size)
    guard animated else {
      card.setFrame(frame, display: true)
      return
    }
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.2
      card.animator().setFrame(frame, display: true)
    }
  }

  private func hidePanels(keepSession: Bool = false) {
    cardPanel?.orderOut(nil)
    pillPanel?.orderOut(nil)
    if !keepSession {
      cardVisible = false
    }
  }

  private func rebuildContent(session: RecordingSession) {
    let app = AppState.shared
    let pillHost = NSHostingController(
      rootView: RecordingPillPanelView(
        session: session,
        minimized: Binding(
          get: { app.recordingCardMinimized },
          set: { app.recordingCardMinimized = $0 })
      )
      .ayrvoAppearance())
    pillPanel?.contentViewController = pillHost
    pillPanel?.setContentSize(RecordingPillLayout.minimizedSize)

    let cardHost = NSHostingController(
      rootView: RecordingExpandedCardView(
        session: session,
        pillPanel: pillPanel,
        onMoved: { [weak self] in self?.syncCardPanel(animated: false) },
        onMinimize: { app.recordingCardMinimized = true },
        onAsk: { _ = AIAsk.openLive() },
        onStop: { Task { await app.stopRecording() } },
        localeStore: app.localeOverrides
      )
      .ayrvoAppearance())
    cardPanel?.contentViewController = cardHost
    cardPanel?.setContentSize(RecordingPillLayout.cardPanelSize)
  }

  private func ensurePillPanel() -> FloatingPanel {
    if let pillPanel { return pillPanel }
    let panel = makePanel(size: RecordingPillLayout.minimizedSize)
    placement.bindMoveNotifications(for: panel)
    pillPanel = panel
    return panel
  }

  private func ensureCardPanel() -> FloatingPanel {
    if let cardPanel { return cardPanel }
    let panel = makePanel(size: RecordingPillLayout.cardPanelSize)
    cardPanel = panel
    return panel
  }

  private func makePanel(size: NSSize) -> FloatingPanel {
    let panel = FloatingPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.level = .statusBar
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    return panel
  }

  private func defaultPillPosition(_ pill: FloatingPanel) {
    guard let screen = NSScreen.main else { return }
    let anchor = RecordingPillLayout.defaultPillAnchor(on: screen)
    pill.setFrame(RecordingPillLayout.pillFrame(anchor: anchor), display: false)
  }
}
