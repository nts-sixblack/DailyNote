import SwiftData
import SwiftUI

struct NoteEditorView: View {
    @Bindable var note: Note
    var compact = false

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Folder.sortIndex) private var folders: [Folder]

    @State private var selection: TextSelection?
    @State private var newItemText = ""
    @State private var showPreview = false
    @State private var showReminder = false
    @State private var showEmoji = false
    @State private var showDone = false
    @FocusState private var focus: Field?

    enum Field: Hashable { case title, body, newItem }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !compact { header }
                // Today's journal card lists the day's tasks separately.
                if showsChecklist { checklist }
                bodyEditor
                if !note.tags.isEmpty { tagChips }
                if !compact { footer }
            }
            .padding(.horizontal, compact ? 0 : 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(note.color == .none ? Color.clear : note.color.color.opacity(0.06))
        .inlineNavigationTitle()
        .toolbar { toolbar }
        .onChange(of: note.body) { changed() }
        .onChange(of: focus) { old, _ in
            // Leaving the field any way (keyboard "Xong", tapping elsewhere) keeps what was typed.
            if old == .newItem { commitNewItem() }
        }
        .onChange(of: note.title) { changed() }
        .onAppear {
            if model.focusNewNote {
                model.focusNewNote = false
                focus = showsChecklist ? .newItem : .body
            }
        }
        .sheet(isPresented: $showReminder) { ReminderSheet(note: note) }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Button {
                    showEmoji = true
                } label: {
                    Text(note.emoji.isEmpty ? "＋" : note.emoji)
                        .font(note.emoji.isEmpty ? .title3 : .largeTitle)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 36)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showEmoji) { EmojiPicker(selection: $note.emoji) }

                TextField("Tiêu đề", text: $note.title, axis: .vertical)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focus = .body }
            }
            metadataChips
        }
    }

    private var metadataChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Toggle(isOn: Binding(get: { note.showOnLockScreen }, set: {
                    note.showOnLockScreen = $0
                    note.touch()
                    model.scheduleWidgetReload(context: context, delay: .zero)
                })) {
                    Label("Lock Screen", systemImage: "lock.iphone")
                }
                .toggleStyle(.button)
                .tint(.orange)

                Menu {
                    Button("Không có thư mục") { note.folder = nil }
                    ForEach(folders) { folder in
                        Button { note.folder = folder } label: { Label(folder.name, systemImage: folder.symbol) }
                    }
                } label: {
                    Label(note.folder?.name ?? String(localized: "Thư mục"), systemImage: note.folder?.symbol ?? "folder")
                }
                .menuStyle(.button)

                Button {
                    showReminder = true
                } label: {
                    if let date = note.reminderDate, date > Date() {
                        Label(date.formatted(.dateTime.day().month().hour().minute()), systemImage: "bell.fill")
                    } else {
                        Label("Nhắc tôi", systemImage: "bell")
                    }
                }

                Menu {
                    ForEach(NoteColor.allCases) { c in
                        Button {
                            note.color = c
                        } label: {
                            Label(c.label, systemImage: note.color == c ? "checkmark.circle.fill" : "circle.fill")
                        }
                        .tint(c.color)
                    }
                } label: {
                    Label("Màu", systemImage: "paintpalette")
                        .foregroundStyle(note.color == .none ? Color.primary : note.color.color)
                }
                .menuStyle(.button)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.subheadline)
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            if note.hasChecklist {
                HStack {
                    Text("\(note.sortedItems.filter(\.isDone).count)/\(note.sortedItems.count) xong")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ProgressView(value: note.progress)
                        .tint(note.color == .none ? .accentColor : note.color.color)
                }
            }
            ForEach(note.sortedItems.filter { !$0.isDone }) { item in
                row(item)
            }
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                TextField("Thêm việc…", text: $newItemText)
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .newItem)
                    .submitLabel(.done)
                    .onSubmit(addItem)
            }
            .padding(.vertical, 4)

            let finished = note.sortedItems.filter(\.isDone)
            if !finished.isEmpty {
                DisclosureGroup(isExpanded: $showDone) {
                    // Grouped by the day each task was ticked off, newest first.
                    let days = Dictionary(grouping: finished) { Calendar.current.startOfDay(for: $0.completedAt ?? $0.createdAt) }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(days.keys.sorted(by: >), id: \.self) { day in
                            Text(Self.dayTitle(day))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                            ForEach(days[day]!.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }) { item in
                                row(item)
                            }
                        }
                    }
                } label: {
                    Label("Đã xong · \(finished.count)", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ item: ChecklistItem) -> some View {
        ChecklistRow(item: item, tint: note.color == .none ? .accentColor : note.color.color) {
            context.delete(item)
            note.touch()
            changed()
        } onChange: {
            changed()
        }
    }

    private static func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return String(localized: "Hôm nay") }
        if cal.isDateInYesterday(day) { return String(localized: "Hôm qua") }
        return day.formatted(.dateTime.weekday(.wide).day().month())
    }

    @ViewBuilder
    private var bodyEditor: some View {
        if showPreview {
            Text(markdown)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
                .onTapGesture(count: 2) { showPreview = false }
        } else {
            ZStack(alignment: .topLeading) {
                if note.body.isEmpty {
                    Text("Bắt đầu viết… Dùng #thẻ để phân loại, **đậm**, - danh sách")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $note.body, selection: $selection)
                    .font(.system(.body, design: .default))
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(minHeight: compact ? 140 : 320)
                    .focused($focus, equals: .body)
            }
        }
    }

    private var tagChips: some View {
        HStack(spacing: 6) {
            ForEach(note.tags, id: \.self) { tag in
                Button("#\(tag)") {
                    model.sidebar = .tag(tag)
                    model.tab = .notes
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.accentColor)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Tạo \(note.createdAt.formatted(date: .abbreviated, time: .shortened))")
            Spacer()
            Text("\(note.wordCount) từ")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if !compact { primaryButtons }
        }
        #if os(iOS)
        ToolbarItemGroup(placement: .keyboard) {
            formatButtons
            Spacer()
            Button("Xong") {
                // Committing here would read text UIKit hasn't flushed yet; the focus-loss handler
                // saves the item once editing ends.
                focus = nil
                dismissKeyboard()
            }
        }
        #else
        ToolbarItemGroup(placement: .secondaryAction) {
            if !compact { formatButtons }
        }
        #endif
    }

    @ViewBuilder
    private var primaryButtons: some View {
            Button(showPreview ? "Sửa" : "Xem trước", systemImage: showPreview ? "pencil" : "eye") {
                showPreview.toggle()
            }
            Button(note.isPinned ? "Bỏ ghim" : "Ghim", systemImage: note.isPinned ? "pin.fill" : "pin") {
                note.isPinned.toggle()
                note.touch()
            }
            Menu {
                Button("Thêm danh sách việc", systemImage: "checklist") {
                    focus = .newItem
                    if !note.hasChecklist { _ = note.addItem("") }
                }
                ShareLink(item: exportText, subject: Text(note.displayTitle)) {
                    Label("Chia sẻ", systemImage: "square.and.arrow.up")
                }
                Button("Sao chép nội dung", systemImage: "doc.on.doc") { copyToClipboard() }
                Divider()
                Button("Chuyển vào thùng rác", systemImage: "trash", role: .destructive) {
                    note.moveToTrash()
                    NotificationService.shared.cancel(id: note.id)
                    model.selectedNote = nil
                    model.scheduleWidgetReload(context: context, delay: .zero)
                }
            } label: {
                Label("Thêm", systemImage: "ellipsis.circle")
            }
    }

    @ViewBuilder
    private var formatButtons: some View {
        Button("Tiêu đề", systemImage: "textformat.size") { insertLinePrefix("## ") }
        Button("Đậm", systemImage: "bold") { wrapSelection("**") }
        Button("Danh sách", systemImage: "list.bullet") { insertLinePrefix("- ") }
        Button("Thẻ", systemImage: "number") { insert("#") }
        Button("Việc cần làm", systemImage: "checklist") {
            if !note.hasChecklist { _ = note.addItem("") }
            focus = .newItem
        }
        #if os(macOS)
        Button("Nghiêng", systemImage: "italic") { wrapSelection("_") }
        Button("Thời gian", systemImage: "clock") {
            insert(Date().formatted(date: .abbreviated, time: .shortened) + " ")
        }
        #endif
    }

    // MARK: Actions

    private var markdown: AttributedString {
        (try? AttributedString(
            markdown: note.body,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(note.body)
    }

    private var exportText: String {
        var parts = [note.displayTitle]
        if note.hasChecklist {
            parts.append(note.sortedItems.map { "\($0.isDone ? "☑︎" : "☐") \($0.text)" }.joined(separator: "\n"))
        }
        if !note.body.isEmpty { parts.append(note.body) }
        return parts.joined(separator: "\n\n")
    }

    private func copyToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = exportText
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(exportText, forType: .string)
        #endif
    }

    private func changed() {
        // Daily notes start unsaved so browsing days doesn't create empty notes.
        if note.modelContext == nil { context.insert(note) }
        note.touch()
        model.scheduleWidgetReload(context: context)
    }

    private var showsChecklist: Bool {
        if compact && note.dailyDate != nil { return false }
        return note.hasChecklist || note.title == String(localized: "Việc cần làm")
    }

    /// Return key: add the item and stay in the field for the next one.
    private func addItem() {
        commitNewItem()
        focus = .newItem
    }

    private func commitNewItem() {
        let text = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Reuse an empty placeholder row if one exists.
        if let blank = note.sortedItems.first(where: { $0.text.isEmpty }) {
            blank.text = text
        } else {
            _ = note.addItem(text)
        }
        newItemText = ""
        changed()
    }

    private var cursorRange: Range<String.Index> {
        if case .selection(let range)? = selection?.indices,
           range.lowerBound >= note.body.startIndex, range.upperBound <= note.body.endIndex {
            return range
        }
        return note.body.endIndex..<note.body.endIndex
    }

    private func insert(_ text: String) {
        let range = cursorRange
        let offset = note.body.distance(from: note.body.startIndex, to: range.lowerBound)
        note.body.replaceSubrange(range, with: text)
        let caret = note.body.index(note.body.startIndex, offsetBy: offset + text.count)
        selection = TextSelection(insertionPoint: caret)
        focus = .body
    }

    private func wrapSelection(_ token: String) {
        let range = cursorRange
        let selected = String(note.body[range])
        let offset = note.body.distance(from: note.body.startIndex, to: range.lowerBound)
        note.body.replaceSubrange(range, with: token + selected + token)
        let caret = note.body.index(note.body.startIndex, offsetBy: offset + token.count + selected.count)
        selection = TextSelection(insertionPoint: caret)
        focus = .body
    }

    private func insertLinePrefix(_ prefix: String) {
        let range = cursorRange
        let lineStart = note.body[..<range.lowerBound].lastIndex(of: "\n").map { note.body.index(after: $0) }
            ?? note.body.startIndex
        let offset = note.body.distance(from: note.body.startIndex, to: range.lowerBound)
        note.body.insert(contentsOf: prefix, at: lineStart)
        let caret = note.body.index(note.body.startIndex, offsetBy: offset + prefix.count)
        selection = TextSelection(insertionPoint: caret)
        focus = .body
    }
}

// MARK: - Checklist row

struct ChecklistRow: View {
    @Bindable var item: ChecklistItem
    var tint: Color
    var onDelete: () -> Void
    var onChange: () -> Void
    @State private var showDue = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                withAnimation(.snappy) { item.toggle() }
                onChange()
            } label: {
                CheckGlyph(isDone: item.isDone, tint: tint)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                TextField("Việc cần làm", text: $item.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
                    .onChange(of: item.text) { onChange() }
                if let due = item.dueLabel {
                    Label(due, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(item.isOverdue ? .red : .secondary)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button("Làm hôm nay", systemImage: "sun.max") {
                    item.schedule(on: Date())
                    onChange()
                }
                Button("Đặt hạn", systemImage: "calendar.badge.clock") { showDue = true }
                if item.dueDate != nil {
                    Button("Bỏ hạn", systemImage: "calendar.badge.minus") {
                        item.dueDate = nil
                        NotificationService.shared.cancel(id: item.id)
                        onChange()
                    }
                }
                Button("Xoá", systemImage: "trash", role: .destructive) {
                    NotificationService.shared.cancel(id: item.id)
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 24, height: 24)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $showDue) {
            DueDateSheet(item: item, onSave: onChange)
        }
    }
}

struct DueDateSheet: View {
    @Bindable var item: ChecklistItem
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date().addingTimeInterval(3600)
    @State private var allDay = false
    @State private var remind = true

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Hạn", selection: $date, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                Toggle("Cả ngày", isOn: $allDay)
                if !allDay {
                    Toggle("Thông báo khi đến hạn", isOn: $remind)
                }
            }
            .navigationTitle(item.text.isEmpty ? "Đặt hạn" : item.text)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        item.isAllDay = allDay
                        item.dueDate = allDay ? Calendar.current.startOfDay(for: date) : date
                        NotificationService.shared.cancel(id: item.id)
                        if remind, !allDay, let note = item.note {
                            NotificationService.shared.schedule(
                                id: item.id, noteID: note.id, title: item.text,
                                body: note.displayTitle, at: date
                            )
                        }
                        onSave()
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let d = item.dueDate { date = d }
                allDay = item.isAllDay
            }
        }
        .presentationDetents([.large])
    }
}

struct ReminderSheet: View {
    @Bindable var note: Note
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Thời gian", selection: $date, in: Date()...)
                        .datePickerStyle(.graphical)
                }
                Section("Nhanh") {
                    quick("Sau 1 giờ", Calendar.current.date(byAdding: .hour, value: 1, to: Date())!)
                    quick("Tối nay (20:00)", Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!)
                    quick("Sáng mai (8:00)", Calendar.current.date(
                        bySettingHour: 8, minute: 0, second: 0,
                        of: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)!)
                }
                if note.reminderDate != nil {
                    Button("Xoá nhắc nhở", role: .destructive) {
                        note.reminderDate = nil
                        NotificationService.shared.cancel(id: note.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Nhắc nhở")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lưu") { save(date) } }
            }
            .onAppear { if let d = note.reminderDate, d > Date() { date = d } }
        }
    }

    private func quick(_ title: String, _ value: Date) -> some View {
        Button {
            save(value)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(value.formatted(.dateTime.weekday().hour().minute())).foregroundStyle(.secondary)
            }
        }
        .disabled(value <= Date())
    }

    private func save(_ value: Date) {
        note.reminderDate = value
        NotificationService.shared.schedule(
            id: note.id, noteID: note.id, title: note.displayTitle,
            body: note.preview.isEmpty ? String(localized: "Đến giờ xem ghi chú") : note.preview, at: value
        )
        dismiss()
    }
}

struct EmojiPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    static let emojis = Array("📝📌✅📅⭐️💡🔥❤️🎯📚🎓💼🏠🛒✈️🏃‍♂️🍜☕️🎵🎨💰🧠🌱🎁🐶⚽️🎮📷🔒⏰🗓️💬🚀🌙☀️🌈🍀").map(String.init)

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(38)), count: 7), spacing: 8) {
                ForEach(Self.emojis, id: \.self) { e in
                    Button(e) {
                        selection = e
                        dismiss()
                    }
                    .font(.title2)
                    .buttonStyle(.plain)
                }
            }
            if !selection.isEmpty {
                Button("Bỏ biểu tượng", role: .destructive) {
                    selection = ""
                    dismiss()
                }
                .font(.footnote)
            }
        }
        .padding()
        .presentationCompactAdaptation(.popover)
    }
}
