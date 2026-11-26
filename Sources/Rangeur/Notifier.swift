import Foundation
import AppKit
import UserNotifications

/// Envoie les notifications de Rangeur et relaie les clics sur leurs boutons.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    enum Category {
        static let newFiles = "NEW_FILES"
        static let autoSorted = "AUTO_SORTED"
    }
    enum Action {
        static let sortNow = "SORT_NOW"
        static let undo = "UNDO"
        static let show = "SHOW"
    }

    /// Clic sur une notification (ou sur « Trier maintenant » / « Voir »).
    var onOpen: ((_ toActivity: Bool) -> Void)?
    /// Clic sur « Annuler » d'un rangement automatique.
    var onUndoBatch: ((_ batchID: String) -> Void)?

    /// Les notifications exigent une vraie app (.app) : depuis Xcode (paquet Swift) elles sont désactivées.
    var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    private var center: UNUserNotificationCenter? {
        isAvailable ? UNUserNotificationCenter.current() : nil
    }

    func setup() {
        guard let center else { return }
        center.delegate = self
        let newFiles = UNNotificationCategory(
            identifier: Category.newFiles,
            actions: [UNNotificationAction(identifier: Action.sortNow, title: "Trier maintenant", options: [.foreground])],
            intentIdentifiers: [])
        let autoSorted = UNNotificationCategory(
            identifier: Category.autoSorted,
            actions: [
                UNNotificationAction(identifier: Action.undo, title: "Annuler", options: []),
                UNNotificationAction(identifier: Action.show, title: "Voir", options: [.foreground]),
            ],
            intentIdentifiers: [])
        center.setNotificationCategories([newFiles, autoSorted])
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void = { _ in }) {
        guard let center else { completion(false); return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// "autorisées", "refusées", "pas encore demandées" ou "indisponibles".
    func status(_ completion: @escaping (UNAuthorizationStatus?) -> Void) {
        guard let center else { completion(nil); return }
        center.getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    func post(id: String, title: String, subtitle: String? = nil, body: String,
              category: String, userInfo: [String: String] = [:], sound: Bool = true) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle { content.subtitle = subtitle }
        content.body = body
        content.categoryIdentifier = category
        content.threadIdentifier = category
        content.userInfo = userInfo
        if sound { content.sound = .default }
        // Même identifiant = la notification remplace la précédente au lieu de s'empiler.
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func remove(id: String) {
        center?.removeDeliveredNotifications(withIdentifiers: [id])
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        let batchID = response.notification.request.content.userInfo["batch"] as? String
        DispatchQueue.main.async {
            switch action {
            case Action.undo:
                if let batchID { self.onUndoBatch?(batchID) }
            case Action.show:
                self.onOpen?(true)
            default: // clic sur la notification ou « Trier maintenant »
                self.onOpen?(category == Category.autoSorted)
            }
            completionHandler()
        }
    }
}
