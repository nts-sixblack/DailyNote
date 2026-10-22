import AppIntents
import SwiftUI
import WidgetKit

@main
struct DailyNoteWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayTasksWidget()
        NoteWidget()
        ChecklistWidget()
        AgendaWidget()
        DateWidget()
        #if os(iOS)
        QuickNoteControl()
        QuickChecklistControl()
        #endif
    }
}

#if os(iOS)
/// Lock Screen / Control Center / Action button control that jumps straight into a new note.
struct QuickNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "DailyNote.QuickNoteControl") {
            ControlWidgetButton(action: NewNoteIntent()) {
                Label("Ghi chú nhanh", systemImage: "square.and.pencil")
            }
        }
        .displayName("Ghi chú nhanh")
        .description("Mở DailyNote và bắt đầu viết ngay.")
    }
}

struct QuickChecklistControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "DailyNote.QuickChecklistControl") {
            ControlWidgetButton(action: NewNoteIntent(checklist: true)) {
                Label("Việc cần làm mới", systemImage: "checklist")
            }
        }
        .displayName("Việc cần làm mới")
        .description("Tạo danh sách việc cần làm mới.")
    }
}
#endif
