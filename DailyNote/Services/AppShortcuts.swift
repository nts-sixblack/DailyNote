import AppIntents

struct DailyNoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickNoteIntent(),
            phrases: [
                "Ghi nhanh trong \(.applicationName)",
                "Quick note in \(.applicationName)",
                "Take a note with \(.applicationName)",
            ],
            shortTitle: "Ghi nhanh",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Thêm việc vào \(.applicationName)",
                "Add a task to \(.applicationName)",
            ],
            shortTitle: "Thêm việc",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: NewNoteIntent(),
            phrases: [
                "Mở ghi chú mới trong \(.applicationName)",
                "New note in \(.applicationName)",
            ],
            shortTitle: "Ghi chú mới",
            systemImageName: "note.text.badge.plus"
        )
        AppShortcut(
            intent: GenerateLatestWallpaperIntent(),
            phrases: [
                "Tạo hình nền \(.applicationName)",
                "Make my \(.applicationName) wallpaper",
            ],
            shortTitle: "Hình nền Lock Screen",
            systemImageName: "lock.iphone"
        )
    }
}
