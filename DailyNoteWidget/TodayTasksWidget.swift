import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

/// One tickable line on the Today widget: a routine or a task.
struct TodayRow: Identifiable, Hashable {
    enum Kind: Hashable { case routine, task }
    let kind: Kind
    let refID: UUID
    let title: String
    let emoji: String
    let time: Date?
    let isDone: Bool
    let isOverdue: Bool
    let streak: Int

    var id: String { "\(kind)-\(refID)" }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let day: Date
    let rows: [TodayRow]
    let done: Int
    let total: Int

    var progress: Double { total == 0 ? 0 : Double(done) / Double(total) }
    var open: [TodayRow] { rows.filter { !$0.isDone } }
    /// Open rows first (routines and tasks by time), then the finished ones.
    var ordered: [TodayRow] { open + rows.filter(\.isDone) }

    static let sample: TodayEntry = {
        let today = Calendar.current.startOfDay(for: .now)
        func at(_ h: Int, _ m: Int = 0) -> Date { Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: today)! }
        let rows = [
            TodayRow(kind: .routine, refID: UUID(), title: "Uống nước", emoji: "💧", time: at(8), isDone: true, isOverdue: false, streak: 12),
            TodayRow(kind: .routine, refID: UUID(), title: "Tập thể dục", emoji: "🏃", time: at(18, 30), isDone: false, isOverdue: false, streak: 5),
            TodayRow(kind: .task, refID: UUID(), title: "Nộp báo cáo", emoji: "", time: at(15), isDone: false, isOverdue: false, streak: 0),
            TodayRow(kind: .task, refID: UUID(), title: "Mua sữa", emoji: "", time: nil, isDone: false, isOverdue: false, streak: 0),
        ]
        return TodayEntry(date: .now, day: today, rows: rows, done: 1, total: 4)
    }()
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let entry = Self.load(at: .now)
        completion(context.isPreview && entry.rows.isEmpty ? .sample : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date.now
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        // Re-render at each timed item so it turns red once due.
        let base = Self.load(at: now)
        let times = Set(base.rows.compactMap(\.time).filter { $0 > now && $0 < midnight }).sorted().prefix(12)
        var entries = [base]
        for t in times { entries.append(Self.load(at: t)) }
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }

    static func load(at date: Date) -> TodayEntry {
        let context = ModelContext(DataStore.container)
        let plan = context.dayPlan(for: date)
        let routines = plan.routines.map { r in
            let time = r.time(on: plan.day)
            let done = r.isDone(on: plan.day)
            return TodayRow(kind: .routine, refID: r.id, title: r.title, emoji: r.emoji, time: time, isDone: done,
                            isOverdue: !done && (time.map { $0 < date } ?? false), streak: r.streak(asOf: date))
        }
        let tasks = plan.tasks.map { item in
            let carried = DayPlan.daysCarried(item, to: plan.day) > 0
            return TodayRow(kind: .task, refID: item.id, title: item.text, emoji: "",
                            time: item.isAllDay || carried ? nil : item.dueDate, isDone: item.isDone,
                            isOverdue: !item.isDone && (carried || (!item.isAllDay && (item.dueDate ?? .distantFuture) < date)),
                            streak: 0)
        }
        // Overdue first, then by time of day (untimed last), keeping routines before tasks on ties.
        let rows = (routines + tasks).enumerated().sorted { a, b in
            if a.element.isOverdue != b.element.isOverdue { return a.element.isOverdue }
            switch (a.element.time, b.element.time) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
        return TodayEntry(date: date, day: plan.day, rows: rows, done: plan.done, total: plan.total)
    }
}

struct TodayTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConstants.WidgetKind.today, provider: TodayProvider()) { entry in
            TodayTasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Việc hôm nay")
        .description("Việc hằng ngày và việc của hôm nay — chạm để đánh dấu xong, kể cả trên Lock Screen.")
        .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(iOS)
        [.accessoryRectangular, .accessoryCircular, .accessoryInline, .systemSmall, .systemMedium, .systemLarge]
        #else
        [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}

struct TodayTasksWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(DeepLink.today.url)
            .widgetBackground(family, tint: .green)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            if let next = entry.open.first {
                Text("\(entry.done)/\(entry.total) · \(next.title)")
            } else {
                Text(entry.total == 0 ? "Hôm nay chưa có việc" : "✓ Xong hết \(entry.total) việc")
            }
        case .accessoryCircular:
            Gauge(value: entry.progress) {
                Image(systemName: "checkmark")
            } currentValueLabel: {
                Text("\(entry.done)/\(entry.total)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                if entry.open.isEmpty {
                    Label(entry.total == 0 ? "Hôm nay chưa có việc" : "Xong hết việc hôm nay", systemImage: "checkmark.seal")
                        .font(.headline)
                        .widgetAccentable()
                    Text(entry.total == 0 ? "Chạm để thêm việc" : "\(entry.done)/\(entry.total) việc").font(.caption)
                } else {
                    ForEach(entry.open.prefix(3)) { row in
                        toggleButton(row) {
                            HStack(spacing: 4) {
                                Image(systemName: row.kind == .routine ? "circle.dashed" : "circle")
                                    .font(.system(size: 12, weight: .bold))
                                    .widgetAccentable()
                                Text(row.emoji.isEmpty ? row.title : "\(row.emoji) \(row.title)")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                if let time = row.time {
                                    Text(time, format: .dateTime.hour().minute())
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        default:
            system
        }
    }

    private var maxRows: Int {
        switch family {
        case .systemLarge: 11
        case .systemMedium: 4
        default: 4
        }
    }

    private var system: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 5 : 6) {
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.day, format: .dateTime.weekday(.wide))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .textCase(.uppercase)
                    Text("Việc hôm nay").font(.system(.headline, design: .rounded)).lineLimit(1)
                }
                Spacer(minLength: 4)
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                    Circle().trim(from: 0, to: entry.progress)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(entry.done)/\(entry.total)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                }
                .frame(width: 30, height: 30)
            }

            if entry.rows.isEmpty {
                Spacer()
                Label("Chưa có việc cho hôm nay", systemImage: "sun.max")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else if entry.open.isEmpty {
                Spacer()
                Label("Xong hết rồi!", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                Spacer()
            }

            if !entry.open.isEmpty {
                ForEach(entry.ordered.prefix(maxRows)) { row in
                    toggleButton(row) { line(row) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func line(_ row: TodayRow) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: row.isDone ? "checkmark.circle.fill" : (row.kind == .routine ? "circle.dashed" : "circle"))
                .foregroundStyle(row.isDone ? .green : (row.isOverdue ? .red : .secondary))
            if !row.emoji.isEmpty { Text(row.emoji).font(.caption) }
            Text(row.title)
                .strikethrough(row.isDone)
                .foregroundStyle(row.isDone ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if family != .systemSmall, row.streak > 1, !row.isDone {
                Text("🔥\(row.streak)").font(.caption2.monospacedDigit()).foregroundStyle(.orange)
            }
            if let time = row.time {
                Text(time, format: .dateTime.hour().minute())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(row.isOverdue ? .red : .secondary)
            }
        }
        .font(.system(.subheadline, design: .rounded))
    }

    @ViewBuilder
    private func toggleButton<Label: View>(_ row: TodayRow, @ViewBuilder label: () -> Label) -> some View {
        switch row.kind {
        case .routine:
            Button(intent: ToggleRoutineIntent(routineID: row.refID, day: entry.day), label: label).buttonStyle(.plain)
        case .task:
            Button(intent: ToggleChecklistItemIntent(itemID: row.refID), label: label).buttonStyle(.plain)
        }
    }
}
