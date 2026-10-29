import Foundation
import SwiftData

@MainActor
final class BookManager {
    typealias CacheCleanup = @MainActor (UUID) async throws -> Void

    private let modelContext: ModelContext
    private let cleanupCache: CacheCleanup

    init(
        modelContext: ModelContext,
        cleanupCache: @escaping CacheCleanup = { bookID in
            try await ChapterDownloadManager.shared.clear(bookID: bookID)
        }
    ) {
        self.modelContext = modelContext
        self.cleanupCache = cleanupCache
    }

    func addBook(title: String, author: String, sourceType: SourceType) -> Book {
        let book = Book(title: title, author: author, sourceType: sourceType)
        modelContext.insert(book)
        return book
    }

    /// Deletes queue intent and disk cache before committing the model delete.
    /// Callers receive either cleanup or persistence failures instead of leaving
    /// an unstructured best-effort task running after this method returns.
    func deleteBook(_ book: Book) async throws {
        let bookID = book.id
        try await cleanupCache(bookID)
        try Task.checkCancellation()
        modelContext.delete(book)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func updateProgress(book: Book, chapterIndex: Int, position: Double) {
        book.lastReadChapterIndex = chapterIndex
        book.lastReadPosition = position
        book.lastReadDate = Date()

        // Chapter indices are 0-based, so the last chapter is totalChapters - 1.
        let onLastChapter = book.totalChapters > 0 && chapterIndex >= book.totalChapters - 1
        if onLastChapter && position >= 0.999 {
            book.readingStatus = .finished
        } else if chapterIndex > 0 || position > 0 {
            book.readingStatus = .reading
        }
    }
}
