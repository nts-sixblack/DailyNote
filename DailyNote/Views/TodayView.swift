import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var dailyNote: Note?
    @State private var calendarModel = CalendarModel.shared
    @State private var editingEvent: EventDraft?
    @State private var viewedOtherDay = false
    @Query private var items: [ChecklistItem]
    @Query private var routines: [Routine]
    @Query private var routineLogs: [RoutineLog]
    @Query(filter: #Predicate<Note> { !$0.isTrashed && $0.showOnLockScreen }, sort: \Note.updatedAt, order: .reverse)
    private var lockNotes: [Note]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                greeting
                weekStrip

                card("Lịch hôm nay", symbol: "calendar") {
                    if calendarModel.hasAccess {
                        let events = calendarModel.events(on: day)
                        if events.isEmpty {
                            Text("Không có sự kiện.").foregroundStyle(.secondary)
                        }
                        ForEach(events) { event in
                            Button {
                                if let ek = CalendarStore.ekEvent(id: event.id) { editingEvent = EventDraft(event: ek) }
                            } label: { EventRow(event: event) }
                                .buttonStyle(.plain)
                        }
                    } else {
                        CalendarAccessCard(model: calendarModel)
                    }
                } trailing: {
                    if calendarModel.hasAccess {
                        Button("Thêm", systemImage: "plus") { editingEvent = EventDraft(day: day) }
                            .labelStyle(.iconOnly)
                    }
                }

                DayTasksCard(day: day)
                    .padding(16)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))

                if !lockNotes.isEmpty {
                    card("Đang hiện trên Lock Screen", symbol: "lock.iphone") {
                        ForEach(lockNotes) { note in
                            Button { model.open(note) } label: {
                                HStack {
                                    Text(note.emoji.isEmpty ? "📝" : note.emoji)
                                    VStack(alignment: .leading) {
                                        Text(note.displayTitle).font(.body.weight(.medium))
                                        if !note.preview.isEmpty {
                                            Text(note.preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } trailing: { EmptyView() }
                }

                card("Nhật ký", symbol: "book") {
                    if let dailyNote {
                        NoteEditorView(note: dailyNote, compact: true)
                            .id(dailyNote.id)
                    }
                } trailing: {
                    if let dailyNote {
                        Button("Mở", systemImage: "arrow.up.left.and.arrow.down.right") {
                            if dailyNote.modelContext == nil { context.insert(dailyNote) }
                            model.open(dailyNote)
                        }
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Hôm nay")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Ghi chú mới", systemImage: "square.and.pencil") { model.createNote(in: context) }
            }
        }
        .onAppear {
            // Coming back on a new day jumps to it rather than showing yesterday's list.
            if day < Calendar.current.startOfDay(for: Date()) && !viewedOtherDay { day = Calendar.current.startOfDay(for: Date()) }
            loadDaily()
        }
        .onChange(of: day) { loadDaily() }
        .sheet(item: $editingEvent) { EventEditorView(draft: $0) }
    }

    /// Share of the day's routines and tasks that are done, for the week strip.
    private func progress(on day: Date) -> Double? {
        _ = routineLogs.count
        let plan = DayPlan.make(day: day, routines: routines, items: items.filter(DayPlan.isListed))
        return plan.total == 0 ? nil : plan.progress
    }

    private var greeting: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let text = hour < 11 ? String(localized: "Chào buổi sáng") : hour < 18 ? String(localized: "Chào buổi chiều") : String(localized: "Chào buổi tối")
        return VStack(alignment: .leading, spacing: 2) {
            Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(text).font(.largeTitle.bold())
        }
    }

    private var weekStrip: some View {
        let cal = CalendarPrefs.calendar
        let week = cal.dateInterval(of: .weekOfYear, for: day)!
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: week.start) }
        return HStack(spacing: 6) {
            Button { day = cal.date(byAdding: .day, value: -7, to: day)! } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            ForEach(days, id: \.self) { d in
                let selected = cal.isDate(d, inSameDayAs: day)
                VStack(spacing: 4) {
                    Text(d.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(d.formatted(.dateTime.day()))
                        .font(.body.weight(selected ? .bold : .regular))
                        .foregroundStyle(selected ? .white : (cal.isDateInToday(d) ? Color.accentColor : .primary))
                        .frame(width: 34, height: 34)
                        .background(selected ? Color.accentColor : .clear, in: Circle())
                    let fraction = progress(on: d)
                    Capsule()
                        .fill(Color.secondary.opacity(fraction == nil ? 0 : 0.2))
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule()
                                    .fill(fraction == 1 ? Color.green : Color.accentColor)
                                    .frame(width: geo.size.width * (fraction ?? 0))
                            }
                        }
                        .frame(width: 20, height: 3)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.snappy) { day = cal.startOfDay(for: d) }
                    viewedOtherDay = !cal.isDateInToday(d)
                }
            }
            Button { day = cal.date(byAdding: .day, value: 7, to: day)! } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
        }
    }

    private func card<Content: View, Trailing: View>(
        _ title: LocalizedStringKey, symbol: String,
        @ViewBuilder content: () -> Content, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: symbol).font(.headline)
                Spacer()
                trailing()
            }
            content()
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
    }

    private func loadDaily() {
        if let existing = context.dailyNote(for: day, create: false) {
            dailyNote = existing
        } else {
            let note = Note()
            note.dailyDate = day
            note.emoji = "📅"
            dailyNote = note
        }
    }
}
