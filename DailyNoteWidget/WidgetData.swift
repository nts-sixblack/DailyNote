import Foundation
import SwiftData
import SwiftUI
import WidgetKit

struct ItemSnapshot: Identifiable, Hashable {
    let id: UUID
    let text: String
    let isDone: Bool
    let due: Date?
    let noteTitle: String
}

struct NoteSnapshot: Identifiable, Hashable {
    let id: UUID
    let title: String
    let body: String
    let emoji: String
    let color: NoteColor
    let items: [ItemSnapshot]
    let updatedAt: Date

    var openItems: [ItemSnapshot] { items.filter { !$0.isDone } }
    var doneCount: Int { items.filter(\.isDone).count }

    init(_ note: Note) {
        id = note.id
        title = note.displayTitle
        body = note.bodyBelowTitle
        emoji = note.emoji
        color = note.color
        items = note.sortedItems.map {
            ItemSnapshot(id: $0.id, text: $0.text, isDone: $0.isDone, due: $0.dueDate, noteTitle: note.displayTitle)
        }
        updatedAt = note.updatedAt
    }

    init(id: UUID = UUID(), title: String, body: String, emoji: String, items: [ItemSnapshot] = []) {
        self.id = id
        self.title = title
        self.body = body
        self.emoji = emoji
        self.color = .orange
        self.items = items
        self.updatedAt = Date()
    }

    static let sample = NoteSnapshot(
        title: "Phòng học hôm nay",
        body: "Toán cao cấp – phòng B2.304\nMang máy tính, nộp bài tập chương 3",
        emoji: "📚",
        items: [
            ItemSnapshot(id: UUID(), text: "Nộp bài tập", isDone: false, due: nil, noteTitle: ""),
            ItemSnapshot(id: UUID(), text: "Mua sữa", isDone: true, due: nil, noteTitle: ""),
            ItemSnapshot(id: UUID(), text: "Gọi cho mẹ", isDone: false, due: nil, noteTitle: ""),
        ]
    )
}

enum WidgetData {
    static func note(for entity: NoteEntity?) -> NoteSnapshot? {
        let context = ModelContext(DataStore.container)
        if let entity, let note = context.note(id: entity.id), !note.isTrashed {
            return NoteSnapshot(note)
        }
        return context.lockScreenNotes().first.map(NoteSnapshot.init)
    }

    static func tasks(for entity: NoteEntity?, limit: Int = 12) -> (title: String, items: [ItemSnapshot], done: Int, total: Int, noteID: UUID?) {
        let context = ModelContext(DataStore.container)
        if let entity, let note = context.note(id: entity.id), !note.isTrashed {
            let snap = NoteSnapshot(note)
            let ordered = snap.openItems + snap.items.filter(\.isDone)
            return (snap.title, Array(ordered.prefix(limit)), snap.doneCount, snap.items.count, snap.id)
        }
        let open = context.openTasks(limit: limit).map {
            ItemSnapshot(id: $0.id, text: $0.text, isDone: $0.isDone, due: $0.dueDate, noteTitle: $0.note?.displayTitle ?? "")
        }
        // Progress for "today": items due today plus items completed today.
        let all = (try? context.fetch(FetchDescriptor<ChecklistItem>())) ?? []
        let today = all.filter { item in
            guard item.note?.isTrashed == false else { return false }
            if let done = item.completedAt, Calendar.current.isDateInToday(done) { return true }
            return !item.isDone
        }
        let done = today.filter(\.isDone).count
        return (String(localized: "Việc cần làm"), open, done, today.count, nil)
    }
}

extension View {
    /// Applies the right container background for Lock Screen vs Home Screen families.
    func widgetBackground(_ family: WidgetFamily, tint: Color = .clear) -> some View {
        containerBackground(for: .widget) {
            switch family {
            case .accessoryCircular, .accessoryRectangular, .accessoryInline:
                Color.clear
            default:
                ZStack {
                    Rectangle().fill(.background)
                    LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.04)], startPoint: .top, endPoint: .bottom)
                }
            }
        }
    }
}
