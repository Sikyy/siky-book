import Foundation
import SwiftData

class BookManager {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func addBook(title: String, author: String, sourceType: SourceType) -> Book {
        let book = Book(title: title, author: author, sourceType: sourceType)
        modelContext.insert(book)
        return book
    }

    func deleteBook(_ book: Book) {
        modelContext.delete(book)
    }

    func updateProgress(book: Book, chapterIndex: Int, position: Double) {
        book.lastReadChapterIndex = chapterIndex
        book.lastReadPosition = position
        book.lastReadDate = Date()

        if chapterIndex >= book.totalChapters && book.totalChapters > 0 {
            book.readingStatus = .finished
        } else if chapterIndex > 0 {
            book.readingStatus = .reading
        }
    }
}
