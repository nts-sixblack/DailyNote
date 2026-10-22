import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Ghi chú", systemImage: "note.text", value: AppTab.notes) {
                NotesSplitView()
            }
            Tab("Hôm nay", systemImage: "sun.max", value: AppTab.today) {
                NavigationStack { TodayView() }
            }
            Tab("Lịch", systemImage: "calendar", value: AppTab.calendar) {
                NavigationStack { CalendarScreen() }
            }
            Tab("Lock Screen", systemImage: "lock.iphone", value: AppTab.lockScreen) {
                NavigationStack { LockScreenStudioView() }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack { SearchView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
