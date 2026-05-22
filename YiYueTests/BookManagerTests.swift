import XCTest
import SwiftData
@testable import YiYue

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
        let book = manager.addBook(title: "三体", author: "刘慈欣", sourceType: .localFile)
        try context.save()

        let descriptor = FetchDescriptor<Book>()
        let books = try context.fetch(descriptor)
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.title, "三体")
    }

    func testDeleteBook() throws {
        let book = manager.addBook(title: "三体", author: "刘慈欣", sourceType: .localFile)
        try context.save()

        manager.deleteBook(book)
        try context.save()

        let descriptor = FetchDescriptor<Book>()
        let books = try context.fetch(descriptor)
        XCTAssertEqual(books.count, 0)
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

        manager.updateProgress(book: book, chapterIndex: 100, position: 0)

        XCTAssertEqual(book.readingStatus, .finished)
    }
}
