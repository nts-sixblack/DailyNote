import SwiftData
import SwiftUI
import WidgetKit

struct AgendaEntry: TimelineEntry {
    let date: Date
    let events: [AgendaEvent]
    let busyDays: Set<Date>
    let openTasks: Int
    let hasAccess: Bool
    let marker: TodayMarker
    let calendar: Calendar

    var nextEvents: [AgendaEvent] { events.filter { $0.end > date } }
}

struct AgendaProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgendaEntry {
        let now = Date()
        return AgendaEntry(
            date: now,
            events: [
                AgendaEvent(id: "1", title: "Họp nhóm", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200),
                            isAllDay: false, location: "Phòng B2.304", notes: nil, calendarTitle: "", colorComponents: [0.3, 0.5, 1]),
                AgendaEvent(id: "2", title: "Gym", start: now.addingTimeInterval(4 * 3600), end: now.addingTimeInterval(5 * 3600),
                            isAllDay: false, location: nil, notes: nil, calendarTitle: "", colorComponents: [1, 0.5, 0.2]),
            ],
            busyDays: [], openTasks: 3, hasAccess: true, marker: CalendarPrefs.todayMarker, calendar: CalendarPrefs.calendar
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (AgendaEntry) -> Void) {
        let entry = load(at: .now)
        completion(context.isPreview && entry.events.isEmpty ? placeholder(in: context) : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgendaEntry>) -> Void) {
        let now = Date()
        let base = load(at: now)
        // One entry now and one at each event end so "next up" stays current.
        var dates = [now]
        dates += base.events.map(\.end).filter { $0 > now }.prefix(8)
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        let entries = dates.filter { $0 < midnight }.map { date in
            AgendaEntry(date: date, events: base.events, busyDays: base.busyDays, openTasks: base.openTasks,
                        hasAccess: base.hasAccess, marker: base.marker, calendar: base.calendar)
        }
        completion(Timeline(entries: entries, policy: .after(min(midnight, now.addingTimeInterval(2 * 3600)))))
    }

    private func load(at date: Date) -> AgendaEntry {
        let context = ModelContext(DataStore.container)
        let cal = CalendarPrefs.calendar
        return AgendaEntry(
            date: date,
            events: CalendarStore.upcoming(limit: 8, days: 3),
            busyDays: CalendarStore.busyDays(inMonthOf: date, calendar: cal),
            openTasks: context.openTasks(limit: 99).count,
            hasAccess: CalendarStore.hasFullAccess,
            marker: CalendarPrefs.todayMarker,
            calendar: cal
        )
    }
}

struct AgendaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConstants.WidgetKind.agenda, provider: AgendaProvider()) { entry in
            AgendaWidgetView(entry: entry)
        }
        .configurationDisplayName("Lịch & sự kiện")
        .description("Lịch tháng và các sự kiện sắp tới, kèm địa điểm.")
        .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(iOS)
        [.accessoryRectangular, .accessoryInline, .systemSmall, .systemMedium, .systemLarge]
        #else
        [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}

struct AgendaWidgetView: View {
    let entry: AgendaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(DeepLink.calendar.url)
            .widgetBackground(family, tint: .blue)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            if let next = entry.nextEvents.first {
                Text("\(next.timeText) \(next.title)")
            } else {
                Text(entry.date, format: .dateTime.weekday(.wide).day().month())
            }
        case .accessoryRectangular:
            rectangular
        case .systemSmall:
            small
        case .systemMedium:
            HStack(alignment: .top, spacing: 12) {
                MiniMonthView(month: entry.date, busyDays: entry.busyDays, marker: entry.marker,
                              accent: .accentColor, fontSize: 10, calendar: entry.calendar)
                    .frame(maxWidth: 150)
                eventList(limit: 3)
            }
        default:
            VStack(alignment: .leading, spacing: 12) {
                MiniMonthView(month: entry.date, busyDays: entry.busyDays, marker: entry.marker,
                              accent: .accentColor, fontSize: 13, calendar: entry.calendar)
                Divider()
                eventList(limit: 4)
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if !entry.hasAccess {
                Text("Mở DailyNote để kết nối Lịch").font(.caption)
            } else if entry.nextEvents.isEmpty {
                Text(entry.date, format: .dateTime.weekday(.wide).day().month())
                    .font(.headline).widgetAccentable()
                Text(entry.openTasks > 0 ? "Không có sự kiện · \(entry.openTasks) việc" : "Không có sự kiện")
                    .font(.caption)
            } else {
                ForEach(entry.nextEvents.prefix(2)) { event in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            Text(eventTime(event)).font(.system(size: 12, weight: .bold, design: .rounded)).widgetAccentable()
                            Text(event.title).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                        }
                        if entry.nextEvents.count == 1, let loc = event.location, !loc.isEmpty {
                            Text(loc).font(.system(size: 11, design: .rounded)).lineLimit(1).opacity(0.8)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.date, format: .dateTime.weekday(.wide))
                .font(.caption.weight(.bold)).foregroundStyle(.red).textCase(.uppercase)
            Text(entry.date, format: .dateTime.day())
                .font(.system(size: 40, weight: .bold, design: .rounded))
            eventList(limit: 2, compact: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func eventList(limit: Int, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            if !entry.hasAccess {
                Text("Mở DailyNote để kết nối Lịch").font(.caption).foregroundStyle(.secondary)
            } else if entry.nextEvents.isEmpty {
                Text("Không có sự kiện sắp tới").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(entry.nextEvents.prefix(limit)) { event in
                HStack(alignment: .top, spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5).fill(event.color).frame(width: 3)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(event.title).font(.system(compact ? .caption : .subheadline, design: .rounded).weight(.semibold)).lineLimit(1)
                        Text(eventTime(event) + (event.location.map { $0.isEmpty ? "" : " · \($0)" } ?? ""))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if entry.openTasks > 0 && !compact {
                Label("\(entry.openTasks) việc cần làm", systemImage: "checklist")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func eventTime(_ event: AgendaEvent) -> String {
        if Calendar.current.isDate(event.start, inSameDayAs: entry.date) || event.start < entry.date { return event.timeText }
        return event.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

// MARK: - Date (circular Lock Screen)

struct DateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConstants.WidgetKind.date, provider: AgendaProvider()) { entry in
            DateWidgetView(entry: entry)
        }
        .configurationDisplayName("Ngày & lịch")
        .description("Ngày hôm nay và số sự kiện còn lại.")
        .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(iOS)
        [.accessoryCircular]
        #else
        [.systemSmall]
        #endif
    }
}

struct DateWidgetView: View {
    let entry: AgendaEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -2) {
                Text(entry.date, format: .dateTime.weekday(.abbreviated))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .widgetAccentable()
                Text(entry.date, format: .dateTime.day())
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                let remaining = entry.nextEvents.filter { Calendar.current.isDate($0.start, inSameDayAs: entry.date) }.count
                if remaining > 0 {
                    Text("\(remaining) sk").font(.system(size: 9, weight: .semibold, design: .rounded))
                }
            }
        }
        .widgetURL(DeepLink.today.url)
        .containerBackground(for: .widget) { Color.clear }
    }
}
