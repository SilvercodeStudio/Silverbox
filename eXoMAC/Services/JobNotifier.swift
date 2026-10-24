import AppKit
import UserNotifications

/// Tells the user that a long job finished while the app was in the
/// background: a bounce of the Dock icon and a notification. Nothing
/// happens while the app is in front, where the bar already says so.
enum JobNotifier {
    static func notify(title: String, body: String) {
        guard !NSApplication.shared.isActive else { return }
        NSApplication.shared.requestUserAttention(.informationalRequest)
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
