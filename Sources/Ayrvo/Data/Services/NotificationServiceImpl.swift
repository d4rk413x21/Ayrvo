import AppKit
import Foundation
import UserNotifications
import os

final class NotificationServiceImpl: NotificationService, @unchecked Sendable {
  private var onReadyTapped: (@Sendable (UUID) -> Void)?
  private var detectionChime: NSSound?
  private let log = Logger(subsystem: AppIdentity.bundleIdentifier, category: "notifications")

  func configure(onReadyTapped: @escaping @Sendable (UUID) -> Void) {
    self.onReadyTapped = onReadyTapped
    guard Bundle.main.bundleIdentifier != nil else { return }
    let center = UNUserNotificationCenter.current()
    center.delegate = NotificationCenterDelegate.shared
    NotificationCenterDelegate.shared.onReadyTapped = onReadyTapped
    center.requestAuthorization(options: [.alert, .sound]) { granted, error in
      self.log.info(
        "notification auth granted=\(granted) error=\(error?.localizedDescription ?? "none", privacy: .public)"
      )
      AyrvoConsoleLog.notification(
        "auth granted=\(granted) error=\(error?.localizedDescription ?? "none")")
    }
  }

  func requestAuthorization() async {
    let center = UNUserNotificationCenter.current()
    _ = try? await center.requestAuthorization(options: [.alert, .sound])
  }

  func refreshAuthorizationStatus() async -> UNAuthorizationStatus {
    await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
  }

  func notifyMeetingReady(_ meeting: Meeting) {
    guard Bundle.main.bundleIdentifier != nil else { return }
    AyrvoConsoleLog.notification(
      "meeting ready \"\(meeting.title)\" (\(meeting.id.uuidString.prefix(8)))")
    let content = UNMutableNotificationContent()
    content.title = meeting.title
    content.body = "Your meeting notes are ready."
    let request = UNNotificationRequest(
      identifier: "ready-\(meeting.id)", content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }

  func playDetectionChime() {
    guard Bundle.main.bundleIdentifier != nil else { return }
    if detectionChime?.isPlaying == true { return }
    AyrvoConsoleLog.notification("detection chime")
    let sound = NSSound(named: NSSound.Name("Ping"))
    detectionChime = sound
    sound?.play()
  }
}

/// Bridges UNUserNotificationCenterDelegate to the Sendable notification service.
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate,
  @unchecked Sendable
{
  static let shared = NotificationCenterDelegate()
  var onReadyTapped: (@Sendable (UUID) -> Void)?

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let identifier = response.notification.request.identifier
    guard identifier.hasPrefix("ready-"),
      let id = UUID(uuidString: String(identifier.dropFirst("ready-".count)))
    else { return }
    await MainActor.run {
      onReadyTapped?(id)
      NSApp.activate()
    }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }
}
