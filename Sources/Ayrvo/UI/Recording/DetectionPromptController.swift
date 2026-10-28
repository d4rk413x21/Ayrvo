import AppKit
import Combine
import SwiftUI

/// Shows/hides the floating detection prompt in lockstep with `AppState.detectedAppName`.
/// Owned by the AppDelegate for the app's lifetime.
@MainActor
final class DetectionPromptController {
  private var panel: FloatingPanel?
  private var shownName: String?
  private var isDismissing = false
  private var cancellable: AnyCancellable?

  init() {
    // detectedAppName is only ever non-nil while detection is on and auto-record is off, and
    // it clears on record/dismiss/mic-release — so binding the panel straight to it needs no
    // extra state. removeDuplicates avoids rebuilding the card on redundant re-publishes.
    cancellable = AppState.shared.$detectedAppName
      .removeDuplicates()
      .sink { [weak self] name in self?.update(appName: name) }
  }

  private func update(appName: String?) {
    guard let appName else {
      shownName = nil
      isDismissing = false
      panel?.orderOut(nil)
      return
    }
    guard !isDismissing else { return }
    let panel = ensurePanel()
    if appName != shownName {
      shownName = appName
      let host = NSHostingController(
        rootView: DetectionPromptView(
          appName: appName,
          onRecord: { Task { await AppState.shared.acceptDetection() } },
          onDismiss: { AppState.shared.dismissDetection() },
          onAutoDismiss: { [weak self] in self?.dismissAnimatedToRight() }
        )
        .ayrvoAppearance())
      panel.contentViewController = host
      panel.setContentSize(host.view.fittingSize)
    }
    position(panel)
    panel.orderFrontRegardless()  // show without activating the app
  }

  private func dismissAnimatedToRight() {
    guard !isDismissing, let panel else {
      AppState.shared.dismissDetection()
      return
    }
    isDismissing = true
    let start = panel.frame
    var end = start
    end.origin.x = start.maxX + 24
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.28
      ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
      panel.animator().alphaValue = 0
      panel.animator().setFrame(end, display: true)
    } completionHandler: { [weak self] in
      Task { @MainActor in
        panel.alphaValue = 1
        panel.setFrame(start, display: false)
        self?.shownName = nil
        AppState.shared.dismissDetection()
      }
    }
  }

  private func ensurePanel() -> FloatingPanel {
    if let panel { return panel }
    let panel = FloatingPanel(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 100),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.level = .floating
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    // Meeting apps are often full-screen; ride along over them and across every Space.
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false  // the card draws its own rounded shadow
    self.panel = panel
    return panel
  }

  /// Top-right, just under the menu bar. The +8 nudges account for the card's transparent
  /// shadow padding so the visible card hugs the corner rather than floating off it.
  private func position(_ panel: FloatingPanel) {
    guard let screen = NSScreen.main else { return }
    let visible = screen.visibleFrame
    let size = panel.frame.size
    panel.setFrameOrigin(
      NSPoint(
        x: visible.maxX - size.width + 8,
        y: visible.maxY - size.height + 8))
  }
}
