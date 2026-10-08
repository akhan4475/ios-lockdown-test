import Foundation
import Combine
import UserNotifications

@MainActor
final class SessionAlerts: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = SessionAlerts()
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "connectionAlerts.enabled")
    @Published private(set) var permissionText = "Checking notification permission..."
    @Published private(set) var schedulingError = ""

    private let center = UNUserNotificationCenter.current()
    private var policy = SessionAlertPolicy()
    private(set) var sessionID: String?
    private let testID = "lockdown-notification-test"

    private override init() {
        super.init()
        center.delegate = self
    }

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            permissionText = "Notification permission allowed."
        case .denied:
            permissionText = "Notifications are blocked. Enable them for Lockdown Test in iPhone Settings."
            disable()
        case .notDetermined:
            permissionText = "Tap Enable alerts to allow notifications."
        @unknown default:
            permissionText = "Notification permission is unknown."
        }
    }

    func enable() async {
        do {
            let allowed = try await center.requestAuthorization(options: [.alert, .sound])
            enabled = allowed
            UserDefaults.standard.set(allowed, forKey: "connectionAlerts.enabled")
            schedulingError = ""
        } catch {
            schedulingError = "Could not enable alerts: \(error.localizedDescription)"
        }
        await refreshAuthorization()
    }

    func disable() {
        enabled = false
        UserDefaults.standard.set(false, forKey: "connectionAlerts.enabled")
        endSession()
        center.removePendingNotificationRequests(withIdentifiers: [testID])
    }

    func beginSession() {
        endSession()
        guard enabled else { return }
        sessionID = UUID().uuidString
        policy.begin(at: ProcessInfo.processInfo.systemUptime)
        scheduleWatchdog()
    }

    func commandFailed(for session: String?) {
        guard enabled, let sessionID, session == sessionID, policy.failure() else { return }
        center.removePendingNotificationRequests(withIdentifiers: [watchdogID(sessionID)])
        schedule(
            identifier: statusID(sessionID), session: sessionID,
            title: "Location updates failed",
            body: "The simulated location is unconfirmed; your real location may be reported. Open Lockdown Test to check LocalDevVPN and reconnect. Pause location sharing manually if needed."
        )
    }

    func commandSucceeded(for session: String?) {
        guard enabled, let sessionID, session == sessionID else { return }
        let event = policy.success(at: ProcessInfo.processInfo.systemUptime)
        if event.recovered {
            center.removeDeliveredNotifications(withIdentifiers: [watchdogID(sessionID)])
            schedule(
                identifier: statusID(sessionID), session: sessionID,
                title: "Location commands resumed",
                body: "The phone acknowledged a location command again. Verify the position in the intended app; this does not verify Find My sharing."
            )
        }
        if event.rearm { scheduleWatchdog() }
    }

    func endSession() {
        if let sessionID {
            let ids = [watchdogID(sessionID), statusID(sessionID)]
            center.removePendingNotificationRequests(withIdentifiers: ids)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
        sessionID = nil
        policy.end()
    }

    func testNotification() {
        guard enabled else { return }
        schedule(
            identifier: testID, session: nil,
            title: "Lockdown Test alert test",
            body: "This is a test notification. No connection failure was detected.",
            delay: 3
        )
    }

    private func watchdogID(_ session: String) -> String { "location-watchdog.\(session)" }
    private func statusID(_ session: String) -> String { "location-status.\(session)" }

    private func scheduleWatchdog() {
        guard let sessionID else { return }
        schedule(
            identifier: watchdogID(sessionID), session: sessionID,
            title: "Location updates unconfirmed",
            body: "No recent successful location update was confirmed. The app may have stopped or lost its connection. Open Lockdown Test and check the session; your real location may be reported.",
            delay: SessionAlertPolicy.watchdogDelay
        )
    }

    private func schedule(identifier: String, session: String?, title: String, body: String, delay: Double? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = delay.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                // A delayed scheduling completion must not leave an alert from
                // a cleared session or a disabled feature pending.
                if !self.enabled || (session != nil && self.sessionID != session) {
                    self.center.removePendingNotificationRequests(withIdentifiers: [identifier])
                    self.center.removeDeliveredNotifications(withIdentifiers: [identifier])
                    return
                }
                if let error {
                    self.schedulingError = "Could not schedule an alert: \(error.localizedDescription)"
                }
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
