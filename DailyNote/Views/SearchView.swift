import SwiftData
import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Query(filter: #Predicate<Note> { !$0.isTrashed }, sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var query = ""

    private var results: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(notes.prefix(20)) }
        let tag = q.hasPrefix("#") ? String(q.dropFirst()).lowercased() : nil
        return notes.filter { note in
            if let tag { return note.tags.contains { $0.hasPrefix(tag) } }
            return note.title.localizedStandardContains(q)
                || note.body.localizedStandardContains(q)
                || (note.items ?? []).contains { $0.text.localizedStandardContains(q) }
                || (note.folder?.name.localizedStandardContains(q) ?? false)
        }
    }

    var body: some View {
        List(results) { note in
            Button {
                model.open(note)
            } label: {
                NoteRow(note: note)
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle(query.isEmpty ? "Gần đây" : "Kết quả")
        .searchable(text: $query, prompt: "Tìm ghi chú, việc cần làm, #thẻ")
    }
}
