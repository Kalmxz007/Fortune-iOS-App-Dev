//
//  NotificationManager.swift
//  Fortune
//
//  Wraps local (on-device) notifications via the UserNotifications framework.
//  These are used for the in-app alerts described in the Privacy Policy:
//  price movements, stop-loss/take-profit events, and XP milestones.
//
//  No remote push server is involved — every notification is scheduled locally
//  on the device in response to real activity in the app.
//

import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        // Deliver banners even while the app is in the foreground.
        center.delegate = self
    }

    /// Prompts the user for permission. Returns whether it was granted.
    /// Safe to call repeatedly — iOS only shows the system prompt once.
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Whether notifications are currently permitted at the OS level.
    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// Fires a local notification immediately, but only if the OS has granted permission.
    func send(title: String, body: String) {
        Task {
            guard await isAuthorized() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body  = body
            content.sound = .default
            // A nil trigger delivers the notification right away.
            let request = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: content,
                                                trigger: nil)
            try? await center.add(request)
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show the banner + play sound even when Fortune is open in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
