import SwiftData
import SwiftUI

struct NotesSplitView: View {
    @Environment(AppModel.self) private var model
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            NoteListView(item: model.sidebar ?? .all)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            if let note = model.selectedNote, note.modelContext != nil {
                NoteEditorView(note: note)
                    .id(note.id)
            } else {
                ContentUnavailableView(
                    "Chọn một ghi chú",
                    systemImage: "note.text",
                    description: Text("Hoặc tạo ghi chú mới bằng nút bút chì.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Folder.sortIndex) private var folders: [Folder]
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var renaming: Folder?
    @State private var showSettings = false

    private let smartItems: [SidebarItem] = [.all, .pinned, .lockScreen, .checklists, .daily]

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebar) {
            Section {
                ForEach(smartItems, id: \.self) { item in
                    row(item, tint: item == .lockScreen ? .orange : .accentColor)
                }
            }

            Section("Thư mục") {
                ForEach(folders) { folder in
                    row(.folder(folder), tint: folder.color.color)
                        .contextMenu {
                            Button("Đổi tên", systemImage: "pencil") {
                                newFolderName = folder.name
                                renaming = folder
                            }
                            Menu("Màu", systemImage: "paintpalette") {
                                ForEach(NoteColor.allCases.dropFirst()) { c in
                                    Button(c.label) { folder.colorName = c.rawValue }
                                }
                            }
                            Menu("Biểu tượng", systemImage: "square.grid.2x2") {
                                ForEach(Self.folderSymbols, id: \.self) { s in
                                    Button { folder.symbol = s } label: { Label(s, systemImage: s) }
                                }
                            }
                            Divider()
                            Button("Xoá thư mục", systemImage: "trash", role: .destructive) {
                                if model.sidebar == .folder(folder) { model.sidebar = .all }
                                context.delete(folder)
                            }
                        }
                }
                Button {
                    newFolderName = ""
                    showNewFolder = true
                } label: {
                    Label("Thư mục mới", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
            }

            let tags = allTags
            if !tags.isEmpty {
                Section("Thẻ") {
                    ForEach(tags, id: \.self) { tag in
                        row(.tag(tag), tint: .secondary)
                    }
                }
            }

            Section {
                row(.trash, tint: .secondary)
            }
        }
        .navigationTitle("DailyNote")
        .safeAreaInset(edge: .bottom) { SyncStatusBadge().padding(.bottom, 8) }
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                Button("Cài đặt", systemImage: "gearshape") { showSettings = true }
            }
            #endif
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .alert("Thư mục mới", isPresented: $showNewFolder) {
            TextField("Tên thư mục", text: $newFolderName)
            Button("Huỷ", role: .cancel) {}
            Button("Tạo") {
                let name = newFolderName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let color = NoteColor.allCases.dropFirst()[folders.count % (NoteColor.allCases.count - 1) + 1]
                let folder = Folder(name: name, color: color, sortIndex: (folders.map(\.sortIndex).max() ?? 0) + 1)
                context.insert(folder)
                model.sidebar = .folder(folder)
            }
        }
        .alert("Đổi tên thư mục", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Tên thư mục", text: $newFolderName)
            Button("Huỷ", role: .cancel) {}
            Button("Lưu") { renaming?.name = newFolderName }
        }
    }

    private func row(_ item: SidebarItem, tint: Color) -> some View {
        Label {
            HStack {
                Text(item.title)
                Spacer()
                let count = notes.filter(item.includes).count
                if count > 0 {
                    Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
        } icon: {
            Image(systemName: item.symbol).foregroundStyle(tint)
        }
        .tag(item)
    }

    private var allTags: [String] {
        var counts: [String: Int] = [:]
        for note in notes where !note.isTrashed {
            for tag in note.tags { counts[tag, default: 0] += 1 }
        }
        return counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map(\.key)
    }

    static let folderSymbols = [
        "folder", "briefcase", "house", "book", "graduationcap", "heart", "star", "lightbulb",
        "cart", "airplane", "dumbbell", "fork.knife", "music.note", "paintbrush", "leaf", "gamecontroller",
    ]
}

struct SyncStatusBadge: View {
    private var sync = SyncMonitor.shared

    var body: some View {
        Label(sync.statusText, systemImage: sync.symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
    }
}

// MARK: - Note list

struct NoteListView: View {
    let item: SidebarItem
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @State private var confirmEmptyTrash = false

    private var notes: [Note] {
        let filtered = allNotes.filter(item.includes)
        switch model.sort {
        case .updated: return filtered
        case .created: return filtered.sorted { $0.createdAt > $1.createdAt }
        case .title: return filtered.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        }
    }

    var body: some View {
        @Bindable var model = model
        let notes = notes
        let pinned = item == .trash || item == .pinned ? [] : notes.filter(\.isPinned)
        let others = notes.filter { !pinned.contains($0) }

        List(selection: $model.selectedNote) {
            if !pinned.isEmpty {
                Section("Đã ghim") {
                    ForEach(pinned) { NoteRow(note: $0).tag($0) }
                }
            }
            Section(pinned.isEmpty ? "" : "Ghi chú") {
                ForEach(others) { NoteRow(note: $0).tag($0) }
            }
        }
        .overlay {
            if notes.isEmpty {
                ContentUnavailableView {
                    Label(item == .trash ? "Thùng rác trống" : "Chưa có ghi chú", systemImage: item.symbol)
                } description: {
                    if item == .lockScreen {
                        Text("Bật “Hiện trên Lock Screen” trong ghi chú để nó xuất hiện trên widget màn hình khoá.")
                    } else if item != .trash {
                        Text("Nhấn nút bút chì để bắt đầu viết.")
                    }
                }
            }
        }
        .navigationTitle(item.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if item == .trash {
                    Button("Dọn thùng rác", systemImage: "trash.slash", role: .destructive) { confirmEmptyTrash = true }
                        .disabled(notes.isEmpty)
                } else {
                    Menu {
                        Picker("Sắp xếp", selection: $model.sort) {
                            ForEach(NoteSort.allCases) { Text($0.label).tag($0) }
                        }
                        Button("Danh sách việc mới", systemImage: "checklist") {
                            model.createNote(in: context, checklist: true)
                        }
                    } label: {
                        Label("Tuỳ chọn", systemImage: "ellipsis.circle")
                    }
                    Button("Ghi chú mới", systemImage: "square.and.pencil") {
                        model.createNote(in: context)
                    }
                }
            }
        }
        .confirmationDialog("Xoá vĩnh viễn \(notes.count) ghi chú?", isPresented: $confirmEmptyTrash, titleVisibility: .visible) {
            Button("Xoá vĩnh viễn", role: .destructive) {
                for note in notes { context.delete(note) }
                model.selectedNote = nil
            }
        }
    }
}

struct NoteRow: View {
    let note: Note
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if note.color != .none {
                RoundedRectangle(cornerRadius: 2)
                    .fill(note.color.color)
                    .frame(width: 4)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if !note.emoji.isEmpty { Text(note.emoji) }
                    Text(note.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if note.showOnLockScreen {
                        Image(systemName: "lock.iphone").foregroundStyle(.orange).font(.caption)
                    }
                    if note.reminderDate.map({ $0 > Date() }) == true {
                        Image(systemName: "bell.fill").foregroundStyle(.secondary).font(.caption2)
                    }
                }
                HStack(spacing: 6) {
                    Text(note.updatedAt, format: note.updatedAt.isToday
                         ? .dateTime.hour().minute() : .dateTime.day().month(.abbreviated))
                        .foregroundStyle(.secondary)
                    Text(note.preview)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .font(.subheadline)
                if note.hasChecklist {
                    ProgressView(value: note.progress)
                        .tint(note.color == .none ? .accentColor : note.color.color)
                        .frame(maxWidth: 160)
                }
                if let folder = note.folder, model.sidebar != .folder(folder) {
                    Label(folder.name, systemImage: folder.symbol)
                        .font(.caption)
                        .foregroundStyle(folder.color.color)
                }
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .leading) {
            if !note.isTrashed {
                Button {
                    note.isPinned.toggle()
                } label: {
                    Label(note.isPinned ? "Bỏ ghim" : "Ghim", systemImage: note.isPinned ? "pin.slash" : "pin")
                }
                .tint(.yellow)
                Button {
                    note.showOnLockScreen.toggle()
                    model.scheduleWidgetReload(context: context, delay: .zero)
                } label: {
                    Label("Lock Screen", systemImage: note.showOnLockScreen ? "lock.slash" : "lock.iphone")
                }
                .tint(.orange)
            }
        }
        .swipeActions(edge: .trailing) {
            if note.isTrashed {
                Button("Xoá", systemImage: "trash", role: .destructive) { delete() }
                Button("Khôi phục", systemImage: "arrow.uturn.backward") { note.restore() }.tint(.green)
            } else {
                Button("Thùng rác", systemImage: "trash", role: .destructive) { trash() }
            }
        }
        .contextMenu {
            if note.isTrashed {
                Button("Khôi phục", systemImage: "arrow.uturn.backward") { note.restore() }
                Button("Xoá vĩnh viễn", systemImage: "trash", role: .destructive) { delete() }
            } else {
                Button(note.isPinned ? "Bỏ ghim" : "Ghim", systemImage: "pin") { note.isPinned.toggle() }
                Button(note.showOnLockScreen ? "Gỡ khỏi Lock Screen" : "Hiện trên Lock Screen", systemImage: "lock.iphone") {
                    note.showOnLockScreen.toggle()
                    model.scheduleWidgetReload(context: context, delay: .zero)
                }
                Button("Nhân bản", systemImage: "plus.square.on.square") { duplicate() }
                Divider()
                Button("Chuyển vào thùng rác", systemImage: "trash", role: .destructive) { trash() }
            }
        }
    }

    private func trash() {
        if model.selectedNote == note { model.selectedNote = nil }
        note.moveToTrash()
        NotificationService.shared.cancel(id: note.id)
        model.scheduleWidgetReload(context: context, delay: .zero)
    }

    private func delete() {
        if model.selectedNote == note { model.selectedNote = nil }
        context.delete(note)
    }

    private func duplicate() {
        let copy = Note(title: note.title.isEmpty ? "" : note.title + " (bản sao)", body: note.body, folder: note.folder)
        copy.emoji = note.emoji
        copy.colorName = note.colorName
        context.insert(copy)
        for item in note.sortedItems { _ = copy.addItem(item.text, dueDate: item.dueDate, isAllDay: item.isAllDay) }
        model.selectedNote = copy
    }
}

extension Date {
    var isToday: Bool { Calendar.current.isDateInToday(self) }
}
