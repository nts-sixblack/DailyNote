import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(AppConstants.Key.weekStartsMonday, store: .shared) private var weekStartsMonday = true
    @AppStorage(AppConstants.Key.todayMarker, store: .shared) private var marker: TodayMarker = .ring
    @AppStorage(AppConstants.Key.defaultAlertMinutes, store: .shared) private var alertMinutes = 15
    @State private var sync = SyncMonitor.shared
    @State private var confirmPurge = false

    var body: some View {
        Form {
            Section {
                Label(sync.statusText, systemImage: sync.symbol)
                if let error = sync.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Text("Ghi chú, thư mục và việc cần làm được đồng bộ qua iCloud trên mọi iPhone, iPad và Mac dùng chung Apple ID.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("iCloud")
            }

            Section("Lịch") {
                Picker("Tuần bắt đầu", selection: $weekStartsMonday) {
                    Text("Thứ Hai").tag(true)
                    Text("Chủ Nhật").tag(false)
                }
                Picker("Đánh dấu hôm nay", selection: $marker) {
                    ForEach(TodayMarker.allCases) { Text($0.label).tag($0) }
                }
                Picker("Báo trước sự kiện", selection: $alertMinutes) {
                    Text("Không").tag(-1)
                    Text("5 phút").tag(5)
                    Text("15 phút").tag(15)
                    Text("30 phút").tag(30)
                }
            }

            Section {
                Button("Dọn ghi chú trong thùng rác quá 30 ngày", role: .destructive) { confirmPurge = true }
            } header: {
                Text("Dữ liệu")
            }

            Section("Giới thiệu") {
                LabeledContent("Phiên bản", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                Text("Mẹo: thêm widget DailyNote vào Lock Screen, Control Center hoặc nút Tác vụ để ghi chú ngay mà không cần mở khoá.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Cài đặt")
        .onChange(of: weekStartsMonday) { DataStore.reloadWidgets() }
        .onChange(of: marker) { DataStore.reloadWidgets() }
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } }
            #endif
        }
        .confirmationDialog("Xoá vĩnh viễn ghi chú cũ trong thùng rác?", isPresented: $confirmPurge, titleVisibility: .visible) {
            Button("Xoá", role: .destructive, action: purge)
        }
        .task { await sync.refreshAccount() }
    }

    private func purge() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let d = FetchDescriptor<Note>(predicate: #Predicate { $0.isTrashed })
        for note in (try? context.fetch(d)) ?? [] where (note.trashedAt ?? .distantPast) < cutoff {
            context.delete(note)
        }
        try? context.save()
    }
}
