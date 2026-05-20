import SwiftUI
import SwiftData

struct ChapterListView: View {
    let book: Book
    let onSelectChapter: (Int) -> Void

    @Query private var chapters: [Chapter]

    init(book: Book, onSelectChapter: @escaping (Int) -> Void) {
        self.book = book
        self.onSelectChapter = onSelectChapter
        let bookId = book.id
        _chapters = Query(
            filter: #Predicate<Chapter> { $0.book?.id == bookId },
            sort: [SortDescriptor(\Chapter.index)]
        )
    }

    var body: some View {
        List(chapters) { chapter in
            Button {
                onSelectChapter(chapter.index)
            } label: {
                HStack {
                    Text(chapter.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    if chapter.isCached {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
