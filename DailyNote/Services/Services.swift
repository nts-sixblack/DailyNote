import CloudKit
import CoreData
import Foundation
import Observation
import UserNotifications

// MARK: - Local reminders

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    /// Called on the main thread when the user taps a reminder.
    var onOpenNote: ((UUID) -> Void)?
    /// Called on the main thread for a routine reminder: (routine, day, tapped "Xong").
    var onRoutine: ((UUID, Date, Bool) -> Void)?

    func activate() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let done = UNNotificationAction(identifier: RoutineReminders.doneAction, title: String(localized: "Xong"), options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: RoutineReminders.category, actions: [done], intentIdentifiers: [])
        ])
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func schedule(id: UUID, noteID: UUID, title: String, body: String, at date: Date) {
        cancel(id: id)
        guard date > Date() else { return }
        Task {
            guard await requestAuthorization() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = ["noteID": noteID.uuidString]
            content.interruptionLevel = .timeSensitive
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: id.uuidString, content: content, trigger: trigger)
            )
        }
    }

    func cancel(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let raw = info["routineID"] as? String, let id = UUID(uuidString: raw) {
            let day = (info["day"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
            let markDone = response.actionIdentifier == RoutineReminders.doneAction
            await MainActor.run { onRoutine?(id, day, markDone) }
            return
        }
        guard let raw = info["noteID"] as? String,
              let id = UUID(uuidString: raw) else { return }
        await MainActor.run { onOpenNote?(id) }
    }
}

// MARK: - iCloud sync status

@MainActor
@Observable
final class SyncMonitor {
    enum AccountState: Equatable {
        case checking, available, noAccount, restricted, unavailable
    }

    static let shared = SyncMonitor()

    var account: AccountState = .checking
    var lastSync: Date?
    var isSyncing = false
    var lastError: String?

    private var observers: [NSObjectProtocol] = []

    func start(onRemoteChange: @escaping @MainActor () -> Void) {
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let ended = event.endDate
            let error = event.error?.localizedDescription
            MainActor.assumeIsolated {
                self.isSyncing = ended == nil
                if let ended { self.lastSync = ended }
                self.lastError = error
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onRemoteChange() }
        })
        Task { await refreshAccount() }
    }

    func refreshAccount() async {
        let status = try? await CKContainer(identifier: AppConstants.cloudContainer).accountStatus()
        account = switch status {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        default: .unavailable
        }
    }

    var statusText: String {
        if !DataStore.isCloudSyncEnabled { return String(localized: "Chỉ lưu trên thiết bị này") }
        switch account {
        case .checking: return String(localized: "Đang kiểm tra iCloud…")
        case .noAccount: return String(localized: "Chưa đăng nhập iCloud")
        case .restricted: return String(localized: "iCloud bị giới hạn")
        case .unavailable: return String(localized: "iCloud không khả dụng")
        case .available:
            if isSyncing { return String(localized: "Đang đồng bộ…") }
            if let lastSync {
                return String(localized: "Đã đồng bộ \(lastSync.formatted(.relative(presentation: .named)))")
            }
            return String(localized: "Đồng bộ iCloud đang bật")
        }
    }

    var symbol: String {
        guard DataStore.isCloudSyncEnabled else { return "icloud.slash" }
        switch account {
        case .available: return isSyncing ? "arrow.triangle.2.circlepath.icloud" : "checkmark.icloud"
        case .checking: return "icloud"
        default: return "exclamationmark.icloud"
        }
    }
}
