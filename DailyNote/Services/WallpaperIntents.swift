import AppIntents
import Foundation
import SwiftData
import UniformTypeIdentifiers

// The bundled "DailyNote Lock Screen" shortcut chains these actions (see Tools/make_shortcut.py):
//   Get Wallpaper Mode → Generate Latest Wallpaper → Get All Wallpapers → Get DailyNote Wallpaper Slot
//   → Set Wallpaper (updating DailyNote's existing wallpaper when the slot is known, otherwise a new one) [→ redraw]
//   → [Generate Home Screen Wallpaper → Set Wallpaper (Home)] → Switch Wallpaper → Confirm Wallpaper Applied
// The shortcut refers to the intents by type name, so keep these names stable.

/// Tells the shortcut how to apply the wallpaper. See `WallpaperConfig.shortcutMode`.
struct GetWallpaperModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Lấy chế độ hình nền"
    static let description = IntentDescription("Cho phím tắt biết cách đặt hình nền: giống nhau cho Lock Screen và Màn hình chính (same), Màn hình chính riêng (pair), làm mờ (blur) và vẽ lại (redraw).")

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: WallpaperConfig.load().shortcutMode)
    }
}

/// Finds DailyNote's wallpaper among all wallpapers so the shortcut updates it instead of adding a new one each run.
/// Shortcuts turns every wallpaper into the text "Wallpaper", so only the list size and position are usable:
/// the remembered position is trusted only while the number of wallpapers is unchanged.
struct GetWallpaperSlotIntent: AppIntent {
    static let title: LocalizedStringResource = "Tìm hình nền DailyNote"
    static let description = IntentDescription("Trả về vị trí hình nền DailyNote trong danh sách hình nền (0 nếu cần tạo mới).")

    @Parameter(title: "Hình nền")
    var wallpapers: [String]

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        .result(value: WallpaperAutomation.slot(forWallpaperCount: wallpapers.count))
    }
}

/// Renders the Lock Screen wallpaper so a Shortcuts automation can pipe it into "Set Wallpaper".
struct GenerateLatestWallpaperIntent: AppIntent {
    static let title: LocalizedStringResource = "Tạo hình nền Lock Screen"
    static let description = IntentDescription("Vẽ lịch, việc cần làm và ghi chú hiện tại lên hình nền theo mẫu bạn đã chọn trong DailyNote.")

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let png = await MainActor.run {
            WallpaperRenderer.renderPNG(context: DataStore.container.mainContext)
        }
        guard let png else { throw CocoaError(.fileWriteUnknown) }
        return .result(value: IntentFile(data: png, filename: "DailyNote-LockScreen.png", type: .png))
    }
}

/// Home Screen companion image: the background without the calendar, blurred so icons stay readable.
struct GenerateHomeScreenWallpaperIntent: AppIntent {
    static let title: LocalizedStringResource = "Tạo hình nền Màn hình chính"
    static let description = IntentDescription("Tạo ảnh nền cho Màn hình chính đi kèm hình nền Lock Screen của DailyNote.")

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let png = await MainActor.run {
            WallpaperRenderer.renderHomePNG(context: DataStore.container.mainContext)
        }
        guard let png else { throw CocoaError(.fileWriteUnknown) }
        return .result(value: IntentFile(data: png, filename: "DailyNote-HomeScreen.png", type: .png))
    }
}

/// Last step of the shortcut, so the app knows the automation works.
struct ConfirmWallpaperAppliedIntent: AppIntent {
    static let title: LocalizedStringResource = "Xác nhận đã đặt hình nền"
    static let description = IntentDescription("Ghi lại thời điểm hình nền được cập nhật để DailyNote hiển thị trạng thái tự động hoá.")

    init() {}

    func perform() async throws -> some IntentResult {
        WallpaperAutomation.markApplied()
        return .result()
    }
}

/// Everything the app needs to install, run and monitor the refresh shortcut.
enum WallpaperAutomation {
    /// Name of the bundled shortcut. `shortcuts://run-shortcut` looks it up by this name.
    static let shortcutName = "DailyNote Lock Screen"

    /// Optional iCloud link to the same shortcut (Shortcuts › Share › Copy iCloud Link).
    /// When set, "Add shortcut" opens it directly instead of sharing the bundled file.
    static let iCloudLink: URL? = nil

    static var bundledShortcutURL: URL? {
        Bundle.main.url(forResource: shortcutName, withExtension: "shortcut")
    }

    /// Runs the shortcut and comes back to the Lock Screen tab when it finishes;
    /// if it fails (e.g. the shortcut isn't installed) the app opens the setup guide.
    static var runURL: URL {
        var c = URLComponents(string: "shortcuts://x-callback-url/run-shortcut")!
        c.queryItems = [
            URLQueryItem(name: "name", value: shortcutName),
            URLQueryItem(name: "x-success", value: callbackURL(.lockScreen)),
            URLQueryItem(name: "x-error", value: callbackURL(.lockScreenSetup)),
        ]
        return c.url!
    }

    static let shortcutsAppURL = URL(string: "shortcuts://")!

    private static func callbackURL(_ link: DeepLink) -> String {
        var c = URLComponents(url: link.url, resolvingAgainstBaseURL: false)!
        c.scheme = AppConstants.callbackScheme
        return c.url!.absoluteString
    }

    static var lastApplied: Date? {
        UserDefaults.shared.object(forKey: AppConstants.Key.wallpaperAppliedAt) as? Date
    }

    static var appliedCount: Int {
        UserDefaults.shared.integer(forKey: AppConstants.Key.wallpaperAppliedCount)
    }

    /// True once the shortcut has run successfully at least once.
    static var isInstalled: Bool { lastApplied != nil }

    /// The automation is considered stale when the wallpaper wasn't refreshed for more than a day.
    static var isStale: Bool {
        guard let lastApplied else { return false }
        return Date().timeIntervalSince(lastApplied) > 26 * 3600
    }

    static func markApplied() {
        let d = UserDefaults.shared
        d.set(Date(), forKey: AppConstants.Key.wallpaperAppliedAt)
        d.set(appliedCount + 1, forKey: AppConstants.Key.wallpaperAppliedCount)
        let index = d.integer(forKey: AppConstants.Key.wallpaperPendingIndex)
        if index > 0 {
            d.set(index, forKey: AppConstants.Key.wallpaperPosterIndex)
            d.set(d.integer(forKey: AppConstants.Key.wallpaperPendingTotal), forKey: AppConstants.Key.wallpaperPosterTotal)
            d.removeObject(forKey: AppConstants.Key.wallpaperPendingIndex)
            d.removeObject(forKey: AppConstants.Key.wallpaperPendingTotal)
        }
    }

    /// 1-based position of DailyNote's wallpaper to update, or 0 to create a new one.
    /// New wallpapers are appended to the end of the list, so a new one will sit at `count + 1`.
    static func slot(forWallpaperCount count: Int) -> Int {
        let d = UserDefaults.shared
        let index = d.integer(forKey: AppConstants.Key.wallpaperPosterIndex)
        let total = d.integer(forKey: AppConstants.Key.wallpaperPosterTotal)
        let reuse = index > 0 && total == count && index <= count
        d.set(reuse ? index : count + 1, forKey: AppConstants.Key.wallpaperPendingIndex)
        d.set(reuse ? count : count + 1, forKey: AppConstants.Key.wallpaperPendingTotal)
        return reuse ? index : 0
    }
}
