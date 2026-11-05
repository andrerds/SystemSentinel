import Foundation
import UserNotifications
import AppKit

// MARK: - Notification Service (Notificações proativas no macOS)
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    
    override private init() {
        super.init()
        setupCenter()
    }
    
    private func setupCenter() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        
        let actionKill = UNNotificationAction(identifier: "ACTION_KILL", title: "Encerrar", options: [.destructive])
        let actionRestart = UNNotificationAction(identifier: "ACTION_RESTART", title: "Reiniciar", options: [.foreground])
        let actionIgnore = UNNotificationAction(identifier: "ACTION_IGNORE", title: "Ignorar", options: [])
        
        let category = UNNotificationCategory(
            identifier: "SYSTEM_SENTINEL_ANOMALY",
            actions: [actionRestart, actionKill, actionIgnore],
            intentIdentifiers: [],
            options: []
        )
        
        center.setNotificationCategories([category])
    }
    
    func postAnomalyNotification(incident: SystemIncident) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ System Sentinel: \(incident.type.rawValue)"
        content.subtitle = incident.title
        content.body = incident.llmDiagnosis ?? incident.description
        content.sound = .default
        content.categoryIdentifier = "SYSTEM_SENTINEL_ANOMALY"
        content.userInfo = ["incidentId": incident.id.uuidString]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: incident.id.uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            let actionId = response.actionIdentifier
            let userInfo = response.notification.request.content.userInfo
            if let idStr = userInfo["incidentId"] as? String, let uuid = UUID(uuidString: idStr) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("SystemSentinelNotificationAction"),
                    object: nil,
                    userInfo: ["incidentId": uuid, "action": actionId]
                )
            }
            completionHandler()
        }
    }
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
