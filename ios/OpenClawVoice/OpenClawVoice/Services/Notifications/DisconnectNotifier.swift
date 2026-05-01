import Foundation
import UserNotifications

// Fires a local user notification when the relay connection drops while the
// app is backgrounded. While foregrounded we rely on the in-app banner so we
// throttle to avoid double-notifying the user.
final class DisconnectNotifier {
    static let shared = DisconnectNotifier()

    private var lastNotifiedAt: Date?
    private let minimumInterval: TimeInterval = 60

    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyDisconnected(reason: String) {
        if let last = lastNotifiedAt, Date().timeIntervalSince(last) < minimumInterval {
            return
        }
        lastNotifiedAt = Date()

        let content = UNMutableNotificationContent()
        content.title = "OpenClaw Voice desconectado"
        content.body = reason
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "openclaw.disconnect.\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func notifyReconnected() {
        lastNotifiedAt = nil
    }
}
