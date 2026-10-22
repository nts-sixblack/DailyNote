import AppIntents
import SwiftUI
import WidgetKit

struct NoteEntry: TimelineEntry {
    let date: Date
    let note: NoteSnapshot?
}

struct NoteProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NoteEntry {
        NoteEntry(date: .now, note: .sample)
    }

    func snapshot(for configuration: SelectNoteIntent, in context: Context) async -> NoteEntry {
        NoteEntry(date: .now, note: WidgetData.note(for: configuration.note) ?? (context.isPreview ? .sample : nil))
    }

    func timeline(for configuration: SelectNoteIntent, in context: Context) async -> Timeline<NoteEntry> {
        let entry = NoteEntry(date: .now, note: WidgetData.note(for: configuration.note))
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60)))
    }
}

struct NoteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: AppConstants.WidgetKind.note, intent: SelectNoteIntent.self, provider: NoteProvider()) { entry in
            NoteWidgetView(entry: entry)
        }
        .configurationDisplayName("Ghi chú")
        .description("Hiện ghi chú bạn chọn — hoặc ghi chú đã gắn Lock Screen — ngay trên màn hình khoá.")
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

struct NoteWidgetView: View {
    let entry: NoteEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        content
            .widgetURL(entry.note.map { DeepLink.note($0.id).url } ?? DeepLink.newNote.url)
            .widgetBackground(family, tint: entry.note?.color == NoteColor.none ? .orange : (entry.note?.color.color ?? .orange))
    }

    @ViewBuilder
    private var content: some View {
        if let note = entry.note {
            switch family {
            case .accessoryInline:
                Text("\(note.emoji.isEmpty ? "📝" : note.emoji) \(note.title)")
            case .accessoryRectangular:
                rectangular(note)
            default:
                system(note)
            }
        } else {
            empty
        }
    }

    private func rectangular(_ note: NoteSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                if !note.emoji.isEmpty { Text(note.emoji).font(.system(size: 12)) }
                Text(note.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .widgetAccentable()
            }
            if !note.body.isEmpty {
                Text(note.body)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(note.openItems.isEmpty ? 3 : 1)
            }
            ForEach(note.openItems.prefix(note.body.isEmpty ? 3 : 2)) { item in
                Button(intent: ToggleChecklistItemIntent(itemID: item.id)) {
                    HStack(spacing: 4) {
                        Image(systemName: "circle").font(.system(size: 10, weight: .bold))
                        Text(item.text).font(.system(size: 12, weight: .medium, design: .rounded)).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func system(_ note: NoteSnapshot) -> some View {
        let tint = note.color == .none ? Color.orange : note.color.color
        let maxItems = family == .systemLarge ? 8 : (family == .systemMedium ? 3 : 2)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if !note.emoji.isEmpty { Text(note.emoji) }
                Text(note.title)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(family == .systemSmall ? 2 : 1)
                Spacer(minLength: 0)
                Image(systemName: "lock.iphone").font(.caption2).foregroundStyle(tint)
            }
            if !note.body.isEmpty {
                Text(note.body)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(family == .systemLarge ? 8 : (note.items.isEmpty ? 5 : 2))
            }
            if !note.items.isEmpty {
                ForEach((note.openItems + note.items.filter(\.isDone)).prefix(maxItems)) { item in
                    Button(intent: ToggleChecklistItemIntent(itemID: item.id)) {
                        HStack(spacing: 6) {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isDone ? tint : .secondary)
                            Text(item.text)
                                .strikethrough(item.isDone)
                                .foregroundStyle(item.isDone ? .secondary : .primary)
                                .lineLimit(1)
                        }
                        .font(.system(.subheadline, design: .rounded))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
            if family != .systemSmall {
                HStack {
                    Text(note.updatedAt, style: .relative).font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Link(destination: DeepLink.newNote.url) {
                        Image(systemName: "square.and.pencil").font(.callout.weight(.semibold)).foregroundStyle(tint)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var empty: some View {
        switch family {
        case .accessoryInline:
            Text("📝 Chạm để ghi chú")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("DailyNote", systemImage: "square.and.pencil").font(.headline).widgetAccentable()
                Text("Chạm để ghi chú").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(spacing: 8) {
                Image(systemName: "square.and.pencil").font(.title).foregroundStyle(.orange)
                Text("Chưa có ghi chú trên Lock Screen").font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
        }
    }
}
