import SwiftData
import SwiftUI

/// The selected day's to-dos: routines plus the checklist items `DayPlan` assigns to that day. Tasks live
/// in the Notes tab's lists; this card is only a per-day view of them.
struct DayTasksCard: View {
    let day: Date

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Routine.sortIndex), SortDescriptor(\Routine.createdAt)]) private var routines: [Routine]
    @Query private var logs: [RoutineLog]
    @Query private var items: [ChecklistItem]

    @State private var newText = ""
    @State private var withTime = false
    @State private var time = Date().addingTimeInterval(3600)
    @State private var editingRoutine: RoutineDraft?
    @State private var showRoutines = false
    @State private var dueItem: ChecklistItem?
    @FocusState private var addFocused: Bool

    private var plan: DayPlan {
        _ = logs.count // observe routine completions
        return DayPlan.make(day: day, routines: routines, items: items.filter(DayPlan.isListed))
    }

    var body: some View {
        let plan = plan
        VStack(alignment: .leading, spacing: 12) {
            header(plan)

            if plan.total > 0 {
                ProgressView(value: plan.progress)
                    .tint(plan.done == plan.total ? .green : .accentColor)
            }

            if !plan.routines.isEmpty {
                section("Hằng ngày", symbol: "repeat")
                ForEach(plan.routines) { routine in
                    RoutineRow(routine: routine, day: plan.day, disabled: plan.isFuture) {
                        withAnimation(.snappy) { routine.toggle(on: plan.day, in: context) }
                        saved()
                    } onEdit: {
                        editingRoutine = RoutineDraft(routine)
                    }
                }
            }

            if !plan.tasks.isEmpty || !plan.routines.isEmpty {
                section(plan.isToday ? "Việc hôm nay" : "Việc trong ngày", symbol: "checklist")
            }
            ForEach(plan.tasks) { item in
                DayTaskRow(item: item, day: plan.day, actions: actions(for: item))
            }
            addField(plan)

            if plan.total == 0 && routines.isEmpty {
                Button {
                    editingRoutine = RoutineDraft()
                } label: {
                    Label("Thêm việc hằng ngày (uống nước, tập thể dục…) để theo dõi mỗi ngày", systemImage: "repeat")
                        .font(.footnote)
                }
                .buttonStyle(.borderless)
            }
        }
        .sheet(item: $editingRoutine) { RoutineEditorView(draft: $0) }
        .sheet(isPresented: $showRoutines) { NavigationStack { RoutinesView() } }
        .sheet(item: $dueItem) { item in DueDateSheet(item: item, onSave: saved) }
    }

    private func header(_ plan: DayPlan) -> some View {
        HStack(spacing: 10) {
            Label(plan.isToday ? "Việc cần làm" : "Việc ngày \(plan.day.formatted(.dateTime.day().month()))",
                  systemImage: "checkmark.circle")
                .font(.headline)
            Spacer()
            if plan.total > 0 {
                Text("\(plan.done)/\(plan.total)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(plan.done == plan.total ? .green : .secondary)
            }
            Menu {
                Button("Việc hằng ngày mới", systemImage: "repeat") { editingRoutine = RoutineDraft() }
                Button("Quản lý việc hằng ngày", systemImage: "list.bullet.rectangle") { showRoutines = true }
                Button("Danh sách việc mới", systemImage: "square.and.pencil") { model.createNote(in: context, checklist: true) }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title3)
            }
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
        }
    }

    private func section(_ title: LocalizedStringKey, symbol: String, tint: Color = .secondary) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(tint)
    }

    private func addField(_ plan: DayPlan) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            TextField(plan.isToday ? "Thêm việc cho hôm nay…" : "Thêm việc cho ngày này…", text: $newText)
                .textFieldStyle(.plain)
                .focused($addFocused)
                .submitLabel(.done)
                .onSubmit {
                    addTask()
                    addFocused = true
                }
            if withTime {
                DatePicker("Giờ", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .fixedSize()
            }
            Button {
                withAnimation(.snappy) { withTime.toggle() }
            } label: {
                Image(systemName: withTime ? "clock.fill" : "clock")
                    .foregroundStyle(withTime ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(withTime ? "Bỏ giờ" : "Đặt giờ")
        }
        .padding(.vertical, 4)
        // Leaving the field any way (keyboard "Xong", tapping elsewhere) keeps what was typed.
        .onChange(of: addFocused) { was, _ in if was { addTask() } }
    }

    private func addTask() {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let note = context.taskInbox()
        // Without a time, a task added for today stays undated: it shows today and carries over until done.
        let due: Date?
        if withTime {
            let t = Calendar.current.dateComponents([.hour, .minute], from: time)
            due = Calendar.current.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: day) ?? day
        } else {
            due = Calendar.current.isDateInToday(day) ? nil : day
        }
        let item = note.addItem(text, dueDate: due, isAllDay: !withTime && due != nil)
        if withTime, let due, due > Date() {
            NotificationService.shared.schedule(id: item.id, noteID: note.id, title: text,
                                                body: String(localized: "Việc cần làm"), at: due)
        }
        newText = ""
        saved()
    }

    private func actions(for item: ChecklistItem) -> DayTaskRow.Actions {
        DayTaskRow.Actions(
            toggle: {
                withAnimation(.snappy) { item.toggle() }
                saved()
            },
            moveToToday: DayPlan.daysCarried(item, to: Date()) == 0 ? nil : {
                withAnimation(.snappy) { item.schedule(on: Date()) }
                saved()
            },
            moveToTomorrow: {
                let base = max(Calendar.current.startOfDay(for: Date()), item.dueDate ?? day)
                withAnimation(.snappy) { item.schedule(on: Calendar.current.date(byAdding: .day, value: 1, to: base)!) }
                saved()
            },
            setDue: { dueItem = item },
            open: item.note.map { note in { model.open(note) } },
            delete: {
                NotificationService.shared.cancel(id: item.id)
                item.note?.touch()
                withAnimation(.snappy) { context.delete(item) }
                saved()
            }
        )
    }

    private func saved() {
        model.scheduleWidgetReload(context: context, delay: .zero)
        RoutineReminders.reschedule(context: context)
    }
}

// MARK: - Rows

struct RoutineRow: View {
    let routine: Routine
    let day: Date
    var disabled = false
    var onToggle: () -> Void
    var onEdit: () -> Void

    var body: some View {
        let done = routine.isDone(on: day)
        let time = routine.time(on: day)
        let late = !done && Calendar.current.isDateInToday(day) && (time.map { $0 < Date() } ?? false)
        HStack(spacing: 10) {
            Button(action: onToggle) { CheckGlyph(isDone: done, tint: .green) }
                .buttonStyle(.plain)
                .disabled(disabled)
            if !routine.emoji.isEmpty { Text(routine.emoji) }
            VStack(alignment: .leading, spacing: 1) {
                Text(routine.title)
                    .strikethrough(done)
                    .foregroundStyle(done ? .secondary : .primary)
                HStack(spacing: 6) {
                    if let time {
                        Text(time, format: .dateTime.hour().minute())
                            .foregroundStyle(late ? .red : .secondary)
                    }
                    if routine.weekdayMask != Routine.everyDay { Text(routine.repeatLabel) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            let streak = routine.streak()
            if streak > 1 {
                Text("🔥 \(streak)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.orange)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Sửa", systemImage: "pencil", action: onEdit)
        }
    }
}

struct DayTaskRow: View {
    struct Actions {
        var toggle: () -> Void
        var moveToToday: (() -> Void)?
        var moveToTomorrow: () -> Void
        var setDue: () -> Void
        var open: (() -> Void)?
        var delete: () -> Void
    }

    let item: ChecklistItem
    let day: Date
    let actions: Actions

    var body: some View {
        HStack(spacing: 10) {
            Button(action: actions.toggle) { CheckGlyph(isDone: item.isDone) }
                .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.text)
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
                let caption = captionParts
                if !caption.isEmpty {
                    Text(caption.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(carried > 0 || item.isOverdue ? .red : .secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let moveToToday = actions.moveToToday, !item.isDone {
                Button(action: moveToToday) {
                    Image(systemName: "sun.max")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Làm hôm nay")
            }
            menu
        }
        .contentShape(Rectangle())
        .contextMenu { menuItems }
    }

    private var carried: Int { DayPlan.daysCarried(item, to: day) }

    private var captionParts: [String] {
        var parts: [String] = []
        switch carried {
        case 0:
            if let due = item.dueDate, !item.isAllDay, Calendar.current.isDate(due, inSameDayAs: day) {
                parts.append(due.formatted(.dateTime.hour().minute()))
            } else if let due = item.dueDate, !Calendar.current.isDate(due, inSameDayAs: day), let label = item.dueLabel {
                parts.append(label)
            }
        case 1: parts.append(String(localized: "Từ hôm qua"))
        default: parts.append(String(localized: "Quá hạn \(carried) ngày"))
        }
        if item.isDone, let done = item.completedAt, !Calendar.current.isDate(done, inSameDayAs: item.dueDate ?? done) {
            parts.append(String(localized: "xong \(done.formatted(.dateTime.day().month()))"))
        }
        if let note = item.note, !note.isTaskInbox { parts.append(note.displayTitle) }
        return parts
    }

    private var menu: some View {
        Menu { menuItems } label: {
            Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 24, height: 24)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    @ViewBuilder
    private var menuItems: some View {
        if let moveToToday = actions.moveToToday, !item.isDone {
            Button("Làm hôm nay", systemImage: "sun.max", action: moveToToday)
        }
        if !item.isDone {
            Button("Dời sang ngày mai", systemImage: "arrow.turn.up.right", action: actions.moveToTomorrow)
        }
        Button("Đặt ngày giờ", systemImage: "calendar.badge.clock", action: actions.setDue)
        if let open = actions.open {
            Button("Mở ghi chú", systemImage: "note.text", action: open)
        }
        Divider()
        Button("Xoá", systemImage: "trash", role: .destructive, action: actions.delete)
    }
}

// MARK: - Routines

struct RoutinesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Query(sort: [SortDescriptor(\Routine.sortIndex), SortDescriptor(\Routine.createdAt)]) private var routines: [Routine]
    @Query private var logs: [RoutineLog]
    @State private var editing: RoutineDraft?

    var body: some View {
        List {
            if routines.isEmpty {
                ContentUnavailableView(
                    "Chưa có việc hằng ngày",
                    systemImage: "repeat",
                    description: Text("Thêm những việc bạn muốn làm đều đặn — mỗi ngày được đánh dấu riêng và hiện trên widget.")
                )
            }
            ForEach(routines) { routine in
                Button { editing = RoutineDraft(routine) } label: { row(routine) }
                    .buttonStyle(.plain)
            }
            .onDelete { offsets in
                offsets.map { routines[$0] }.forEach(context.delete)
                changed()
            }
            .onMove { from, to in
                var ordered = routines
                ordered.move(fromOffsets: from, toOffset: to)
                for (i, r) in ordered.enumerated() { r.sortIndex = i }
                changed()
            }
        }
        .navigationTitle("Việc hằng ngày")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                Button("Thêm", systemImage: "plus") { editing = RoutineDraft(sortIndex: routines.count) }
            }
        }
        .sheet(item: $editing) { RoutineEditorView(draft: $0) }
    }

    private func row(_ routine: Routine) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let week = (0..<7).reversed().map { cal.date(byAdding: .day, value: -$0, to: today)! }
        _ = logs.count
        return HStack(spacing: 12) {
            Text(routine.emoji.isEmpty ? "🔁" : routine.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(routine.title).font(.body.weight(.medium))
                Text([routine.timeLabel, routine.repeatLabel, routine.isPaused ? String(localized: "Tạm dừng") : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Last 7 days: filled = done, ring = missed, faint = not scheduled.
                HStack(spacing: 4) {
                    ForEach(week, id: \.self) { d in
                        let done = routine.isDone(on: d)
                        let scheduled = routine.isScheduled(on: d)
                        Circle()
                            .strokeBorder(done ? Color.clear : (scheduled ? Color.secondary : Color.secondary.opacity(0.25)), lineWidth: 1.2)
                            .background(Circle().fill(done ? Color.green : .clear))
                            .frame(width: 9, height: 9)
                    }
                }
            }
            Spacer()
            let streak = routine.streak()
            if streak > 0 {
                VStack(spacing: 0) {
                    Text("🔥 \(streak)").font(.subheadline.weight(.bold).monospacedDigit())
                    Text("ngày").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .opacity(routine.isPaused ? 0.5 : 1)
        .contentShape(Rectangle())
    }

    private func changed() {
        model.scheduleWidgetReload(context: context, delay: .zero)
        RoutineReminders.reschedule(context: context)
    }
}

/// Editable copy of a routine, so cancelling leaves the original untouched.
struct RoutineDraft: Identifiable {
    let id = UUID()
    var routine: Routine?
    var title = ""
    var emoji = ""
    var hasTime = false
    var time = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
    var weekdayMask = Routine.everyDay
    var remind = true
    var isPaused = false
    var sortIndex = 0

    init(sortIndex: Int = 0) { self.sortIndex = sortIndex }

    init(_ routine: Routine) {
        self.routine = routine
        title = routine.title
        emoji = routine.emoji
        hasTime = routine.hasTime
        if let t = routine.time(on: Date()) { time = t }
        weekdayMask = routine.weekdayMask
        remind = routine.remind
        isPaused = routine.isPaused
        sortIndex = routine.sortIndex
    }
}

struct RoutineEditorView: View {
    @State var draft: RoutineDraft
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var showEmoji = false
    @State private var confirmDelete = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Button {
                            showEmoji = true
                        } label: {
                            Text(draft.emoji.isEmpty ? "🔁" : draft.emoji).font(.title)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showEmoji) { EmojiPicker(selection: $draft.emoji) }
                        TextField("Ví dụ: Uống 2 lít nước", text: $draft.title)
                            .focused($titleFocused)
                            .submitLabel(.done)
                    }
                }

                Section("Lặp lại") {
                    Picker("Lặp lại", selection: $draft.weekdayMask) {
                        Text("Mỗi ngày").tag(Routine.everyDay)
                        Text("Thứ 2 – Thứ 6").tag(Routine.weekdays)
                        Text("Cuối tuần").tag(Routine.weekend)
                        if ![Routine.everyDay, Routine.weekdays, Routine.weekend].contains(draft.weekdayMask) {
                            Text("Tuỳ chọn").tag(draft.weekdayMask)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    HStack(spacing: 6) {
                        ForEach(Routine.orderedWeekdays, id: \.self) { weekday in
                            let on = draft.weekdayMask & (1 << (weekday - 1)) != 0
                            Button(Routine.shortName(weekday)) {
                                let toggled = draft.weekdayMask ^ (1 << (weekday - 1))
                                if toggled != 0 { draft.weekdayMask = toggled }
                            }
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                            .foregroundStyle(on ? .white : .primary)
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Toggle("Đặt giờ", isOn: $draft.hasTime.animation())
                    if draft.hasTime {
                        DatePicker("Giờ", selection: $draft.time, displayedComponents: .hourAndMinute)
                        Toggle("Nhắc tôi đúng giờ", isOn: $draft.remind)
                    }
                } footer: {
                    Text("Việc có giờ được sắp theo thứ tự trong ngày. Nhắc nhở tự bỏ qua những ngày bạn đã xong.")
                }

                if draft.routine != nil {
                    Section {
                        Toggle("Tạm dừng", isOn: $draft.isPaused)
                        Button("Xoá việc hằng ngày", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Tạm dừng giữ lại lịch sử và chuỗi ngày nhưng không hiện trong danh sách.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(draft.routine == nil ? "Việc hằng ngày mới" : "Sửa việc hằng ngày")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu", action: save)
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Xoá việc này và toàn bộ lịch sử?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Xoá", role: .destructive) {
                    if let routine = draft.routine { context.delete(routine) }
                    finish()
                }
            }
            .onAppear { if draft.routine == nil { titleFocused = true } }
        }
    }

    private func save() {
        let routine = draft.routine ?? {
            let r = Routine(title: "", sortIndex: draft.sortIndex)
            context.insert(r)
            return r
        }()
        routine.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        routine.emoji = draft.emoji
        let t = Calendar.current.dateComponents([.hour, .minute], from: draft.time)
        routine.minuteOfDay = draft.hasTime ? (t.hour ?? 0) * 60 + (t.minute ?? 0) : -1
        routine.weekdayMask = draft.weekdayMask
        routine.remind = draft.remind
        routine.isPaused = draft.isPaused
        finish()
        if draft.hasTime && draft.remind {
            Task {
                await NotificationService.shared.requestAuthorization()
                RoutineReminders.reschedule(context: context)
            }
        }
    }

    private func finish() {
        try? context.save()
        RoutineReminders.reschedule(context: context)
        model.scheduleWidgetReload(context: context, delay: .zero)
        dismiss()
    }
}
