import PhotosUI
import SwiftData
import SwiftUI

struct LockScreenStudioView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Query(filter: #Predicate<Note> { !$0.isTrashed }, sort: \Note.updatedAt, order: .reverse) private var notes: [Note]

    @State private var config = WallpaperConfig.load()
    @State private var content = WallpaperContent()
    @State private var background: PlatformImage? = WallpaperConfig.loadBackground()
    @State private var photoItem: PhotosPickerItem?
    @State private var exported: WallpaperFile?
    @State private var toast: String?
    @State private var calendarModel = CalendarModel.shared
    @State private var category: WallpaperConfig.Category = .all
    @State private var lastApplied = WallpaperAutomation.lastApplied
    @State private var previewHome = false
    @AppStorage(AppConstants.Key.weekStartsMonday, store: .shared) private var weekStartsMonday = true
    @AppStorage(AppConstants.Key.todayMarker, store: .shared) private var marker: TodayMarker = .ring

    private var isWide: Bool {
        #if os(iOS)
        sizeClass == .regular
        #else
        true
        #endif
    }

    /// Real data, with sample events/tasks filling whatever is missing so every template reads well in the gallery.
    private var galleryContent: WallpaperContent {
        var c = content
        let sample = WallpaperContent.sample
        if c.rangeEvents.isEmpty {
            c.rangeEvents = sample.rangeEvents
            c.events = sample.events
            c.busyDays = sample.busyDays
        }
        if c.tasks.isEmpty && c.doneTasks.isEmpty {
            c.tasks = sample.tasks
            c.doneTasks = sample.doneTasks
        }
        if c.noteTitle == nil {
            c.noteTitle = sample.noteTitle
            c.noteItems = sample.noteItems
        }
        return c
    }

    var body: some View {
        Group {
            if isWide {
                HStack(alignment: .top, spacing: 0) {
                    ScrollView { previewColumn.padding() }
                        .frame(width: 380)
                    Divider()
                    controls
                }
            } else {
                Form {
                    Section {
                        previewColumn
                            .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(Color.clear)
                    controlSections
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle("Lock Screen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showLockScreenSetup = true
                } label: {
                    Label("Hướng dẫn", systemImage: "questionmark.circle")
                }
            }
        }
        .sheet(isPresented: Bindable(model).showLockScreenSetup) {
            LockScreenSetupView()
        }
        .onAppear {
            WallpaperRenderer.rememberScreen()
            refreshContent()
        }
        .onChange(of: config) {
            config.save()
            exported = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                lastApplied = WallpaperAutomation.lastApplied
                refreshContent()
            }
        }
        .onChange(of: calendarModel.revision) { refreshContent() }
        .onChange(of: weekStartsMonday) { refreshContent() }
        .onChange(of: marker) { refreshContent() }
        .onChange(of: photoItem) { loadPhoto() }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: Preview

    private var previewColumn: some View {
        VStack(spacing: 14) {
            let canvas = WallpaperRenderer.canvasSize
            let width: CGFloat = isWide ? 320 : 250
            let scale = width / canvas.width
            ZStack(alignment: .top) {
                if previewHome && config.homeMode == .clean {
                    HomeWallpaperView(config: config, background: background, size: canvas)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: canvas.width * scale, height: canvas.height * scale, alignment: .topLeading)
                    MockHomeIcons(scale: scale, size: canvas)
                } else {
                    WallpaperView(
                        config: config, content: content, background: background, size: canvas,
                        onMoveSticker: { id, point in
                            if let i = config.stickers.firstIndex(where: { $0.id == id }) {
                                config.stickers[i].x = point.x
                                config.stickers[i].y = point.y
                            }
                        },
                        onRemoveSticker: { id in config.stickers.removeAll { $0.id == id } }
                    )
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: canvas.width * scale, height: canvas.height * scale, alignment: .topLeading)

                    if previewHome {
                        MockHomeIcons(scale: scale, size: canvas)
                    } else {
                        MockClock(color: config.foreground, scale: scale)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 34 * scale * 1.6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 34 * scale * 1.6, style: .continuous).stroke(.quaternary, lineWidth: 6))
            .shadow(color: .black.opacity(0.2), radius: 18, y: 8)

            if config.homeMode != .lockOnly {
                Picker("Xem trước", selection: $previewHome) {
                    Text("Lock Screen").tag(false)
                    Text("Màn hình chính").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
            }

            if !config.stickers.isEmpty && !previewHome {
                Text("Kéo sticker để di chuyển · chạm 2 lần để xoá")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            #if os(iOS)
            Button {
                applyNow()
            } label: {
                Label(lastApplied == nil ? "Đặt làm hình nền" : "Cập nhật hình nền ngay", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            #endif

            HStack {
                #if os(iOS)
                Button {
                    Task { await saveToPhotos() }
                } label: {
                    Label("Lưu vào Ảnh", systemImage: "photo.badge.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                #endif
                if let exported {
                    ShareLink(item: exported, preview: SharePreview("Hình nền DailyNote", image: Image(systemName: "photo"))) {
                        Label("Chia sẻ", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        exported = renderFile()
                    } label: {
                        Label("Xuất ảnh", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.large)
        }
    }

    // MARK: Controls

    private var controls: some View {
        Form { controlSections }
            .formStyle(.grouped)
    }

    @ViewBuilder
    private var controlSections: some View {
        #if os(iOS)
        automationSection
        #endif
        templateSection
        layoutSection
        backgroundSection
        styleSection
        #if os(iOS)
        homeScreenSection
        #endif
        stickerSection
        notesSection
        widgetGuideSection
    }

    private var automationSection: some View {
        Section {
            Button {
                model.showLockScreenSetup = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: automationSymbol)
                        .font(.title2)
                        .foregroundStyle(automationTint)
                        .frame(width: 32)
                    // Re-evaluated every minute so "last updated" stays current.
                    TimelineView(.everyMinute) { _ in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(automationTitle).font(.headline).foregroundStyle(.primary)
                            Text(automationSubtitle).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Tự động cập nhật")
        }
    }

    private var automationTitle: LocalizedStringKey {
        if lastApplied == nil { return "Thiết lập tự động cập nhật" }
        return WallpaperAutomation.isStale ? "Tự động hoá có thể đã dừng" : "Đang tự động cập nhật"
    }

    private var automationSubtitle: LocalizedStringKey {
        guard let lastApplied else {
            return "Dùng Phím tắt để vẽ lại lịch và việc cần làm lên hình nền mỗi ngày, lúc hoàng hôn và khi bạn đóng app."
        }
        let when = lastApplied.formatted(.relative(presentation: .named))
        return "Lần cuối: \(when). Chạm để xem hướng dẫn tự động hoá."
    }

    private var automationSymbol: String {
        if lastApplied == nil { return "sparkles" }
        return WallpaperAutomation.isStale ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"
    }

    private var automationTint: Color {
        if lastApplied == nil { return .accentColor }
        return WallpaperAutomation.isStale ? .orange : .green
    }

    private var templateSection: some View {
        Section("Mẫu") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WallpaperConfig.Category.allCases) { c in
                        Button(c.label) { withAnimation { category = c } }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .tint(category == c ? .accentColor : .secondary)
                            .controlSize(.small)
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(WallpaperConfig.Layout.allCases.filter { category == .all || $0.category == category }) { layout in
                        TemplateThumbnail(
                            layout: layout, config: config, content: galleryContent, background: background,
                            isCurrent: config.layout == layout
                        ) {
                            withAnimation { config.layout = layout }
                            if layout.usesCalendar && !calendarModel.hasAccess {
                                Task { await calendarModel.requestAccess() }
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private var layoutSection: some View {
        switch config.layout {
        case .classic:
            Section {
                Toggle("Lịch tháng", systemImage: "calendar", isOn: $config.showCalendar)
                Toggle("Sự kiện sắp tới", systemImage: "list.bullet.below.rectangle", isOn: $config.showAgenda)
                Toggle("Việc cần làm", systemImage: "checklist", isOn: $config.showTasks)
                Toggle("Ghi chú", systemImage: "note.text", isOn: $config.showNote)
                calendarAccessButton
            } header: {
                Text("Hiển thị trên hình nền")
            } footer: {
                Text("Ghi chú hiển thị là ghi chú bạn đã bật “Lock Screen”. Việc cần làm lấy từ các danh sách đang mở.")
            }
        case .yearProgress:
            Section("Đếm ngược") {
                TextField("Tiêu đề (vd: ngày đến kỳ nghỉ)", text: $config.countdownTitle)
                Toggle("Ngày riêng", isOn: Binding(
                    get: { config.countdownDate != nil },
                    set: { config.countdownDate = $0 ? Calendar.current.date(byAdding: .month, value: 1, to: Date()) : nil }
                ))
                if let date = config.countdownDate {
                    DatePicker("Đếm đến", selection: Binding(get: { date }, set: { config.countdownDate = $0 }),
                               in: Date()..., displayedComponents: .date)
                } else {
                    LabeledContent("Đếm đến", value: "Năm mới")
                }
            }
        case .monthEvents, .week, .timeline, .today:
            if !calendarModel.hasAccess {
                Section { calendarAccessButton } footer: {
                    Text("Mẫu này hiển thị sự kiện từ Lịch của bạn (Apple, Google, Outlook…).")
                }
            }
        case .matrix, .sticky:
            EmptyView()
        }
    }

    @ViewBuilder
    private var calendarAccessButton: some View {
        if !calendarModel.hasAccess && (config.layout != .classic || config.showAgenda) {
            Button("Cho phép truy cập Lịch") { Task { await calendarModel.requestAccess() } }
        }
    }

    private var backgroundSection: some View {
        Section("Nền") {
            Toggle("Dùng ảnh của tôi", isOn: $config.usePhoto)
            if config.usePhoto {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(background == nil ? "Chọn ảnh" : "Đổi ảnh", systemImage: "photo.on.rectangle")
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(WallpaperConfig.gradients.indices, id: \.self) { i in
                            LinearGradient(colors: WallpaperConfig.gradients[i], startPoint: .topLeading, endPoint: .bottomTrailing)
                                .frame(width: 44, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.accentColor, lineWidth: config.gradientIndex == i ? 3 : 0))
                                .onTapGesture { config.gradientIndex = i }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            LabeledContent("Làm mờ") {
                Slider(value: $config.blur, in: 0...30)
            }
            LabeledContent("Làm tối/sáng") {
                Slider(value: $config.dim, in: 0...0.7)
            }
        }
    }

    private var styleSection: some View {
        Section("Phong cách") {
            ColorPicker("Màu nhấn", selection: Binding(
                get: { config.accent },
                set: { config.accentHex = $0.hexString }
            ), supportsOpacity: false)
            Picker("Màu chữ", selection: $config.lightText) {
                Text("Sáng").tag(true)
                Text("Tối").tag(false)
            }
            Picker("Khung", selection: $config.panel) {
                ForEach(WallpaperConfig.PanelStyle.allCases) { Text($0.label).tag($0) }
            }
            Picker("Vị trí", selection: $config.position) {
                ForEach(WallpaperConfig.Position.allCases) { Text($0.label).tag($0) }
            }
            Picker("Tuần bắt đầu", selection: $weekStartsMonday) {
                Text("Thứ Hai").tag(true)
                Text("Chủ Nhật").tag(false)
            }
            Picker("Đánh dấu hôm nay", selection: $marker) {
                ForEach(TodayMarker.allCases) { Text($0.label).tag($0) }
            }
        }
    }

    private var homeScreenSection: some View {
        Section {
            Picker("Màn hình chính", selection: $config.homeMode) {
                ForEach(WallpaperConfig.HomeMode.allCases) { Text($0.label).tag($0) }
            }
            if config.homeMode == .clean {
                LabeledContent("Làm mờ màn hình chính") {
                    Slider(value: $config.homeBlur, in: 0...40)
                }
            }
            if config.homeMode != .lockOnly {
                Toggle("Làm mờ để dễ đọc (Legibility Blur)", isOn: $config.legibilityBlur)
            }
            Toggle("Vẽ lại hai lần", isOn: $config.redraw)
        } header: {
            Text("Khi phím tắt chạy")
        } footer: {
            Text("“Chỉ ảnh nền” giữ Màn hình chính gọn gàng, không có lịch phía sau icon. “Vẽ lại hai lần” khắc phục lỗi iOS đôi khi không hiện hình nền mới.")
        }
    }

    private var stickerSection: some View {
        Section("Sticker") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                ForEach(WallpaperConfig.stickerPalette, id: \.self) { emoji in
                    Button(emoji) {
                        config.stickers.append(.init(emoji: emoji, x: .random(in: 0.15...0.85), y: .random(in: 0.08...0.3)))
                    }
                    .font(.title2)
                    .buttonStyle(.plain)
                }
            }
            if !config.stickers.isEmpty {
                Button("Xoá tất cả sticker", role: .destructive) { config.stickers.removeAll() }
            }
        }
    }

    private var notesSection: some View {
        Section {
            if notes.filter(\.showOnLockScreen).isEmpty {
                Text("Chưa có ghi chú nào. Bật bên dưới hoặc trong trình soạn thảo.")
                    .foregroundStyle(.secondary)
            }
            ForEach(notes.prefix(12)) { note in
                Toggle(isOn: Binding(get: { note.showOnLockScreen }, set: {
                    note.showOnLockScreen = $0
                    note.touch()
                    model.scheduleWidgetReload(context: context, delay: .zero)
                    refreshContent()
                })) {
                    Label {
                        Text(note.displayTitle).lineLimit(1)
                    } icon: {
                        Text(note.emoji.isEmpty ? "📝" : note.emoji)
                    }
                }
            }
        } header: {
            Text("Ghi chú trên Lock Screen")
        } footer: {
            Text("Các ghi chú này hiện trên widget Lock Screen, mẫu “Tổng hợp” và “Giấy note”.")
        }
    }

    private var widgetGuideSection: some View {
        Section("Thêm widget vào Lock Screen") {
            GuideStep(n: 1, text: "Chạm và giữ Lock Screen, chọn “Tuỳ chỉnh” › “Màn hình khoá”.")
            GuideStep(n: 2, text: "Chạm vùng widget dưới đồng hồ, chọn DailyNote: Ghi chú, Việc cần làm, Lịch hoặc Ngày.")
            GuideStep(n: 3, text: "Ở hai nút dưới cùng, thay bằng “Ghi chú nhanh” để ghi chú ngay từ màn hình khoá.")
            GuideStep(n: 4, text: "Chạm vào ô trên widget Việc cần làm để đánh dấu xong mà không cần mở khoá.")
        }
    }

    // MARK: Actions

    private func refreshContent() {
        content = WallpaperContent.current(context: context)
    }

    /// Runs the refresh shortcut when it is installed; otherwise walks the user through setting it up.
    private func applyNow() {
        config.save()
        if WallpaperAutomation.isInstalled {
            openURL(WallpaperAutomation.runURL)
        } else {
            model.showLockScreenSetup = true
        }
    }

    private func loadPhoto() {
        guard let photoItem else { return }
        Task {
            guard let data = try? await photoItem.loadTransferable(type: Data.self),
                  let jpeg = ImageEncoding.jpeg(from: data) else { return }
            try? jpeg.write(to: WallpaperConfig.backgroundURL, options: .atomic)
            background = PlatformImage.fromData(jpeg)
            config.usePhoto = true
            exported = nil
        }
    }

    private func renderFile() -> WallpaperFile? {
        guard let cg = WallpaperRenderer.render(config: config, content: content, background: background),
              let png = ImageEncoding.png(cg) else { return nil }
        return WallpaperFile(png: png)
    }

    private func saveToPhotos() async {
        guard let file = renderFile() else { return }
        do {
            try await WallpaperRenderer.saveToPhotos(file.png)
            show("Đã lưu vào Ảnh. Vào Cài đặt › Hình nền để đặt cho Lock Screen.")
        } catch {
            show("Không thể lưu: cần quyền thêm ảnh.")
        }
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { toast = nil }
        }
    }
}

/// Small live preview of a template in the gallery, with the "current" badge.
private struct TemplateThumbnail: View {
    let layout: WallpaperConfig.Layout
    let config: WallpaperConfig
    let content: WallpaperContent
    let background: PlatformImage?
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        let canvas = WallpaperRenderer.canvasSize
        let width: CGFloat = 104
        let scale = width / canvas.width
        var preview = config
        preview.layout = layout
        preview.stickers = []
        return Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .top) {
                    WallpaperView(config: preview, content: content, background: background, size: canvas)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: width, height: canvas.height * scale, alignment: .topLeading)
                        .allowsHitTesting(false)
                    MockClock(color: config.foreground, scale: scale)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isCurrent ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isCurrent ? 3 : 1))
                .overlay(alignment: .bottom) {
                    if isCurrent {
                        Text("Hiện tại")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
                Label(layout.label, systemImage: layout.symbol)
                    .font(.caption.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                    .lineLimit(1)
            }
            // The preview ignores hit testing, so give the whole card a tap area.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(layout.label))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Lock Screen clock overlay so the layout can be judged against it.
private struct MockClock: View {
    let color: Color
    let scale: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            VStack(spacing: 0) {
                Text(timeline.date.formatted(.dateTime.weekday(.wide).day().month()))
                    .font(.system(size: 15 * scale * 1.2, weight: .semibold))
                Text(timeline.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))
                    .font(.system(size: 92 * scale * 1.2, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(color.opacity(0.9))
        .padding(.top, 60 * scale)
        .allowsHitTesting(false)
    }
}

/// Placeholder app icons for the Home Screen preview.
private struct MockHomeIcons: View {
    let scale: CGFloat
    let size: CGSize

    var body: some View {
        let icon = 62 * scale
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(icon), spacing: 26 * scale), count: 4), spacing: 30 * scale) {
            ForEach(0..<20, id: \.self) { _ in
                RoundedRectangle(cornerRadius: icon * 0.24, style: .continuous)
                    .fill(.white.opacity(0.35))
                    .frame(width: icon, height: icon)
            }
        }
        .padding(.top, 80 * scale)
        .allowsHitTesting(false)
    }
}

private struct GuideStep: View {
    let n: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            Text(text).font(.subheadline)
        }
    }
}
