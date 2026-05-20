import SwiftUI
import SwiftData

struct ChapterListView: View {
    let book: Book

    @Query private var chapters: [Chapter]

    init(book: Book) {
        self.book = book
        let bookId = book.id
        _chapters = Query(
            filter: #Predicate<Chapter> { $0.book?.id == bookId },
            sort: [SortDescriptor(\Chapter.index)]
        )
    }

    var body: some View {
        List(chapters) { chapter in
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
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
