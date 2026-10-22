import EventKit
import SwiftData
import SwiftUI

/// Observable wrapper that refreshes when the system calendar database changes.
@MainActor
@Observable
final class CalendarModel {
    static let shared = CalendarModel()

    var status: EKAuthorizationStatus = CalendarStore.authorizationStatus
    var revision = 0
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: CalendarStore.eventStore, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.revision += 1
                DataStore.reloadWidgets()
            }
        }
    }

    var hasAccess: Bool { status == .fullAccess }

    func requestAccess() async {
        _ = await CalendarStore.requestAccess()
        status = CalendarStore.authorizationStatus
        revision += 1
        DataStore.reloadWidgets()
    }

    func events(on day: Date) -> [AgendaEvent] {
        _ = revision
        return CalendarStore.events(on: day)
    }

    func busyDays(month: Date) -> Set<Date> {
        _ = revision
        return CalendarStore.busyDays(inMonthOf: month, calendar: CalendarPrefs.calendar)
    }
}

struct CalendarScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Note> { !$0.isTrashed }) private var notes: [Note]
    @Query(filter: #Predicate<ChecklistItem> { $0.dueDate != nil }) private var dueItems: [ChecklistItem]
    @State private var calendarModel = CalendarModel.shared
    @State private var month = Date()
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var editingEvent: EventDraft?
    @AppStorage(AppConstants.Key.weekStartsMonday, store: .shared) private var weekStartsMonday = true
    @AppStorage(AppConstants.Key.todayMarker, store: .shared) private var marker: TodayMarker = .ring

    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = weekStartsMonday ? 2 : 1
        return c
    }

    var body: some View {
        List {
            Section {
                monthHeader
                monthGrid
            }
            .listRowSeparator(.hidden)

            if !calendarModel.hasAccess {
                Section {
                    CalendarAccessCard(model: calendarModel)
                }
            }

            Section(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
                DayAgenda(day: selectedDay, calendarModel: calendarModel, onEdit: { editingEvent = $0 })
            }
        }
        .navigationTitle("Lịch")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Hôm nay", systemImage: "calendar.circle") {
                    withAnimation {
                        month = Date()
                        selectedDay = Calendar.current.startOfDay(for: Date())
                    }
                }
                Button("Sự kiện mới", systemImage: "plus") {
                    editingEvent = EventDraft(day: selectedDay)
                }
                .disabled(!calendarModel.hasAccess)
            }
        }
        .sheet(item: $editingEvent) { draft in
            EventEditorView(draft: draft)
        }
    }

    private var monthHeader: some View {
        HStack {
            Text(MonthGrid(month: month, calendar: calendar).title.capitalized)
                .font(.title2.bold())
            Spacer()
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.borderless)
        .font(.title3)
    }

    private var monthGrid: some View {
        let grid = MonthGrid(month: month, calendar: calendar)
        let busy = calendarModel.busyDays(month: month)
        let noteDays = Set(notes.compactMap { $0.dailyDate.map { calendar.startOfDay(for: $0) } })
        let taskDays = Set(dueItems.compactMap { item in item.dueDate.map { calendar.startOfDay(for: $0) } })
        return Grid(horizontalSpacing: 4, verticalSpacing: 6) {
            GridRow {
                ForEach(Array(grid.weekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                GridRow {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            let start = calendar.startOfDay(for: day)
                            DayCell(
                                day: day, isSelected: start == selectedDay, marker: marker,
                                hasEvent: busy.contains(start), hasNote: noteDays.contains(start),
                                hasTask: taskDays.contains(start)
                            )
                            .onTapGesture { withAnimation(.snappy) { selectedDay = start } }
                        } else {
                            Color.clear.frame(height: 44)
                        }
                    }
                }
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.width < -40 { shiftMonth(1) } else if value.translation.width > 40 { shiftMonth(-1) }
        })
    }

    private func shiftMonth(_ delta: Int) {
        withAnimation(.snappy) {
            month = calendar.date(byAdding: .month, value: delta, to: month) ?? month
        }
    }
}

private struct DayCell: View {
    let day: Date
    let isSelected: Bool
    let marker: TodayMarker
    let hasEvent: Bool
    let hasNote: Bool
    let hasTask: Bool

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        VStack(spacing: 3) {
            ZStack {
                if isSelected {
                    Circle().fill(Color.accentColor.opacity(0.18))
                }
                if isToday {
                    switch marker {
                    case .ring: Circle().stroke(Color.accentColor, lineWidth: 2)
                    case .square: RoundedRectangle(cornerRadius: 8).fill(Color.accentColor)
                    case .dot: EmptyView()
                    }
                }
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.body.weight(isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isToday && marker == .square ? .white : (isToday ? Color.accentColor : .primary))
            }
            .frame(width: 34, height: 34)
            HStack(spacing: 2) {
                if isToday && marker == .dot { dot(.accentColor) }
                if hasEvent { dot(.blue) }
                if hasNote { dot(.orange) }
                if hasTask { dot(.green) }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func dot(_ c: Color) -> some View {
        Circle().fill(c).frame(width: 5, height: 5)
    }
}

struct CalendarAccessCard: View {
    let model: CalendarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Kết nối Lịch", systemImage: "calendar.badge.plus").font(.headline)
            Text("Cho phép DailyNote đọc Lịch Apple (bao gồm Google Calendar đã thêm trong Cài đặt) để hiển thị sự kiện cạnh ghi chú, trên widget và hình nền Lock Screen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if model.status == .denied || model.status == .restricted {
                Text("Quyền truy cập đã bị từ chối. Mở Cài đặt › Quyền riêng tư › Lịch để bật lại.")
                    .font(.footnote).foregroundStyle(.red)
            } else {
                Button("Cho phép truy cập Lịch") { Task { await model.requestAccess() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Events, due tasks and notes for a given day.
struct DayAgenda: View {
    let day: Date
    let calendarModel: CalendarModel
    var onEdit: (EventDraft) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ChecklistItem> { $0.dueDate != nil }, sort: \ChecklistItem.dueDate) private var dueItems: [ChecklistItem]
    @Query(filter: #Predicate<Note> { !$0.isTrashed }, sort: \Note.updatedAt, order: .reverse) private var notes: [Note]

    var body: some View {
        let events = calendarModel.events(on: day)
        let tasks = dueItems.filter { item in
            item.note?.isTrashed == false && item.dueDate.map { Calendar.current.isDate($0, inSameDayAs: day) } == true
        }
        let dayNotes = notes.filter { note in
            if let d = note.dailyDate { return Calendar.current.isDate(d, inSameDayAs: day) }
            return Calendar.current.isDate(note.createdAt, inSameDayAs: day)
        }

        if events.isEmpty && tasks.isEmpty && dayNotes.isEmpty {
            Text("Không có gì trong ngày này.")
                .foregroundStyle(.secondary)
        }
        ForEach(events) { event in
            Button {
                if let ek = CalendarStore.ekEvent(id: event.id) { onEdit(EventDraft(event: ek)) }
            } label: {
                EventRow(event: event)
            }
            .buttonStyle(.plain)
            .swipeActions {
                Button("Xoá", systemImage: "trash", role: .destructive) {
                    if let ek = CalendarStore.ekEvent(id: event.id) {
                        try? CalendarStore.eventStore.remove(ek, span: .thisEvent)
                    }
                }
            }
        }
        ForEach(tasks) { item in
            HStack(spacing: 10) {
                Button {
                    withAnimation { item.toggle() }
                    model.scheduleWidgetReload(context: context, delay: .zero)
                } label: { CheckGlyph(isDone: item.isDone) }
                    .buttonStyle(.plain)
                VStack(alignment: .leading) {
                    Text(item.text).strikethrough(item.isDone)
                    if let note = item.note {
                        Text(note.displayTitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let due = item.dueDate {
                    Text(due.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        ForEach(dayNotes) { note in
            Button {
                model.open(note)
            } label: {
                Label {
                    VStack(alignment: .leading) {
                        Text(note.displayTitle)
                        if !note.preview.isEmpty {
                            Text(note.preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                } icon: {
                    Text(note.emoji.isEmpty ? "📝" : note.emoji)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct EventRow: View {
    let event: AgendaEvent

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(event.isAllDay ? String(localized: "Cả ngày")
                         : "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                    if let loc = event.location, !loc.isEmpty {
                        Label(loc, systemImage: "mappin").lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let notes = event.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Event editor

enum RepeatRule: String, CaseIterable, Identifiable {
    case none, daily, weekdays, weekly, monthly, yearly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "Không lặp"
        case .daily: "Hằng ngày"
        case .weekdays: "Ngày trong tuần"
        case .weekly: "Hằng tuần"
        case .monthly: "Hằng tháng"
        case .yearly: "Hằng năm"
        }
    }

    var rule: EKRecurrenceRule? {
        switch self {
        case .none: nil
        case .daily: EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekdays: EKRecurrenceRule(
            recurrenceWith: .weekly, interval: 1,
            daysOfTheWeek: [.monday, .tuesday, .wednesday, .thursday, .friday].map { EKRecurrenceDayOfWeek($0) },
            daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
        case .weekly: EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .monthly: EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .yearly: EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        }
    }

    init(_ rule: EKRecurrenceRule?) {
        guard let rule else { self = .none; return }
        switch rule.frequency {
        case .daily: self = .daily
        case .weekly: self = (rule.daysOfTheWeek?.count ?? 0) == 5 ? .weekdays : .weekly
        case .monthly: self = .monthly
        case .yearly: self = .yearly
        @unknown default: self = .none
        }
    }
}

struct EventDraft: Identifiable {
    let id = UUID()
    var eventID: String?
    var title = ""
    var start: Date
    var end: Date
    var isAllDay = false
    var repeatRule: RepeatRule = .none
    var alertMinutes: Int = UserDefaults.shared.object(forKey: AppConstants.Key.defaultAlertMinutes) as? Int ?? 15
    var location = ""
    var notes = ""
    var calendarID: String?

    init(day: Date) {
        let cal = Calendar.current
        let now = Date()
        let hour = cal.isDateInToday(day) ? cal.component(.hour, from: now) + 1 : 9
        start = cal.date(bySettingHour: min(hour, 23), minute: 0, second: 0, of: day) ?? day
        end = start.addingTimeInterval(3600)
        calendarID = CalendarStore.eventStore.defaultCalendarForNewEvents?.calendarIdentifier
    }

    init(event: EKEvent) {
        eventID = event.eventIdentifier
        title = event.title ?? ""
        start = event.startDate
        end = event.endDate
        isAllDay = event.isAllDay
        repeatRule = RepeatRule(event.recurrenceRules?.first)
        alertMinutes = event.alarms?.first.map { Int(-$0.relativeOffset / 60) } ?? -1
        location = event.location ?? ""
        notes = event.notes ?? ""
        calendarID = event.calendar?.calendarIdentifier
    }
}

struct EventEditorView: View {
    @State var draft: EventDraft
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    private var calendars: [EKCalendar] {
        CalendarStore.eventStore.calendars(for: .event).filter(\.allowsContentModifications)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tiêu đề", text: $draft.title)
                    TextField("Địa điểm / phòng học", text: $draft.location)
                }
                Section {
                    Toggle("Cả ngày", isOn: $draft.isAllDay)
                    DatePicker("Bắt đầu", selection: $draft.start,
                               displayedComponents: draft.isAllDay ? .date : [.date, .hourAndMinute])
                    DatePicker("Kết thúc", selection: $draft.end, in: draft.start...,
                               displayedComponents: draft.isAllDay ? .date : [.date, .hourAndMinute])
                    Picker("Lặp lại", selection: $draft.repeatRule) {
                        ForEach(RepeatRule.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Báo trước", selection: $draft.alertMinutes) {
                        Text("Không").tag(-1)
                        Text("Đúng giờ").tag(0)
                        Text("5 phút").tag(5)
                        Text("15 phút").tag(15)
                        Text("30 phút").tag(30)
                        Text("1 giờ").tag(60)
                        Text("1 ngày").tag(1440)
                    }
                    Picker("Lịch", selection: $draft.calendarID) {
                        ForEach(calendars, id: \.calendarIdentifier) { cal in
                            Label {
                                Text(cal.title)
                            } icon: {
                                Image(systemName: "circle.fill").foregroundStyle(Color(cgColor: cal.cgColor))
                            }
                            .tag(Optional(cal.calendarIdentifier))
                        }
                    }
                }
                Section("Ghi chú") {
                    TextField("Ghi chú cho sự kiện", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                if draft.eventID != nil {
                    Section {
                        Button("Xoá sự kiện", role: .destructive) { delete() }
                    }
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(draft.eventID == nil ? "Sự kiện mới" : "Sửa sự kiện")
            .inlineNavigationTitle()
            .onChange(of: draft.start) { old, new in
                draft.end = draft.end.addingTimeInterval(new.timeIntervalSince(old))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { save() }
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    private func save() {
        let store = CalendarStore.eventStore
        let event = draft.eventID.flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = max(draft.end, draft.start.addingTimeInterval(draft.isAllDay ? 0 : 300))
        event.isAllDay = draft.isAllDay
        event.location = draft.location.isEmpty ? nil : draft.location
        event.notes = draft.notes.isEmpty ? nil : draft.notes
        event.calendar = draft.calendarID.flatMap { store.calendar(withIdentifier: $0) } ?? store.defaultCalendarForNewEvents
        event.recurrenceRules?.forEach { event.removeRecurrenceRule($0) }
        if let rule = draft.repeatRule.rule { event.addRecurrenceRule(rule) }
        event.alarms?.forEach { event.removeAlarm($0) }
        if draft.alertMinutes >= 0 {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-draft.alertMinutes * 60)))
        }
        do {
            try store.save(event, span: draft.repeatRule == .none ? .thisEvent : .futureEvents, commit: true)
            DataStore.reloadWidgets()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete() {
        guard let id = draft.eventID, let event = CalendarStore.eventStore.event(withIdentifier: id) else { return }
        try? CalendarStore.eventStore.remove(event, span: .thisEvent, commit: true)
        DataStore.reloadWidgets()
        dismiss()
    }
}
