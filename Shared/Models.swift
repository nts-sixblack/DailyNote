import Foundation
import SwiftData
import SwiftUI

// CloudKit-backed SwiftData rules: every attribute has a default or is optional,
// relationships are optional, and there are no unique constraints.

@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "folder"
    var colorName: String = NoteColor.orange.rawValue
    var sortIndex: Int = 0
    var createdAt: Date = Date()
    @Relationship(deleteRule: .nullify, inverse: \Note.folder) var notes: [Note]? = []

    init(name: String, symbol: String = "folder", color: NoteColor = .orange, sortIndex: Int = 0) {
        self.name = name
        self.symbol = symbol
        self.colorName = color.rawValue
        self.sortIndex = sortIndex
    }

    var color: NoteColor { NoteColor(rawValue: colorName) ?? .orange }
    var activeNotes: [Note] { (notes ?? []).filter { !$0.isTrashed } }
}

@Model
final class Note {
    var id: UUID = UUID()
    var title: String = ""
    var body: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isPinned: Bool = false
    var showOnLockScreen: Bool = false
    var isTrashed: Bool = false
    var trashedAt: Date?
    var colorName: String = NoteColor.none.rawValue
    var emoji: String = ""
    /// Start of day for daily journal notes; nil for regular notes.
    var dailyDate: Date?
    var reminderDate: Date?
    /// The shared to-do list that tasks added from the Today tab, Siri and widgets go into.
    var isTaskInbox: Bool = false
    var folder: Folder?
    @Relationship(deleteRule: .cascade, inverse: \ChecklistItem.note) var items: [ChecklistItem]? = []

    init(title: String = "", body: String = "", folder: Folder? = nil) {
        self.title = title
        self.body = body
        self.folder = folder
    }

    var color: NoteColor {
        get { NoteColor(rawValue: colorName) ?? .none }
        set { colorName = newValue.rawValue }
    }

    var sortedItems: [ChecklistItem] {
        (items ?? []).sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    var openItems: [ChecklistItem] { sortedItems.filter { !$0.isDone } }

    var hasChecklist: Bool { !(items ?? []).isEmpty }

    var progress: Double {
        let all = items ?? []
        guard !all.isEmpty else { return 0 }
        return Double(all.filter(\.isDone).count) / Double(all.count)
    }

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        if let daily = dailyDate { return daily.formatted(.dateTime.weekday(.wide).day().month()) }
        let firstLine = body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
        if let firstLine, !firstLine.isEmpty { return Note.stripMarkdown(firstLine) }
        if let first = sortedItems.first { return first.text }
        return String(localized: "Ghi chú mới")
    }

    var preview: String {
        let text = bodyBelowTitle
            .split(separator: "\n", omittingEmptySubsequences: true)
            .joined(separator: " ")
        if !text.isEmpty { return text }
        if hasChecklist {
            return sortedItems.prefix(3).map { ($0.isDone ? "✓ " : "○ ") + $0.text }.joined(separator: "  ")
        }
        return ""
    }

    var tags: [String] { Note.extractTags(from: body + " " + title) }

    /// Body text without the line that `displayTitle` already shows when the title is empty.
    var bodyBelowTitle: String {
        let plain = Note.stripMarkdown(body).trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.trimmingCharacters(in: .whitespaces).isEmpty, dailyDate == nil else { return plain }
        var lines = plain.split(separator: "\n", omittingEmptySubsequences: false)
        if !lines.isEmpty { lines.removeFirst() }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var wordCount: Int {
        body.split { $0.isWhitespace || $0.isNewline }.count
    }

    func touch() { updatedAt = Date() }

    func moveToTrash() {
        isTrashed = true
        trashedAt = Date()
        isPinned = false
        showOnLockScreen = false
        touch()
    }

    func restore() {
        isTrashed = false
        trashedAt = nil
        touch()
    }

    func addItem(_ text: String, dueDate: Date? = nil, isAllDay: Bool = false) -> ChecklistItem {
        let nextIndex = ((items ?? []).map(\.sortIndex).max() ?? -1) + 1
        let item = ChecklistItem(text: text, sortIndex: nextIndex, dueDate: dueDate, isAllDay: isAllDay)
        if items == nil { items = [] }
        items?.append(item)
        touch()
        return item
    }

    static func extractTags(from text: String) -> [String] {
        var result: [String] = []
        let pattern = /#([\p{L}\p{N}_\-]+)/
        for match in text.matches(of: pattern) {
            let tag = String(match.output.1).lowercased()
            if !result.contains(tag) { result.append(tag) }
        }
        return result
    }

    static func stripMarkdown(_ text: String) -> String {
        var t = text
        for token in ["**", "__", "~~", "`"] { t = t.replacingOccurrences(of: token, with: "") }
        t = t.replacing(/(?m)^\s{0,3}(#{1,6}|>|[-*+]\s\[[ xX]\]|[-*+])\s+/, with: "")
        return t
    }
}

@Model
final class ChecklistItem {
    var id: UUID = UUID()
    var text: String = ""
    var isDone: Bool = false
    var sortIndex: Int = 0
    var dueDate: Date?
    var createdAt: Date = Date()
    var completedAt: Date?
    /// The task belongs to the day of `dueDate` without a specific time.
    var isAllDay: Bool = false
    var note: Note?

    init(text: String, sortIndex: Int = 0, dueDate: Date? = nil, isAllDay: Bool = false) {
        self.text = text
        self.sortIndex = sortIndex
        self.isAllDay = isAllDay
        self.dueDate = isAllDay ? dueDate.map { Calendar.current.startOfDay(for: $0) } : dueDate
    }

    func toggle() {
        isDone.toggle()
        completedAt = isDone ? Date() : nil
        note?.touch()
    }

    /// Overdue once its time has passed, or the day after for all-day tasks.
    var isOverdue: Bool {
        guard let dueDate, !isDone else { return false }
        return isAllDay ? dueDate < Calendar.current.startOfDay(for: Date()) : dueDate < Date()
    }

    /// Moves the task to `day`, keeping its time of day if it has one.
    func schedule(on day: Date) {
        let cal = Calendar.current
        if let dueDate, !isAllDay {
            let time = cal.dateComponents([.hour, .minute], from: dueDate)
            self.dueDate = cal.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day)
        } else {
            self.dueDate = cal.startOfDay(for: day)
            isAllDay = true
        }
        note?.touch()
    }

    var dueLabel: String? {
        guard let dueDate else { return nil }
        let cal = Calendar.current
        if isAllDay {
            if cal.isDateInToday(dueDate) { return String(localized: "Hôm nay") }
            if cal.isDateInTomorrow(dueDate) { return String(localized: "Ngày mai") }
            if cal.isDateInYesterday(dueDate) { return String(localized: "Hôm qua") }
            return dueDate.formatted(.dateTime.weekday().day().month())
        }
        if cal.isDateInToday(dueDate) { return dueDate.formatted(.dateTime.hour().minute()) }
        return dueDate.formatted(.dateTime.weekday().day().month().hour().minute())
    }
}

/// A task repeated on chosen weekdays, ticked off separately for each day.
@Model
final class Routine {
    var id: UUID = UUID()
    var title: String = ""
    var emoji: String = ""
    /// Minutes after midnight, or -1 for "any time of the day".
    var minuteOfDay: Int = -1
    /// Bit n set = repeats on weekday n+1 (1 = Sunday … 7 = Saturday, as in `Calendar`). 127 = every day.
    var weekdayMask: Int = 127
    var remind: Bool = true
    var isPaused: Bool = false
    var sortIndex: Int = 0
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \RoutineLog.routine) var logs: [RoutineLog]? = []

    init(title: String, emoji: String = "", minuteOfDay: Int = -1, weekdayMask: Int = 127, sortIndex: Int = 0) {
        self.title = title
        self.emoji = emoji
        self.minuteOfDay = minuteOfDay
        self.weekdayMask = weekdayMask
        self.sortIndex = sortIndex
    }

    static let everyDay = 127
    static let weekdays = 0b0111110
    static let weekend = 0b1000001

    var hasTime: Bool { minuteOfDay >= 0 }

    func time(on day: Date) -> Date? {
        guard hasTime else { return nil }
        return Calendar.current.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: day)
    }

    var timeLabel: String? {
        time(on: Date()).map { $0.formatted(.dateTime.hour().minute()) }
    }

    func repeats(onWeekday weekday: Int) -> Bool { weekdayMask & (1 << (weekday - 1)) != 0 }

    /// Scheduled on `day`: active, created by then and repeating on that weekday.
    func isScheduled(on day: Date) -> Bool {
        let cal = Calendar.current
        guard !isPaused, cal.startOfDay(for: createdAt) <= cal.startOfDay(for: day) else { return false }
        return repeats(onWeekday: cal.component(.weekday, from: day))
    }

    func isDone(on day: Date) -> Bool {
        (logs ?? []).contains { Calendar.current.isDate($0.day, inSameDayAs: day) }
    }

    func setDone(_ done: Bool, on day: Date, in context: ModelContext) {
        let existing = (logs ?? []).filter { Calendar.current.isDate($0.day, inSameDayAs: day) }
        if done {
            guard existing.isEmpty else { return }
            let log = RoutineLog(day: day)
            context.insert(log)
            log.routine = self
        } else {
            // Sync can leave duplicates for the same day; clear them all.
            existing.forEach(context.delete)
        }
    }

    func toggle(on day: Date, in context: ModelContext) {
        setDone(!isDone(on: day), on: day, in: context)
    }

    /// Consecutive scheduled days completed, counting today only once it is done.
    func streak(asOf today: Date = Date()) -> Int {
        let cal = Calendar.current
        let doneDays = Set((logs ?? []).map { cal.startOfDay(for: $0.day) })
        var day = cal.startOfDay(for: today)
        if !doneDays.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        for _ in 0..<366 {
            if isScheduled(on: day) {
                guard doneDays.contains(day) else { break }
                count += 1
            } else if day < cal.startOfDay(for: createdAt) {
                break
            }
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    var repeatLabel: String {
        switch weekdayMask {
        case Routine.everyDay: return String(localized: "Mỗi ngày")
        case Routine.weekdays: return String(localized: "Thứ 2 – Thứ 6")
        case Routine.weekend: return String(localized: "Cuối tuần")
        default:
            return Routine.orderedWeekdays.filter(repeats(onWeekday:)).map(Routine.shortName).joined(separator: ", ")
        }
    }

    /// Weekdays in display order, following the calendar setting.
    static var orderedWeekdays: [Int] {
        CalendarPrefs.weekStartsMonday ? [2, 3, 4, 5, 6, 7, 1] : [1, 2, 3, 4, 5, 6, 7]
    }

    static func shortName(_ weekday: Int) -> String {
        weekday == 1 ? String(localized: "CN") : String(localized: "T\(weekday)")
    }
}

@Model
final class RoutineLog {
    var id: UUID = UUID()
    /// Start of the day the routine was completed for.
    var day: Date = Date()
    var completedAt: Date = Date()
    var routine: Routine?

    init(day: Date) {
        self.day = Calendar.current.startOfDay(for: day)
    }
}

enum NoteColor: String, CaseIterable, Identifiable, Codable {
    case none, red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .none: .secondary
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        }
    }

    var label: String {
        switch self {
        case .none: "Không màu"
        case .red: "Đỏ"
        case .orange: "Cam"
        case .yellow: "Vàng"
        case .green: "Xanh lá"
        case .mint: "Bạc hà"
        case .teal: "Xanh ngọc"
        case .blue: "Xanh dương"
        case .indigo: "Chàm"
        case .purple: "Tím"
        case .pink: "Hồng"
        case .brown: "Nâu"
        }
    }
}
