import XCTest
import SwiftData
@testable import YiYue

@MainActor
final class BookManagerTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var manager: BookManager!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: Book.self, Chapter.self, BookSource.self,
            configurations: config
        )
        context = ModelContext(container)
        manager = BookManager(modelContext: context)
    }

    func testAddBook() throws {
        _ = manager.addBook(title: "三体", author: "刘慈欣", sourceType: .localFile)
        try context.save()

        let descriptor = FetchDescriptor<Book>()
        let books = try context.fetch(descriptor)
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.title, "三体")
    }

    func testLastChapterOpeningDoesNotMarkBookFinished() throws {
        let book = manager.addBook(title: "三体", author: "刘慈欣", sourceType: .localFile)
        book.totalChapters = 10

        manager.updateProgress(book: book, chapterIndex: 9, position: 0.2)

        XCTAssertEqual(book.readingStatus, .reading)
    }

    func testEarlierChapterNeverMarksBookFinished() throws {
        let book = manager.addBook(title: "三体", author: "刘慈欣", sourceType: .localFile)
        book.totalChapters = 10
        book.readingStatus = .reading

        manager.updateProgress(book: book, chapterIndex: 3, position: 1)

        XCTAssertEqual(book.readingStatus, .reading)
    }

    func testDeleteBookWaitsForCleanupAndPersistsDeletion() async throws {
        let book = manager.addBook(title: "三体", author: "刘慈欣", sourceType: .localFile)
        try context.save()
        let bookID = book.id
        let cleanup = BookCleanupRecorder()
        manager = BookManager(modelContext: context) { bookID in
            await cleanup.record(bookID)
        }

        try await manager.deleteBook(book)

        let descriptor = FetchDescriptor<Book>()
        let books = try context.fetch(descriptor)
        XCTAssertEqual(books.count, 0)
        let cleanedIDs = await cleanup.bookIDs
        XCTAssertEqual(cleanedIDs, [bookID])
    }

    func testDeleteBookPreservesModelWhenCleanupFails() async throws {
        let book = manager.addBook(title: "三体", author: "刘慈欣", sourceType: .localFile)
        try context.save()
        manager = BookManager(modelContext: context) { _ in
            throw BookCleanupTestError.failed
        }

        do {
            try await manager.deleteBook(book)
            XCTFail("缓存清理失败时不应删除书籍")
        } catch BookCleanupTestError.failed {
            // Expected.
        }

        let books = try context.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(books.map(\.id), [book.id])
    }

    func testUpdateReadingProgress() {
        let book = manager.addBook(title: "三体", author: "刘慈欣", sourceType: .localFile)
        book.totalChapters = 100

        manager.updateProgress(book: book, chapterIndex: 30, position: 0.5)

        XCTAssertEqual(book.lastReadChapterIndex, 30)
        XCTAssertEqual(book.lastReadPosition, 0.5)
        XCTAssertEqual(book.readingStatus, .reading)
        XCTAssertNotNil(book.lastReadDate)
    }

    func testMarkAsFinished() {
        let book = manager.addBook(title: "三体", author: "刘慈欣", sourceType: .localFile)
        book.totalChapters = 100

        // Chapter indices are 0-based: 99 is the last chapter, and reaching its
        // last page is what makes the book finished.
        manager.updateProgress(book: book, chapterIndex: 99, position: 1)

        XCTAssertEqual(book.readingStatus, .finished)
    }
}

private actor BookCleanupRecorder {
    private(set) var bookIDs: [UUID] = []

    func record(_ bookID: UUID) {
        bookIDs.append(bookID)
    }
}

private enum BookCleanupTestError: Error {
    case failed
}
