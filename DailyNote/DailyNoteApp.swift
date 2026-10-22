//
//  DailyNoteApp.swift
//  DailyNote
//
//  Created by Thanh Sau on 21/10/26.
//

import SwiftData
import SwiftUI

@main
struct DailyNoteApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NotificationService.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(model.storeGeneration)
                .environment(model)
                .onOpenURL { url in
                    if let link = DeepLink(url: url) {
                        model.handle(link, context: model.context)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .dailyNotePendingAction)) { _ in
                    model.consumePendingAction(context: model.context)
                }
                .task {
                    NotificationService.shared.onOpenNote = { id in
                        model.handle(.note(id), context: model.context)
                    }
                    NotificationService.shared.onRoutine = { id, day, markDone in
                        if markDone, let routine = model.context.routine(id: id) {
                            routine.setDone(true, on: day, in: model.context)
                            model.scheduleWidgetReload(context: model.context, delay: .zero)
                        } else {
                            model.tab = .today
                        }
                    }
                    SyncMonitor.shared.start {
                        model.scheduleWidgetReload(context: model.context, delay: .seconds(2))
                    }
                    model.consumePendingAction(context: model.context)
                }
        }
        .modelContainer(DataStore.container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.reloadIfStoreChangedExternally()
                model.context.moveJournalTasksToInbox()
                model.consumePendingAction(context: model.context)
                RoutineReminders.reschedule(context: model.context)
                WallpaperRenderer.rememberScreen()
                Task { await SyncMonitor.shared.refreshAccount() }
            case .background, .inactive:
                try? model.context.save()
                DataStore.reloadWidgets()
            @unknown default: break
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Ghi chú mới") { model.createNote(in: model.context) }
                    .keyboardShortcut("n")
                Button("Danh sách việc mới") { model.createNote(in: model.context, checklist: true) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandMenu("Đi tới") {
                Button("Ghi chú") { model.tab = .notes }.keyboardShortcut("1")
                Button("Hôm nay") { model.tab = .today }.keyboardShortcut("2")
                Button("Lịch") { model.tab = .calendar }.keyboardShortcut("3")
                Button("Lock Screen") { model.tab = .lockScreen }.keyboardShortcut("4")
                Button("Tìm kiếm") { model.tab = .search }.keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .frame(width: 480, height: 520)
                .modelContainer(DataStore.container)
        }
        #endif
    }
}
