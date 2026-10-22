import Photos
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#endif

struct WallpaperConfig: Codable, Equatable {
    enum Position: String, Codable, CaseIterable, Identifiable {
        case middle, bottom
        var id: String { rawValue }
        var label: String { self == .middle ? "Dưới đồng hồ" : "Phía dưới" }
    }

    enum PanelStyle: String, Codable, CaseIterable, Identifiable {
        case glass, solid, clear
        var id: String { rawValue }
        var label: String {
            switch self {
            case .glass: "Kính mờ"
            case .solid: "Thẻ đặc"
            case .clear: "Trong suốt"
            }
        }
    }

    /// Ready-made wallpaper templates, the equivalent of Ink's template gallery.
    enum Layout: String, Codable, CaseIterable, Identifiable {
        case classic, monthEvents, week, timeline, today, matrix, yearProgress, sticky
        var id: String { rawValue }

        var label: String {
            switch self {
            case .classic: "Tổng hợp"
            case .monthEvents: "Lịch tháng"
            case .week: "Tuần này"
            case .timeline: "Dòng thời gian"
            case .today: "Hôm nay"
            case .matrix: "Bảng việc"
            case .yearProgress: "Tiến độ năm"
            case .sticky: "Giấy note"
            }
        }

        var symbol: String {
            switch self {
            case .classic: "square.stack"
            case .monthEvents: "calendar"
            case .week: "calendar.day.timeline.left"
            case .timeline: "list.bullet.below.rectangle"
            case .today: "sun.max"
            case .matrix: "square.grid.2x2"
            case .yearProgress: "hourglass"
            case .sticky: "note.text"
            }
        }

        var category: Category {
            switch self {
            case .classic: .all
            case .monthEvents, .yearProgress: .calendar
            case .week, .timeline, .today: .events
            case .matrix: .tasks
            case .sticky: .notes
            }
        }

        /// Whether the layout needs calendar access to show anything useful.
        var usesCalendar: Bool {
            switch self {
            case .classic, .monthEvents, .week, .timeline, .today: true
            case .matrix, .yearProgress, .sticky: false
            }
        }
    }

    enum Category: String, CaseIterable, Identifiable {
        case all, calendar, events, tasks, notes
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "Tất cả"
            case .calendar: "Lịch"
            case .events: "Sự kiện"
            case .tasks: "Việc cần làm"
            case .notes: "Ghi chú"
            }
        }
    }

    /// What the refresh shortcut does with the Home Screen.
    enum HomeMode: String, Codable, CaseIterable, Identifiable {
        /// Lock Screen and Home Screen get the same image.
        case same
        /// Home Screen gets the background only (no calendar), so app icons stay readable.
        case clean
        /// Only the Lock Screen is replaced.
        case lockOnly
        var id: String { rawValue }
        var label: String {
            switch self {
            case .same: "Giống Lock Screen"
            case .clean: "Chỉ ảnh nền"
            case .lockOnly: "Giữ nguyên"
            }
        }
    }

    struct Sticker: Codable, Equatable, Identifiable {
        var id = UUID()
        var emoji: String
        /// Normalized position inside the canvas (0...1).
        var x: Double
        var y: Double
        var scale: Double = 1
    }

    var layout: Layout = .classic
    var showCalendar = true
    var showAgenda = true
    var showTasks = true
    var showNote = true
    var accentHex = "#FF9455"
    var lightText = true
    var dim: Double = 0.25
    /// Gaussian blur radius applied to the background (points).
    var blur: Double = 0
    var position: Position = .middle
    var panel: PanelStyle = .glass
    var gradientIndex = 0
    var usePhoto = false
    var stickers: [Sticker] = []
    var countdownTitle = ""
    /// Target of the countdown on the "Year progress" template; nil counts down to New Year.
    var countdownDate: Date?

    var homeMode: HomeMode = .clean
    /// Blur radius for the Home Screen image in `.clean` mode.
    var homeBlur: Double = 14
    /// Passes iOS's "Legibility Blur" option to the Set Wallpaper action.
    var legibilityBlur = false
    /// Sets the wallpaper twice, which works around iOS sometimes keeping the old image on screen.
    var redraw = true

    var accent: Color { Color(hex: accentHex) }
    var foreground: Color { lightText ? .white : .black }

    /// Mode string read by the refresh shortcut (`GetWallpaperModeIntent`).
    /// The shortcut tests it with "contains": `same` / `pair`, plus optional `blur` and `redraw` flags.
    var shortcutMode: String {
        var parts = [homeMode == .same ? "same" : homeMode == .clean ? "pair" : "lock"]
        if legibilityBlur { parts.append("blur") }
        if redraw { parts.append("redraw") }
        return parts.joined(separator: "-")
    }

    var countdownTarget: Date {
        if let countdownDate, countdownDate > Calendar.current.startOfDay(for: Date()) { return countdownDate }
        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        return cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
    }

    var countdownLabel: String {
        if !countdownTitle.trimmingCharacters(in: .whitespaces).isEmpty { return countdownTitle }
        return countdownDate == nil ? String(localized: "ngày đến Năm mới") : String(localized: "ngày còn lại")
    }

    static let gradients: [[Color]] = [
        [Color(hex: "#1B1F3B"), Color(hex: "#5B3E96"), Color(hex: "#F28C6B")],
        [Color(hex: "#0F2027"), Color(hex: "#203A43"), Color(hex: "#2C5364")],
        [Color(hex: "#FDEBD0"), Color(hex: "#F8C8DC"), Color(hex: "#C9D6FF")],
        [Color(hex: "#134E5E"), Color(hex: "#71B280")],
        [Color(hex: "#232526"), Color(hex: "#414345")],
        [Color(hex: "#FFE29F"), Color(hex: "#FFA99F"), Color(hex: "#FF719A")],
        [Color(hex: "#F9B35B"), Color(hex: "#F9B35B")],
        [Color(hex: "#A1C4FD"), Color(hex: "#C2E9FB")],
        [Color(hex: "#000000"), Color(hex: "#1C1C1E")],
    ]

    static let stickerPalette = Array("⭐️🌸🍀🦋🌙☀️❤️🎀🐱🐶🍓☁️✨🎧📚☕️🌷🧸🎈🪐").map(String.init)

    static func load() -> WallpaperConfig {
        guard let data = UserDefaults.shared.data(forKey: AppConstants.Key.wallpaperConfig),
              let config = try? JSONDecoder().decode(WallpaperConfig.self, from: data) else { return WallpaperConfig() }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.shared.set(data, forKey: AppConstants.Key.wallpaperConfig)
        }
    }

    static var backgroundURL: URL {
        AppConstants.groupContainerURL.appending(path: "wallpaper-background.jpg")
    }

    static func loadBackground() -> PlatformImage? {
        guard let data = try? Data(contentsOf: backgroundURL) else { return nil }
        return PlatformImage.fromData(data)
    }
}

extension WallpaperConfig {
    /// Tolerant decoding: settings saved by older versions keep working when new fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WallpaperConfig()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        layout = value(.layout, d.layout)
        showCalendar = value(.showCalendar, d.showCalendar)
        showAgenda = value(.showAgenda, d.showAgenda)
        showTasks = value(.showTasks, d.showTasks)
        showNote = value(.showNote, d.showNote)
        accentHex = value(.accentHex, d.accentHex)
        lightText = value(.lightText, d.lightText)
        dim = value(.dim, d.dim)
        blur = value(.blur, d.blur)
        position = value(.position, d.position)
        panel = value(.panel, d.panel)
        gradientIndex = value(.gradientIndex, d.gradientIndex)
        usePhoto = value(.usePhoto, d.usePhoto)
        stickers = value(.stickers, d.stickers)
        countdownTitle = value(.countdownTitle, d.countdownTitle)
        countdownDate = try? c.decodeIfPresent(Date.self, forKey: .countdownDate)
        homeMode = value(.homeMode, d.homeMode)
        homeBlur = value(.homeBlur, d.homeBlur)
        legibilityBlur = value(.legibilityBlur, d.legibilityBlur)
        redraw = value(.redraw, d.redraw)
    }
}

/// Data shown on the wallpaper, captured from SwiftData + EventKit.
struct WallpaperContent {
    struct TaskLine: Identifiable { let id: UUID; let text: String; let isDone: Bool; let due: Date? }

    var events: [AgendaEvent] = []
    /// Events covering the visible month grid and the next week, for the calendar templates.
    var rangeEvents: [AgendaEvent] = []
    var tasks: [TaskLine] = []
    var doneTasks: [TaskLine] = []
    var noteTitle: String?
    var noteBody: String?
    var noteItems: [TaskLine] = []
    var busyDays: Set<Date> = []
    var date = Date()

    @MainActor
    static func current(context: ModelContext) -> WallpaperContent {
        var content = WallpaperContent()
        let cal = CalendarPrefs.calendar
        content.events = CalendarStore.upcoming(limit: 4, days: 2)
        content.busyDays = CalendarStore.busyDays(inMonthOf: Date(), calendar: cal)
        if let month = cal.dateInterval(of: .month, for: Date()),
           let week = cal.dateInterval(of: .weekOfYear, for: Date()) {
            let start = min(month.start, week.start)
            let end = max(month.end, cal.date(byAdding: .day, value: 8, to: week.start)!)
            content.rangeEvents = CalendarStore.events(from: start, to: end)
        }
        content.tasks = context.openTasks(limit: 8).map(TaskLine.init)
        content.doneTasks = context.recentlyCompletedTasks(limit: 4).map(TaskLine.init)
        if let note = context.lockScreenNotes().first(where: { !$0.body.isEmpty || !$0.title.isEmpty || $0.hasChecklist }) {
            content.noteTitle = note.displayTitle
            content.noteBody = note.bodyBelowTitle
            content.noteItems = note.sortedItems.map(TaskLine.init)
        }
        return content
    }

    /// Events that overlap the given day.
    func events(on day: Date, calendar: Calendar = CalendarPrefs.calendar) -> [AgendaEvent] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return rangeEvents.filter { $0.start < end && $0.end > start }
    }

    /// Sample content so templates look right in the gallery before the user has data.
    static var sample: WallpaperContent {
        var c = WallpaperContent()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(byAdding: .minute, value: (day * 24 + hour) * 60 + minute, to: today)!
        }
        let palette: [[Double]] = [[0.98, 0.55, 0.33], [0.36, 0.62, 0.98], [0.45, 0.80, 0.52], [0.80, 0.50, 0.95]]
        let samples: [(String, Int, Int, Int)] = [
            ("Tập thể dục", 0, 6, 1), ("Họp nhóm", 0, 9, 2), ("Ăn trưa với Lan", 0, 12, 3),
            ("Nộp báo cáo", 1, 10, 0), ("Học tiếng Anh", 2, 19, 1), ("Yoga", 3, 7, 2), ("Xem phim", 5, 20, 3),
        ]
        c.rangeEvents = samples.enumerated().map { i, s in
            AgendaEvent(id: "sample-\(i)", title: s.0, start: at(s.1, s.2), end: at(s.1, s.2 + 1), isAllDay: false,
                        location: nil, notes: nil, calendarTitle: "", colorComponents: palette[s.3])
        }
        c.events = Array(c.rangeEvents.prefix(3))
        c.busyDays = Set(c.rangeEvents.map { cal.startOfDay(for: $0.start) })
        let lines = ["Mua đồ ăn cả tuần", "Gọi cho mẹ", "Trả tiền điện", "Đọc 10 trang sách"]
        c.tasks = lines.enumerated().map { i, t in
            TaskLine(id: UUID(), text: t, isDone: false, due: i < 2 ? today : (i == 2 ? at(2, 9) : nil))
        }
        c.doneTasks = [TaskLine(id: UUID(), text: "Giặt đồ", isDone: true, due: nil)]
        c.noteTitle = "Việc cần làm"
        c.noteBody = ""
        c.noteItems = c.tasks + c.doneTasks
        return c
    }
}

extension WallpaperContent.TaskLine {
    init(_ item: ChecklistItem) {
        self.init(id: item.id, text: item.text, isDone: item.isDone, due: item.dueDate)
    }
}

struct WallpaperView: View {
    let config: WallpaperConfig
    let content: WallpaperContent
    let background: PlatformImage?
    let size: CGSize
    var onMoveSticker: ((UUID, CGPoint) -> Void)?
    var onRemoveSticker: ((UUID) -> Void)?

    var body: some View {
        ZStack(alignment: .top) {
            WallpaperBackground(config: config, background: background, size: size, blur: config.blur)
            (config.lightText ? Color.black : Color.white).opacity(config.dim)

            VStack(spacing: 0) {
                if config.position == .middle {
                    Spacer().frame(height: size.height * 0.34)
                } else {
                    Spacer()
                }
                WallpaperLayoutView(config: config, content: content, size: size)
                    .padding(.horizontal, 20)
                if config.position == .middle {
                    Spacer(minLength: size.height * 0.14)
                } else {
                    Spacer().frame(height: size.height * 0.15)
                }
            }

            ForEach(config.stickers) { sticker in
                StickerView(sticker: sticker, canvas: size, onMove: onMoveSticker, onRemove: onRemoveSticker)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .environment(\.colorScheme, config.lightText ? .dark : .light)
    }
}

/// Home Screen companion: the same background without any overlays, blurred so icons stay readable.
struct HomeWallpaperView: View {
    let config: WallpaperConfig
    let background: PlatformImage?
    let size: CGSize

    var body: some View {
        ZStack {
            WallpaperBackground(config: config, background: background, size: size, blur: max(config.blur, config.homeBlur))
            (config.lightText ? Color.black : Color.white).opacity(config.dim * 0.6)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

struct WallpaperBackground: View {
    let config: WallpaperConfig
    let background: PlatformImage?
    let size: CGSize
    let blur: Double

    var body: some View {
        Group {
            if config.usePhoto, let background {
                Image(platformImage: background)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                let colors = WallpaperConfig.gradients[config.gradientIndex % WallpaperConfig.gradients.count]
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        // Opaque blur keeps the edges from fading to transparent.
        .blur(radius: blur, opaque: true)
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

private struct StickerView: View {
    let sticker: WallpaperConfig.Sticker
    let canvas: CGSize
    var onMove: ((UUID, CGPoint) -> Void)?
    var onRemove: ((UUID) -> Void)?
    @State private var drag: CGSize = .zero

    var body: some View {
        Text(sticker.emoji)
            .font(.system(size: 44 * sticker.scale))
            .position(x: sticker.x * canvas.width + drag.width, y: sticker.y * canvas.height + drag.height)
            .gesture(onMove == nil ? nil : DragGesture()
                .onChanged { drag = $0.translation }
                .onEnded { value in
                    let x = min(max(sticker.x + value.translation.width / canvas.width, 0), 1)
                    let y = min(max(sticker.y + value.translation.height / canvas.height, 0), 1)
                    drag = .zero
                    onMove?(sticker.id, CGPoint(x: x, y: y))
                })
            .onTapGesture(count: 2) { onRemove?(sticker.id) }
    }
}

// MARK: - Rendering

@MainActor
enum WallpaperRenderer {
    private struct Canvas: Codable { var width: Double; var height: Double; var scale: Double }

    /// Remembers the device screen while the app is in the foreground. Shortcuts may launch the app
    /// in the background without a window scene, and the wallpaper must still match the screen.
    static func rememberScreen() {
        #if os(iOS)
        guard let screen = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.screen }).first else { return }
        let b = screen.bounds.size
        let canvas = Canvas(width: min(b.width, b.height), height: max(b.width, b.height), scale: screen.scale)
        if let data = try? JSONEncoder().encode(canvas) {
            UserDefaults.shared.set(data, forKey: AppConstants.Key.wallpaperCanvas)
        }
        #endif
    }

    private static var savedCanvas: Canvas? {
        guard let data = UserDefaults.shared.data(forKey: AppConstants.Key.wallpaperCanvas) else { return nil }
        return try? JSONDecoder().decode(Canvas.self, from: data)
    }

    static var canvasSize: CGSize {
        #if os(iOS)
        if let screen = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.screen }).first {
            let b = screen.bounds.size
            return CGSize(width: min(b.width, b.height), height: max(b.width, b.height))
        }
        #endif
        if let saved = savedCanvas { return CGSize(width: saved.width, height: saved.height) }
        return CGSize(width: 402, height: 874)
    }

    static var renderScale: CGFloat {
        savedCanvas.map { CGFloat($0.scale) } ?? 3
    }

    static func render(config: WallpaperConfig, content: WallpaperContent, background: PlatformImage?) -> CGImage? {
        let size = canvasSize
        return render(WallpaperView(config: config, content: content, background: background, size: size), size: size)
    }

    static func renderHome(config: WallpaperConfig, background: PlatformImage?) -> CGImage? {
        let size = canvasSize
        return render(HomeWallpaperView(config: config, background: background, size: size), size: size)
    }

    private static func render(_ view: some View, size: CGSize) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = renderScale
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.cgImage
    }

    static func renderPNG(context: ModelContext) -> Data? {
        let config = WallpaperConfig.load()
        let content = WallpaperContent.current(context: context)
        guard let cg = render(config: config, content: content, background: WallpaperConfig.loadBackground()) else { return nil }
        return ImageEncoding.png(cg)
    }

    /// Home Screen image for the current mode: the clean background, or the Lock Screen image itself.
    static func renderHomePNG(context: ModelContext) -> Data? {
        let config = WallpaperConfig.load()
        if config.homeMode == .same { return renderPNG(context: context) }
        guard let cg = renderHome(config: config, background: WallpaperConfig.loadBackground()) else { return nil }
        return ImageEncoding.png(cg)
    }

    static func saveToPhotos(_ png: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw CocoaError(.userCancelled)
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: nil)
        }
    }
}

struct WallpaperFile: Transferable {
    let png: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName("DailyNote-LockScreen.png")
    }
}
