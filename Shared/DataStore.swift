import Foundation
import SwiftData
import WidgetKit

/// Single SwiftData store living in the App Group container so the app, widgets and
/// App Intents read the same notes. Only the main app syncs it with iCloud (CloudKit
/// private database); extensions open the same file without CloudKit mirroring.
enum DataStore {
    static let schema = Schema([Note.self, Folder.self, ChecklistItem.self, Routine.self, RoutineLog.self])

    static var storeURL: URL {
        AppConstants.groupContainerURL.appending(path: "DailyNote.store")
    }

    /// Whether the running container mirrors to iCloud.
    nonisolated(unsafe) private(set) static var isCloudSyncEnabled = false

    static let container: ModelContainer = makeContainer(cloud: !AppConstants.isExtension)

    private static func makeContainer(cloud: Bool) -> ModelContainer {
        if cloud {
            let config = ModelConfiguration(
                "DailyNote", schema: schema, url: storeURL,
                cloudKitDatabase: .private(AppConstants.cloudContainer)
            )
            if let container = try? ModelContainer(for: schema, configurations: config) {
                isCloudSyncEnabled = true
                return container
            }
        }
        let local = ModelConfiguration("DailyNote", schema: schema, url: storeURL, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: local) {
            return container
        }
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: memory)
    }

    static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Runs a write on the app's main context when inside the app (so open screens see it at once and
    /// it syncs to iCloud), or on a fresh context in an extension. Saves, flags extension writes for the
    /// app and reloads widgets.
    @MainActor
    static func write<T>(_ body: (ModelContext) throws -> T) throws -> T {
        let context = AppConstants.isExtension ? ModelContext(container) : container.mainContext
        let result = try body(context)
        try context.save()
        if AppConstants.isExtension { markExternalWrite() }
        reloadWidgets()
        return result
    }

    // MARK: Changes made by extensions

    static let externalWriteNotification = "com.sixpilot.DaillyNote.storeChanged"

    /// When an extension last wrote to the store. The app's main context never sees writes from
    /// other processes, so the app refetches when this moves forward.
    static var lastExternalWrite: Double {
        UserDefaults.shared.double(forKey: AppConstants.Key.lastExternalWrite)
    }

    static func markExternalWrite() {
        UserDefaults.shared.set(Date().timeIntervalSince1970, forKey: AppConstants.Key.lastExternalWrite)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(externalWriteNotification as CFString), nil, nil, true
        )
    }
}

// MARK: - Queries shared by widgets, intents and app

extension ModelContext {
    func note(id: UUID) -> Note? {
        var d = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? fetch(d).first
    }

    func checklistItem(id: UUID) -> ChecklistItem? {
        var d = FetchDescriptor<ChecklistItem>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? fetch(d).first
    }

    func activeNotes(limit: Int? = nil) -> [Note] {
        var d = FetchDescriptor<Note>(
            predicate: #Predicate { !$0.isTrashed },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let limit { d.fetchLimit = limit }
        return (try? fetch(d)) ?? []
    }

    /// Notes the user flagged for the Lock Screen, falling back to pinned, then most recent.
    func lockScreenNotes() -> [Note] {
        let d = FetchDescriptor<Note>(
            predicate: #Predicate { !$0.isTrashed && $0.showOnLockScreen },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let flagged = (try? fetch(d)) ?? []
        if !flagged.isEmpty { return flagged }
        let p = FetchDescriptor<Note>(
            predicate: #Predicate { !$0.isTrashed && $0.isPinned },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let pinned = (try? fetch(p)) ?? []
        if !pinned.isEmpty { return pinned }
        return activeNotes(limit: 1)
    }

    /// Open checklist items from Lock Screen notes first, then from any note, due-date first.
    func openTasks(limit: Int = 20) -> [ChecklistItem] {
        let d = FetchDescriptor<ChecklistItem>(predicate: #Predicate { !$0.isDone })
        let all = ((try? fetch(d)) ?? []).filter { $0.note?.isTrashed == false }
        return all.sorted { a, b in
            let aLock = a.note?.showOnLockScreen == true, bLock = b.note?.showOnLockScreen == true
            if aLock != bLock { return aLock }
            switch (a.dueDate, b.dueDate) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                let aDate = a.note?.updatedAt ?? .distantPast, bDate = b.note?.updatedAt ?? .distantPast
                if aDate != bDate { return aDate > bDate }
                return a.sortIndex < b.sortIndex
            }
        }
        .prefix(limit).map { $0 }
    }

    /// Items ticked off recently (newest first), for "Done" columns on the wallpaper.
    func recentlyCompletedTasks(limit: Int = 5, within days: Int = 2) -> [ChecklistItem] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let never = Date.distantPast
        var d = FetchDescriptor<ChecklistItem>(
            predicate: #Predicate { $0.isDone && ($0.completedAt ?? never) >= since },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        d.fetchLimit = limit * 2
        return ((try? fetch(d)) ?? []).filter { $0.note?.isTrashed == false }.prefix(limit).map { $0 }
    }

    func tasksDue(on day: Date) -> [ChecklistItem] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let never = Date.distantPast
        let d = FetchDescriptor<ChecklistItem>(
            predicate: #Predicate { item in
                (item.dueDate ?? never) >= start && (item.dueDate ?? never) < end
            },
            sortBy: [SortDescriptor(\.dueDate)]
        )
        return ((try? fetch(d)) ?? []).filter { $0.note?.isTrashed == false }
    }

    func dailyNote(for day: Date, create: Bool) -> Note? {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let never = Date.distantPast
        let d = FetchDescriptor<Note>(predicate: #Predicate { note in
            !note.isTrashed && (note.dailyDate ?? never) >= start && (note.dailyDate ?? never) < end
        })
        if let existing = try? fetch(d).first { return existing }
        guard create else { return nil }
        let note = Note()
        note.dailyDate = start
        note.emoji = "📅"
        insert(note)
        return note
    }
}
