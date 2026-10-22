import Foundation
import Observation
import SwiftData
import SwiftUI
import WidgetKit

enum AppTab: Hashable {
    case notes, today, calendar, lockScreen, search
}

enum SidebarItem: Hashable {
    case all, pinned, lockScreen, checklists, daily, trash
    case folder(Folder)
    case tag(String)

    var title: String {
        switch self {
        case .all: String(localized: "Tất cả ghi chú")
        case .pinned: String(localized: "Đã ghim")
        case .lockScreen: String(localized: "Trên Lock Screen")
        case .checklists: String(localized: "Việc cần làm")
        case .daily: String(localized: "Nhật ký hằng ngày")
        case .trash: String(localized: "Thùng rác")
        case .folder(let f): f.name
        case .tag(let t): "#\(t)"
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray.full"
        case .pinned: "pin"
        case .lockScreen: "lock.iphone"
        case .checklists: "checklist"
        case .daily: "calendar.day.timeline.left"
        case .trash: "trash"
        case .folder(let f): f.symbol
        case .tag: "number"
        }
    }

    func includes(_ note: Note) -> Bool {
        switch self {
        case .trash: return note.isTrashed
        case _ where note.isTrashed: return false
        case .all: return true
        case .pinned: return note.isPinned
        case .lockScreen: return note.showOnLockScreen
        case .checklists: return note.hasChecklist
        case .daily: return note.dailyDate != nil
        case .folder(let f): return note.folder?.id == f.id
        case .tag(let t): return note.tags.contains(t)
        }
    }
}

enum NoteSort: String, CaseIterable, Identifiable {
    case updated, created, title
    var id: String { rawValue }
    var label: String {
        switch self {
        case .updated: "Ngày sửa"
        case .created: "Ngày tạo"
        case .title: "Tiêu đề"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var tab: AppTab = .notes
    var sidebar: SidebarItem? = .all
    var selectedNote: Note?
    var sort: NoteSort = .updated
    var focusNewNote = false
    /// Presents the Lock Screen automation guide (deep link or a failed shortcut run).
    var showLockScreenSetup = false

    /// The main context every screen uses.
    let context = DataStore.container.mainContext
    /// Bumped after an extension wrote to the store, so the view tree rebuilds and re-reads models.
    private(set) var storeGeneration = 0
    private var seenExternalWrite = DataStore.lastExternalWrite

    private var reloadTask: Task<Void, Never>?

    init() {
        context.moveJournalTasksToInbox()
        ExternalWriteObserver.start { [weak self] in self?.reloadIfStoreChangedExternally() }
    }

    /// Widgets and Siri extensions write to the store from another process. The main context never
    /// hears about it and @Query keeps showing cached rows, so refetch every model type (which refreshes
    /// the registered objects and their relationships) and rebuild the views.
    func reloadIfStoreChangedExternally() {
        let stamp = DataStore.lastExternalWrite
        guard stamp > seenExternalWrite else { return }
        seenExternalWrite = stamp
        try? context.save()
        _ = try? context.fetch(FetchDescriptor<Folder>())
        _ = try? context.fetch(FetchDescriptor<Note>())
        _ = try? context.fetch(FetchDescriptor<ChecklistItem>())
        _ = try? context.fetch(FetchDescriptor<Routine>())
        _ = try? context.fetch(FetchDescriptor<RoutineLog>())
        if let note = selectedNote, note.isDeleted || context.note(id: note.id) == nil { selectedNote = nil }
        storeGeneration += 1
        RoutineReminders.reschedule(context: context)
    }

    func createNote(in context: ModelContext, checklist: Bool = false) {
        let folder: Folder? = if case .folder(let f) = sidebar { f } else { nil }
        let note = Note(folder: folder)
        if sidebar == .lockScreen { note.showOnLockScreen = true }
        if sidebar == .pinned { note.isPinned = true }
        if checklist {
            note.title = String(localized: "Việc cần làm")
            note.emoji = "✅"
        }
        context.insert(note)
        if sidebar == .trash || sidebar == .daily || (sidebar.map { !$0.includes(note) } ?? false) {
            sidebar = .all
        }
        tab = .notes
        selectedNote = note
        focusNewNote = true
        scheduleWidgetReload(context: context)
    }

    func open(_ note: Note) {
        tab = .notes
        if let current = sidebar, !current.includes(note) { sidebar = note.isTrashed ? .trash : .all }
        selectedNote = note
    }

    func handle(_ link: DeepLink, context: ModelContext) {
        switch link {
        case .newNote: createNote(in: context)
        case .capture(let text):
            let note = Note(body: text)
            context.insert(note)
            try? context.save()
            open(note)
            scheduleWidgetReload(context: context, delay: .zero)
        case .newChecklist: createNote(in: context, checklist: true)
        case .note(let id): if let note = context.note(id: id) { open(note) }
        case .today: tab = .today
        case .calendar: tab = .calendar
        case .lockScreen: tab = .lockScreen
        case .lockScreenSetup:
            tab = .lockScreen
            showLockScreenSetup = true
        }
    }

    /// Consumes an action requested by a Lock Screen control or App Intent.
    func consumePendingAction(context: ModelContext) {
        guard let action = UserDefaults.shared.string(forKey: AppConstants.Key.pendingAction) else { return }
        UserDefaults.shared.removeObject(forKey: AppConstants.Key.pendingAction)
        handle(action == "newChecklist" ? .newChecklist : .newNote, context: context)
    }

    /// Debounced save + widget refresh so typing doesn't thrash WidgetKit.
    func scheduleWidgetReload(context: ModelContext, delay: Duration = .seconds(1.2)) {
        reloadTask?.cancel()
        reloadTask = Task { [weak context] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            try? context?.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

/// Listens for the Darwin notification extensions post after writing, so an open app refreshes too.
enum ExternalWriteObserver {
    @MainActor private static var handler: (() -> Void)?

    @MainActor
    static func start(_ onChange: @escaping @MainActor () -> Void) {
        guard handler == nil else { return }
        handler = onChange
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil,
            { _, _, _, _, _ in
                Task { @MainActor in ExternalWriteObserver.handler?() }
            },
            DataStore.externalWriteNotification as CFString, nil, .deliverImmediately
        )
    }
}
