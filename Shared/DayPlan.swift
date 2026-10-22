import Foundation
import SwiftData
import UserNotifications

/// Everything to do on one day, built from the same checklist items the Notes tab edits:
/// - today: every open task that is undated, due today, or left over from earlier days (carried over),
///   plus tasks finished today;
/// - a past day: tasks finished that day, and tasks due that day that are still open;
/// - a future day: tasks due that day.
/// A task is ticked off on the day it was completed, whatever its due date.
struct DayPlan {
    let day: Date
    var routines: [Routine] = []
    /// Open tasks first (carried over, then by time), then the ones finished that day.
    var tasks: [ChecklistItem] = []

    var isToday: Bool { Calendar.current.isDateInToday(day) }
    var isFuture: Bool { day > Calendar.current.startOfDay(for: Date()) }

    var total: Int { routines.count + tasks.count }
    var done: Int { routines.filter { $0.isDone(on: day) }.count + tasks.filter(\.isDone).count }
    var progress: Double { total == 0 ? 0 : Double(done) / Double(total) }

    /// Whole days a task due before `day` has been waiting, or 0.
    static func daysCarried(_ item: ChecklistItem, to day: Date) -> Int {
        guard let due = item.dueDate, !item.isDone else { return 0 }
        let cal = Calendar.current
        return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: due), to: cal.startOfDay(for: day)).day ?? 0)
    }
}

extension ModelContext {
    func routine(id: UUID) -> Routine? {
        var d = FetchDescriptor<Routine>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? fetch(d).first
    }

    func routines() -> [Routine] {
        let d = FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)])
        return (try? fetch(d)) ?? []
    }

    func dayPlan(for day: Date) -> DayPlan {
        let items = ((try? fetch(FetchDescriptor<ChecklistItem>())) ?? []).filter(DayPlan.isListed)
        return DayPlan.make(day: day, routines: routines(), items: items)
    }

    /// The shared to-do list, created on first use. Prefers the flagged list (oldest, in case two devices
    /// both made one), then an existing "Việc cần làm" checklist.
    func taskInbox() -> Note {
        let flagged = FetchDescriptor<Note>(
            predicate: #Predicate { $0.isTaskInbox && !$0.isTrashed },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        if let inbox = try? fetch(flagged).first { return inbox }
        let title = String(localized: "Việc cần làm")
        let named = FetchDescriptor<Note>(
            predicate: #Predicate { $0.title == title && !$0.isTrashed && $0.dailyDate == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        if let existing = try? fetch(named).first {
            existing.isTaskInbox = true
            return existing
        }
        let note = Note(title: title)
        note.emoji = "✅"
        note.isTaskInbox = true
        insert(note)
        return note
    }

    /// Moves tasks that earlier versions stored in daily journal notes into the shared list, and drops
    /// journal notes that only existed to hold them.
    func moveJournalTasksToInbox() {
        let journals = FetchDescriptor<Note>(predicate: #Predicate { $0.dailyDate != nil })
        let withItems = ((try? fetch(journals)) ?? []).filter { !($0.items ?? []).isEmpty }
        guard !withItems.isEmpty else { return }
        let inbox = taskInbox()
        var next = ((inbox.items ?? []).map(\.sortIndex).max() ?? -1) + 1
        for journal in withItems {
            for item in journal.sortedItems {
                item.note = inbox
                item.sortIndex = next
                next += 1
            }
            journal.items = []
            if journal.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { delete(journal) }
        }
        inbox.touch()
        try? save()
    }
}

extension DayPlan {
    static func isListed(_ item: ChecklistItem) -> Bool {
        item.note?.isTrashed == false && !item.text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func make(day: Date, routines: [Routine], items: [ChecklistItem]) -> DayPlan {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let today = cal.startOfDay(for: Date())
        var plan = DayPlan(day: start)

        plan.routines = routines
            .filter { $0.isScheduled(on: start) || $0.isDone(on: start) }
            .sorted { a, b in
                switch (a.hasTime, b.hasTime) {
                case (true, false): return true
                case (false, true): return false
                case (true, true) where a.minuteOfDay != b.minuteOfDay: return a.minuteOfDay < b.minuteOfDay
                default: return (a.sortIndex, a.createdAt) < (b.sortIndex, b.createdAt)
                }
            }

        func inDay(_ date: Date?) -> Bool { date.map { cal.isDate($0, inSameDayAs: start) } ?? false }

        let open = items.filter { item in
            guard !item.isDone else { return false }
            if start == today {
                guard let due = item.dueDate else { return true }
                return cal.startOfDay(for: due) <= start
            }
            // Past days keep what was due then; future days show what is planned.
            return inDay(item.dueDate)
        }
        .sorted { a, b in
            let ca = daysCarried(a, to: start), cb = daysCarried(b, to: start)
            if (ca > 0) != (cb > 0) { return ca > 0 }
            if ca != cb { return ca > cb }
            let ta = a.isAllDay ? nil : a.dueDate, tb = b.isAllDay ? nil : b.dueDate
            switch (ta, tb) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return (a.createdAt, a.sortIndex) < (b.createdAt, b.sortIndex)
            }
        }
        let finished = items.filter { item in
            guard item.isDone else { return false }
            if let completed = item.completedAt { return inDay(completed) }
            return inDay(item.dueDate)
        }
        .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }

        plan.tasks = open + finished
        return plan
    }
}

// MARK: - Routine reminders

/// Keeps one-shot notifications for the next few days of each routine, skipping days already done,
/// so finishing a routine early silences that day's reminder.
enum RoutineReminders {
    static let category = "ROUTINE"
    static let doneAction = "ROUTINE_DONE"
    private static let prefix = "routine-"
    private static let horizonDays = 4

    static func reschedule(context: ModelContext) {
        let center = UNUserNotificationCenter.current()
        let routines = context.routines().filter { $0.remind && $0.hasTime && !$0.isPaused }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var requests: [UNNotificationRequest] = []
        for offset in 0..<horizonDays {
            let day = cal.date(byAdding: .day, value: offset, to: today)!
            for routine in routines where routine.isScheduled(on: day) && !routine.isDone(on: day) {
                guard let fire = routine.time(on: day), fire > Date() else { continue }
                let content = UNMutableNotificationContent()
                content.title = [routine.emoji, routine.title].filter { !$0.isEmpty }.joined(separator: " ")
                let streak = routine.streak()
                content.body = streak > 1
                    ? String(localized: "Giữ chuỗi \(streak) ngày nhé 🔥")
                    : String(localized: "Việc hằng ngày của bạn")
                content.sound = .default
                content.categoryIdentifier = category
                content.interruptionLevel = .timeSensitive
                content.userInfo = ["routineID": routine.id.uuidString, "day": day.timeIntervalSince1970]
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                requests.append(UNNotificationRequest(
                    identifier: "\(prefix)\(routine.id.uuidString)-\(Int(day.timeIntervalSince1970))",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                ))
            }
        }
        // Stay well under iOS's 64 pending notification limit.
        let wanted = requests.sorted { fireDate($0) < fireDate($1) }.prefix(40)
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            wanted.forEach { center.add($0) }
        }
    }

    private static func fireDate(_ request: UNNotificationRequest) -> Date {
        (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
    }
}
