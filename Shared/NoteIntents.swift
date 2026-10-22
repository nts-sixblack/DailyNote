import AppIntents
import Foundation
import SwiftData
import WidgetKit

extension Notification.Name {
    static let dailyNotePendingAction = Notification.Name("DailyNotePendingAction")
}

// MARK: - Entity

struct NoteEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Ghi chú"
    static let defaultQuery = NoteEntityQuery()

    let id: UUID
    let title: String
    let emoji: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji.isEmpty ? "" : emoji + " ")\(title)")
    }

    init(id: UUID, title: String, emoji: String) {
        self.id = id
        self.title = title
        self.emoji = emoji
    }

    init(_ note: Note) {
        self.init(id: note.id, title: note.displayTitle, emoji: note.emoji)
    }
}

struct NoteEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [NoteEntity] {
        let context = ModelContext(DataStore.container)
        return identifiers.compactMap { context.note(id: $0) }.map(NoteEntity.init)
    }

    func entities(matching string: String) async throws -> [NoteEntity] {
        let context = ModelContext(DataStore.container)
        return context.activeNotes()
            .filter { $0.displayTitle.localizedStandardContains(string) || $0.body.localizedStandardContains(string) }
            .prefix(30).map(NoteEntity.init)
    }

    func suggestedEntities() async throws -> [NoteEntity] {
        let context = ModelContext(DataStore.container)
        let notes = context.activeNotes(limit: 40)
        let ordered = notes.filter(\.showOnLockScreen) + notes.filter { $0.isPinned && !$0.showOnLockScreen }
            + notes.filter { !$0.isPinned && !$0.showOnLockScreen }
        return ordered.map(NoteEntity.init)
    }
}

// MARK: - Widget configuration

struct SelectNoteIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Chọn ghi chú"
    static let description = IntentDescription("Chọn ghi chú muốn hiển thị. Để trống để tự động hiện ghi chú bạn đã gắn lên Lock Screen.")

    @Parameter(title: "Ghi chú")
    var note: NoteEntity?

    init() {}
    init(note: NoteEntity?) { self.note = note }
}

// MARK: - Interactive widget actions

struct ToggleChecklistItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Đánh dấu việc cần làm"
    static let isDiscoverable = false

    @Parameter(title: "Mã việc")
    var itemID: String

    init() {}
    init(itemID: UUID) { self.itemID = itemID.uuidString }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: itemID) else { return .result() }
        try DataStore.write { context in
            context.checklistItem(id: id)?.toggle()
        }
        return .result()
    }
}

struct ToggleRoutineIntent: AppIntent {
    static let title: LocalizedStringResource = "Đánh dấu việc hằng ngày"
    static let isDiscoverable = false

    @Parameter(title: "Mã việc")
    var routineID: String

    @Parameter(title: "Ngày")
    var day: Date

    init() {}
    init(routineID: UUID, day: Date) {
        self.routineID = routineID.uuidString
        self.day = day
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: routineID) else { return .result() }
        try DataStore.write { context in
            context.routine(id: id)?.toggle(on: day, in: context)
        }
        RoutineReminders.reschedule(context: ModelContext(DataStore.container))
        return .result()
    }
}

#if os(iOS)
// Live Activity intents run in the app's process (launched in the background if needed), so widget
// taps update the app's own context — open screens refresh at once and the change syncs to iCloud.
extension ToggleChecklistItemIntent: LiveActivityIntent {}
extension ToggleRoutineIntent: LiveActivityIntent {}
#endif

// MARK: - Open the app to compose (used by Lock Screen / Control Center controls)

struct NewNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Ghi chú mới"
    static let description = IntentDescription("Mở DailyNote và bắt đầu ghi chú ngay.")
    static let openAppWhenRun = true

    @Parameter(title: "Dạng danh sách việc", default: false)
    var checklist: Bool

    init() {}
    init(checklist: Bool) { self.checklist = checklist }

    func perform() async throws -> some IntentResult {
        UserDefaults.shared.set(checklist ? "newChecklist" : "newNote", forKey: AppConstants.Key.pendingAction)
        await MainActor.run {
            NotificationCenter.default.post(name: .dailyNotePendingAction, object: nil)
        }
        return .result()
    }
}

// MARK: - Capture without opening the app (Siri, Shortcuts, Action button)

struct QuickNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Ghi nhanh"
    static let description = IntentDescription("Lưu một ghi chú mới vào DailyNote mà không cần mở ứng dụng.")

    @Parameter(title: "Nội dung", inputOptions: String.IntentInputOptions(multiline: true),
               requestValueDialog: "Bạn muốn ghi gì?")
    var text: String

    @Parameter(title: "Hiện trên Lock Screen", default: true)
    var showOnLockScreen: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Ghi \(\.$text)") {
            \.$showOnLockScreen
        }
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<NoteEntity> & ProvidesDialog {
        let entity = try DataStore.write { context in
            let note = Note(body: text)
            note.showOnLockScreen = showOnLockScreen
            context.insert(note)
            return NoteEntity(note)
        }
        return .result(value: entity, dialog: "Đã lưu ghi chú.")
    }
}

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Thêm việc cần làm"
    static let description = IntentDescription("Thêm một việc vào danh sách Việc cần làm — hiện ở tab Hôm nay và widget.")

    @Parameter(title: "Việc cần làm", requestValueDialog: "Việc gì cần làm?")
    var text: String

    @Parameter(title: "Hạn")
    var dueDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Thêm \(\.$text)") {
            \.$dueDate
        }
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Without a due date the task is undated: it shows on today's list until done.
        let title = try DataStore.write { context in
            let target = context.taskInbox()
            _ = target.addItem(text, dueDate: dueDate)
            return target.displayTitle
        }
        return .result(dialog: "Đã thêm vào \(title).")
    }
}
