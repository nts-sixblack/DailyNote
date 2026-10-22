import AppIntents
import SwiftUI
import WidgetKit

struct ChecklistEntry: TimelineEntry {
    let date: Date
    let title: String
    let items: [ItemSnapshot]
    let done: Int
    let total: Int
    let noteID: UUID?

    static let sample = ChecklistEntry(
        date: .now, title: "Việc cần làm", items: NoteSnapshot.sample.items, done: 1, total: 3, noteID: nil
    )
}

struct ChecklistProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ChecklistEntry { .sample }

    func snapshot(for configuration: SelectNoteIntent, in context: Context) async -> ChecklistEntry {
        let entry = load(configuration)
        return context.isPreview && entry.items.isEmpty ? .sample : entry
    }

    func timeline(for configuration: SelectNoteIntent, in context: Context) async -> Timeline<ChecklistEntry> {
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        return Timeline(entries: [load(configuration)], policy: .after(min(midnight, .now.addingTimeInterval(30 * 60))))
    }

    private func load(_ configuration: SelectNoteIntent) -> ChecklistEntry {
        let data = WidgetData.tasks(for: configuration.note)
        return ChecklistEntry(date: .now, title: data.title, items: data.items, done: data.done, total: data.total, noteID: data.noteID)
    }
}

struct ChecklistWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: AppConstants.WidgetKind.checklist, intent: SelectNoteIntent.self, provider: ChecklistProvider()) { entry in
            ChecklistWidgetView(entry: entry)
        }
        .configurationDisplayName("Việc cần làm")
        .description("Đánh dấu việc đã xong ngay trên Lock Screen — không cần mở khoá.")
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

struct ChecklistWidgetView: View {
    let entry: ChecklistEntry
    @Environment(\.widgetFamily) private var family

    private var progress: Double { entry.total == 0 ? 0 : Double(entry.done) / Double(entry.total) }
    private var openCount: Int { entry.items.filter { !$0.isDone }.count }

    var body: some View {
        content
            .widgetURL(entry.noteID.map { DeepLink.note($0).url } ?? DeepLink.today.url)
            .widgetBackground(family, tint: .green)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            if let first = entry.items.first(where: { !$0.isDone }) {
                Text("☐ \(first.text)")
            } else {
                Text("✓ Đã xong hết việc")
            }
        case .accessoryCircular:
            Gauge(value: progress) {
                Image(systemName: "checklist")
            } currentValueLabel: {
                Text("\(openCount)").font(.system(.title3, design: .rounded, weight: .bold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                if entry.items.isEmpty {
                    Label("Đã xong hết việc", systemImage: "checkmark.seal").font(.headline).widgetAccentable()
                    Text("Chạm để thêm việc").font(.caption)
                }
                ForEach(entry.items.prefix(3)) { item in
                    Button(intent: ToggleChecklistItemIntent(itemID: item.id)) {
                        HStack(spacing: 4) {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12, weight: .bold))
                                .widgetAccentable()
                            Text(item.text)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .strikethrough(item.isDone)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        default:
            system
        }
    }

    private var system: some View {
        let maxItems = family == .systemLarge ? 10 : (family == .systemMedium ? 4 : 4)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.title).font(.system(.headline, design: .rounded)).lineLimit(1)
                Spacer(minLength: 4)
                Gauge(value: progress) { EmptyView() }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(.green)
                    .scaleEffect(0.45)
                    .frame(width: 24, height: 24)
            }
            if entry.items.isEmpty {
                Spacer()
                Label("Đã xong hết việc", systemImage: "checkmark.seal.fill")
                    .font(.subheadline).foregroundStyle(.green)
                Spacer()
            }
            ForEach(entry.items.prefix(maxItems)) { item in
                Button(intent: ToggleChecklistItemIntent(itemID: item.id)) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isDone ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.text)
                                .strikethrough(item.isDone)
                                .foregroundStyle(item.isDone ? .secondary : .primary)
                                .lineLimit(1)
                            if family != .systemSmall, entry.noteID == nil, !item.noteTitle.isEmpty {
                                Text(item.noteTitle).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        if let due = item.due, family != .systemSmall {
                            Text(due, format: .dateTime.day().month().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(due < .now ? .red : .secondary)
                        }
                    }
                    .font(.system(.subheadline, design: .rounded))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
