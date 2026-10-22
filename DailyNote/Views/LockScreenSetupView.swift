import SwiftUI

/// Step-by-step guide for the refresh shortcut and its automations (iOS can't change wallpapers from an app,
/// so a Shortcuts automation regenerates and applies it on a schedule).
struct LockScreenSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastApplied = WallpaperAutomation.lastApplied
    @State private var recipe: AutomationRecipe = .daily

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    step(1, "Thêm phím tắt", done: lastApplied != nil) { addShortcutStep }
                    step(2, "Chạy thử một lần", done: lastApplied != nil) { runOnceStep }
                    step(3, "Tạo tự động hoá", done: false) { automationStep }
                    tips
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Tự động cập nhật")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { lastApplied = WallpaperAutomation.lastApplied }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.iphone")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(LinearGradient(colors: [Color(hex: "#FF9455"), Color(hex: "#FF5E7E")],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("Hình nền luôn mới").font(.title3.bold())
                Text("iOS không cho ứng dụng tự đổi hình nền. DailyNote dùng app Phím tắt để vẽ lại lịch, việc cần làm và ghi chú lên hình nền rồi đặt cho Lock Screen — hoàn toàn tự động sau khi thiết lập một lần.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Step 1

    @ViewBuilder
    private var addShortcutStep: some View {
        Text("Phím tắt “\(WallpaperAutomation.shortcutName)” tạo hình nền mới từ DailyNote và đặt nó cho Lock Screen (và Màn hình chính nếu bạn chọn).")
            .font(.subheadline)
        if let link = WallpaperAutomation.iCloudLink {
            Button {
                openURL(link)
            } label: {
                Label("Thêm phím tắt", systemImage: "plus.square.on.square").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else if let file = WallpaperAutomation.bundledShortcutURL {
            ShareLink(item: file, preview: SharePreview(WallpaperAutomation.shortcutName, image: Image(systemName: "square.2.layers.3d"))) {
                Label("Thêm phím tắt", systemImage: "plus.square.on.square").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Hint("Trong bảng chia sẻ, chọn **Phím tắt** (Shortcuts) rồi chạm **Thêm phím tắt**. Không thấy Phím tắt? Kéo hàng ứng dụng sang phải và chạm **Thêm**.")
        }
    }

    // MARK: Step 2

    @ViewBuilder
    private var runOnceStep: some View {
        Text("Chạy thử để cấp quyền. Lần đầu iOS hỏi hai lần: cho phép phím tắt **chạy tác vụ từ DailyNote** và **đặt hình nền** — chọn **Cho phép** cả hai. Từ lần sau phím tắt chạy không cần hỏi.")
            .font(.subheadline)
        Button {
            openURL(WallpaperAutomation.runURL)
        } label: {
            Label("Chạy phím tắt ngay", systemImage: "play.fill").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        if let lastApplied {
            Label("Đã cập nhật hình nền lúc \(lastApplied.formatted(date: .abbreviated, time: .shortened))", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
        } else {
            Hint("Sau khi chạy xong, Phím tắt sẽ đưa bạn quay lại đây và bước này được đánh dấu hoàn tất.")
        }
    }

    // MARK: Step 3

    @ViewBuilder
    private var automationStep: some View {
        Text("Tự động hoá chạy phím tắt theo lịch, để hình nền luôn khớp với ngày hôm nay. Nên tạo cả ba:")
            .font(.subheadline)
        Picker("Kiểu tự động hoá", selection: $recipe) {
            ForEach(AutomationRecipe.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)

        Text(recipe.purpose).font(.subheadline).foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, text in
                GuideRow(n: i + 1, text: text)
            }
        }

        AutomationMock(recipe: recipe)

        Button {
            openURL(WallpaperAutomation.shortcutsAppURL)
        } label: {
            Label("Mở Phím tắt", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    // MARK: Tips

    private var tips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mẹo & khắc phục sự cố").font(.headline)
            Tip(symbol: "arrow.triangle.2.circlepath", title: "Hình nền không đổi?",
                text: "Bật “Vẽ lại hai lần” trong mục Màn hình chính của Lock Screen Studio. iOS đôi khi giữ ảnh cũ cho đến khi hình nền được đặt lại.")
            Tip(symbol: "bell.slash", title: "Bị hỏi xác nhận mỗi lần?",
                text: "Mở lại tự động hoá, chọn “Chạy ngay lập tức” và tắt “Thông báo khi chạy”. Chạy phím tắt thủ công một lần và chọn “Cho phép” ở cả hai hộp thoại.")
            Tip(symbol: "square.stack.3d.up", title: "Có quá nhiều hình nền?",
                text: "Phím tắt cập nhật lại đúng hình nền DailyNote đã tạo thay vì thêm mới. Nếu bạn thêm hoặc xoá hình nền khác, lần chạy kế tiếp sẽ tạo một hình nền DailyNote mới để không ghi đè ảnh của bạn — xoá bản cũ bằng cách giữ Lock Screen, vuốt lên trên hình nền và chạm thùng rác.")
            Tip(symbol: "arrow.down.circle", title: "Vừa cài lại hoặc cập nhật phím tắt?",
                text: "iOS hỏi lại quyền sau khi phím tắt được thay thế. Chạy phím tắt thủ công một lần và chọn “Cho phép”, nếu không tự động hoá sẽ chạy thất bại trong im lặng.")
            Tip(symbol: "calendar.badge.exclamationmark", title: "Không thấy sự kiện?",
                text: "Cho phép DailyNote truy cập Lịch. Google Calendar sẽ hiện nếu bạn đã thêm tài khoản Google trong Cài đặt › Lịch.")
            Tip(symbol: "iphone.gen3", title: "Hình bị lệch kích thước?",
                text: "Mở DailyNote một lần trên máy đó để ứng dụng ghi nhớ kích thước màn hình, rồi chạy lại phím tắt.")
        }
    }

    // MARK: Building blocks

    private func step(_ n: Int, _ title: LocalizedStringKey, done: Bool, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(done ? Color.green : Color.accentColor)
                    if done {
                        Image(systemName: "checkmark").font(.caption.bold())
                    } else {
                        Text("\(n)").font(.subheadline.bold())
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                Text(title).font(.headline)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

enum AutomationRecipe: String, CaseIterable, Identifiable {
    case daily, sunset, appClosed
    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .daily: "Hằng ngày"
        case .sunset: "Hoàng hôn"
        case .appClosed: "Khi đóng app"
        }
    }

    var purpose: LocalizedStringKey {
        switch self {
        case .daily: "Cập nhật lúc nửa đêm để Lock Screen chuyển sang ngày mới, và thêm một lần buổi sáng."
        case .sunset: "Cập nhật lúc hoàng hôn để thấy lịch tối nay và ngày mai — giờ tự đổi theo mùa và vị trí của bạn."
        case .appClosed: "Cập nhật ngay sau khi bạn thêm việc, sửa ghi chú hay sự kiện trong DailyNote."
        }
    }

    var trigger: LocalizedStringKey {
        switch self {
        case .daily, .sunset: "Thời gian trong ngày (Time of Day)"
        case .appClosed: "Ứng dụng (App)"
        }
    }

    var steps: [LocalizedStringKey] {
        let start: [LocalizedStringKey] = [
            "Mở **Phím tắt** › tab **Tự động hoá** (Automation) › chạm **+** (hoặc **Tạo tự động hoá cá nhân**).",
        ]
        let finish: [LocalizedStringKey] = [
            "Chọn **Chạy ngay lập tức** (Run Immediately) thay vì “Chạy sau khi xác nhận”.",
            "Tắt **Thông báo khi chạy** (Notify When Run), rồi chạm **Tiếp**.",
            "Chọn phím tắt **\(WallpaperAutomation.shortcutName)** — xong!",
        ]
        let middle: [LocalizedStringKey] = switch self {
        case .daily: [
            "Chọn **Thời gian trong ngày** (Time of Day).",
            "Chọn giờ cụ thể và đặt **0:01** (tạo thêm một tự động hoá giống vậy lúc **6:00** cho buổi sáng).",
            "Ở **Lặp lại** (Repeat) chọn **Hằng ngày** (Daily).",
        ]
        case .sunset: [
            "Chọn **Thời gian trong ngày** (Time of Day).",
            "Chọn **Hoàng hôn** (Sunset) › **Lúc hoàng hôn** (At Sunset). Muốn sớm hơn, chọn “Trước hoàng hôn” 15 phút.",
            "Ở **Lặp lại** (Repeat) chọn **Hằng ngày** (Daily).",
        ]
        case .appClosed: [
            "Chọn **Ứng dụng** (App).",
            "Chạm **Chọn** › **DailyNote**, chọn **Đã đóng** (Is Closed) và bỏ chọn **Đã mở** (Is Opened).",
        ]
        }
        return start + middle + finish
    }

    var mockRows: [(LocalizedStringKey, LocalizedStringKey)] {
        switch self {
        case .daily: [("Thời gian trong ngày", "0:01"), ("Lặp lại", "Hằng ngày")]
        case .sunset: [("Thời gian trong ngày", "Lúc hoàng hôn"), ("Lặp lại", "Hằng ngày")]
        case .appClosed: [("Ứng dụng", "DailyNote"), ("Khi", "Đã đóng")]
        }
    }
}

/// A drawing of the iOS automation sheet, highlighting the options that matter.
private struct AutomationMock: View {
    let recipe: AutomationRecipe

    var body: some View {
        VStack(spacing: 0) {
            Text(recipe.trigger)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            VStack(spacing: 0) {
                ForEach(Array(recipe.mockRows.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.0)
                        Spacer()
                        Text(row.1).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    Divider().padding(.leading, 14)
                }
                option("Chạy sau khi xác nhận", selected: false)
                Divider().padding(.leading, 14)
                option("Chạy ngay lập tức", selected: true)
                    .background(Color.accentColor.opacity(0.12))
                Divider().padding(.leading, 14)
                HStack {
                    Text("Thông báo khi chạy")
                    Spacer()
                    Capsule().fill(Color.gray.opacity(0.35))
                        .frame(width: 44, height: 26)
                        .overlay(alignment: .leading) { Circle().fill(.white).padding(2) }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.12))
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding([.horizontal, .bottom], 10)
        }
        .font(.subheadline)
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.quaternary))
    }

    private func option(_ title: LocalizedStringKey, selected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

private struct GuideRow: View {
    let n: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text).font(.subheadline)
        }
    }
}

private struct Hint: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Label { Text(text) } icon: { Image(systemName: "lightbulb") }
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

private struct Tip: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        DisclosureGroup {
            Text(text).font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Label(title, systemImage: symbol).font(.subheadline.weight(.medium))
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
