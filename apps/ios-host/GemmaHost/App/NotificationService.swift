import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()

    private init() {
        requestAuthorization()
    }

    func scheduleTaskCompletedNotification(taskTitle: String, summary: String, taskId: String) {
        let content = UNMutableNotificationContent()
        content.title = "Task Completed"
        content.body = "\(taskTitle): \(String(summary.prefix(100)))"
        content.userInfo = ["task_id": taskId]
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "task-completed-\(taskId)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    func cancelPending() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}
