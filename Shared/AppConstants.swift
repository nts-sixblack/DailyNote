import Foundation

enum AppConstants {
    static let appGroup = "group.com.sixpilot.DaillyNote"
    static let cloudContainer = "iCloud.com.sixpilot.DaillyNote"
    static let urlScheme = "dailynote"
    /// Bundle-specific scheme for Shortcuts callbacks, so another app claiming "dailynote" can't catch them.
    static let callbackScheme = "com.sixpilot.daillynote"

    /// Widget kinds, shared so the app can reload specific timelines.
    enum WidgetKind {
        static let note = "DailyNote.NoteWidget"
        static let checklist = "DailyNote.ChecklistWidget"
        static let agenda = "DailyNote.AgendaWidget"
        static let date = "DailyNote.DateWidget"
        static let today = "DailyNote.TodayTasksWidget"
    }

    /// Keys stored in the shared App Group defaults.
    enum Key {
        static let pendingAction = "pendingAction"
        static let weekStartsMonday = "weekStartsMonday"
        static let todayMarker = "todayMarker"
        static let wallpaperConfig = "wallpaperConfig"
        /// Set by the "Confirm Wallpaper Applied" action at the end of the refresh shortcut.
        static let wallpaperAppliedAt = "wallpaperAppliedAt"
        static let wallpaperAppliedCount = "wallpaperAppliedCount"
        /// Position (1-based) of DailyNote's wallpaper in Shortcuts' "Get All Wallpapers" list, and the list size then.
        static let wallpaperPosterIndex = "wallpaperPosterIndex"
        static let wallpaperPosterTotal = "wallpaperPosterTotal"
        /// Slot chosen by the current run, committed by "Confirm Wallpaper Applied".
        static let wallpaperPendingIndex = "wallpaperPendingIndex"
        static let wallpaperPendingTotal = "wallpaperPendingTotal"
        /// Last known screen size (points) and scale, so Shortcuts runs in the background render at the right size.
        static let wallpaperCanvas = "wallpaperCanvas"
        static let defaultAlertMinutes = "defaultAlertMinutes"
        static let lastExternalWrite = "lastExternalWrite"
    }

    static var isExtension: Bool {
        Bundle.main.bundlePath.hasSuffix(".appex")
    }

    static var groupContainerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? URL.applicationSupportDirectory
    }
}

extension UserDefaults {
    static let shared: UserDefaults = UserDefaults(suiteName: AppConstants.appGroup) ?? .standard
}

/// Deep links understood by the app: `dailynote://new[?text=…]`, `dailynote://note/<uuid>`, `dailynote://today`.
enum DeepLink: Equatable {
    case newNote
    /// Saves a note with the given text without opening the editor (for Shortcuts / automation).
    case capture(String)
    case newChecklist
    case note(UUID)
    case today
    case calendar
    case lockScreen
    case lockScreenSetup

    var url: URL {
        switch self {
        case .newNote: URL(string: "\(AppConstants.urlScheme)://new")!
        case .capture(let text):
            {
                var c = URLComponents(string: "\(AppConstants.urlScheme)://new")!
                c.queryItems = [URLQueryItem(name: "text", value: text)]
                return c.url!
            }()
        case .newChecklist: URL(string: "\(AppConstants.urlScheme)://new-checklist")!
        case .note(let id): URL(string: "\(AppConstants.urlScheme)://note/\(id.uuidString)")!
        case .today: URL(string: "\(AppConstants.urlScheme)://today")!
        case .calendar: URL(string: "\(AppConstants.urlScheme)://calendar")!
        case .lockScreen: URL(string: "\(AppConstants.urlScheme)://lockscreen")!
        case .lockScreenSetup: URL(string: "\(AppConstants.urlScheme)://lockscreen-setup")!
        }
    }

    init?(url: URL) {
        guard url.scheme == AppConstants.urlScheme || url.scheme == AppConstants.callbackScheme else { return nil }
        switch url.host() {
        case "new":
            let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "text" })?.value
            if let text, !text.isEmpty { self = .capture(text) } else { self = .newNote }
        case "new-checklist": self = .newChecklist
        case "today": self = .today
        case "calendar": self = .calendar
        case "lockscreen": self = .lockScreen
        case "lockscreen-setup": self = .lockScreenSetup
        case "note":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            self = .note(id)
        default: return nil
        }
    }
}

enum TodayMarker: String, CaseIterable, Identifiable, Codable {
    case dot, ring, square
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dot: "Chấm"
        case .ring: "Vòng"
        case .square: "Ô vuông"
        }
    }
}

enum CalendarPrefs {
    static var weekStartsMonday: Bool {
        get { UserDefaults.shared.object(forKey: AppConstants.Key.weekStartsMonday) as? Bool ?? true }
        set { UserDefaults.shared.set(newValue, forKey: AppConstants.Key.weekStartsMonday) }
    }
    static var todayMarker: TodayMarker {
        get { TodayMarker(rawValue: UserDefaults.shared.string(forKey: AppConstants.Key.todayMarker) ?? "") ?? .ring }
        set { UserDefaults.shared.set(newValue.rawValue, forKey: AppConstants.Key.todayMarker) }
    }
    static var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = weekStartsMonday ? 2 : 1
        return cal
    }
}
