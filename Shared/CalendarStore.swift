import EventKit
import Foundation
import SwiftUI

/// Lightweight, Sendable snapshot of a calendar event for views and widgets.
struct AgendaEvent: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let calendarTitle: String
    let colorComponents: [Double]

    var color: Color {
        guard colorComponents.count >= 3 else { return .accentColor }
        return Color(red: colorComponents[0], green: colorComponents[1], blue: colorComponents[2])
    }

    var timeText: String {
        if isAllDay { return String(localized: "Cả ngày") }
        return start.formatted(date: .omitted, time: .shortened)
    }
}

enum CalendarStore {
    static let eventStore = EKEventStore()

    static var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    static var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    static func requestAccess() async -> Bool {
        (try? await eventStore.requestFullAccessToEvents()) ?? false
    }

    static func events(from start: Date, to end: Date) -> [AgendaEvent] {
        guard hasFullAccess else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate)
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map(AgendaEvent.init)
    }

    static func events(on day: Date) -> [AgendaEvent] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return events(from: start, to: end)
    }

    /// Upcoming events from now (events already finished today are skipped).
    static func upcoming(limit: Int, days: Int = 7) -> [AgendaEvent] {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: now))!
        return events(from: Calendar.current.startOfDay(for: now), to: end)
            .filter { $0.end > now }
            .prefix(limit).map { $0 }
    }

    /// Set of start-of-day dates that contain at least one event, for month grids.
    static func busyDays(inMonthOf date: Date, calendar: Calendar = .current) -> Set<Date> {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return [] }
        var days = Set<Date>()
        for event in events(from: interval.start, to: interval.end) {
            var day = calendar.startOfDay(for: event.start)
            let last = event.end.addingTimeInterval(-1)
            while day <= last && day < interval.end {
                days.insert(day)
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
        }
        return days
    }

    static func ekEvent(id: String) -> EKEvent? {
        eventStore.event(withIdentifier: id)
    }
}

extension AgendaEvent {
    init(_ event: EKEvent) {
        var comps: [Double] = []
        if let cg = event.calendar?.cgColor, let c = cg.components, c.count >= 3 {
            comps = c.prefix(3).map { Double($0) }
        }
        self.init(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? String(localized: "Sự kiện"),
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            calendarTitle: event.calendar?.title ?? "",
            colorComponents: comps
        )
    }
}

/// Month grid helper shared by the app calendar, widgets and wallpapers.
struct MonthGrid {
    let month: Date
    let calendar: Calendar

    init(month: Date, calendar: Calendar = CalendarPrefs.calendar) {
        self.month = month
        self.calendar = calendar
    }

    /// Weekday symbols ordered by the calendar's first weekday.
    var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// Dates for the grid cells; nil for leading/trailing blanks.
    var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let dayCount = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            result.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    var weeks: [[Date?]] {
        let c = cells
        return stride(from: 0, to: c.count, by: 7).map { Array(c[$0..<min($0 + 7, c.count)]) }
    }

    var title: String {
        month.formatted(.dateTime.month(.wide).year())
    }
}
