import XCTest
import SwiftData
@testable import YiYue

final class ModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: Book.self, Chapter.self, BookSource.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    func testBookCreation() {
        let book = Book(title: "斗破苍穹", author: "天蚕土豆", sourceType: .localFile, totalChapters: 1647)
        context.insert(book)

        XCTAssertEqual(book.title, "斗破苍穹")
        XCTAssertEqual(book.author, "天蚕土豆")
        XCTAssertEqual(book.readingStatus, .unread)
        XCTAssertEqual(book.lastReadChapterIndex, 0)
        XCTAssertEqual(book.totalChapters, 1647)
    }

    func testProgressComputation() {
        let book = Book(title: "Test", author: "A", sourceType: .localFile, totalChapters: 100)
        book.lastReadChapterIndex = 45
        XCTAssertEqual(book.progress, 0.45, accuracy: 0.001)
    }

    func testProgressZeroDivision() {
        let book = Book(title: "Test", author: "A", sourceType: .localFile, totalChapters: 0)
        XCTAssertEqual(book.progress, 0)
    }

    func testChapterRelationship() {
        let book = Book(title: "Test", author: "A", sourceType: .localFile, totalChapters: 2)
        context.insert(book)

        let ch1 = Chapter(index: 0, title: "第一章", content: "内容一")
        let ch2 = Chapter(index: 1, title: "第二章", content: "内容二")
        ch1.book = book
        ch2.book = book
        context.insert(ch1)
        context.insert(ch2)

        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertTrue(ch1.isCached)
    }

    func testChapterWithoutContentIsNotCached() {
        let ch = Chapter(index: 0, title: "Ch1", content: nil)
        XCTAssertFalse(ch.isCached)
    }

    func testBookSourceCreation() {
        let source = BookSource(name: "笔趣阁", sourceURL: "https://example.com", ruleJSON: "{}")
        context.insert(source)

        XCTAssertEqual(source.name, "笔趣阁")
        XCTAssertTrue(source.enabled)
        XCTAssertFalse(source.isQualityVerified)
        XCTAssertNil(source.qualityScore)
    }

    func testAddBookPersistenceWorkerCreatesCompleteGraph() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let testContainer = try ModelContainer(
            for: Book.self, Chapter.self, BookSource.self,
            configurations: config
        )
        let draft = AddBookPersistenceDraft(
            title: "后台入库测试",
            author: "Author",
            sourceId: UUID(),
            sourceBookURL: "https://example.com/book",
            sourceName: "Test Source",
            coverURL: nil,
            chapters: [
                .init(index: 0, title: "Chapter 1", sourceURL: "https://example.com/1"),
                .init(index: 1, title: "Chapter 2", sourceURL: "https://example.com/2")
            ]
        )

        let bookId = try await Task.detached {
            try AddBookPersistenceWorker.addBook(draft, in: testContainer)
        }.value

        let verificationContext = ModelContext(testContainer)
        let expectedId = bookId
        let descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { $0.id == expectedId }
        )
        let persistedBook = try XCTUnwrap(verificationContext.fetch(descriptor).first)

        XCTAssertEqual(persistedBook.totalChapters, 2)
        XCTAssertEqual(persistedBook.chapters.map(\.index).sorted(), [0, 1])
        XCTAssertEqual(
            persistedBook.chapters.compactMap(\.sourceURL).sorted(),
            ["https://example.com/1", "https://example.com/2"]
        )
        XCTAssertTrue(persistedBook.chapters.allSatisfy { $0.book?.id == bookId })
    }

    func testBackgroundCoverUpdateDoesNotReplaceExistingCover() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let testContainer = try ModelContainer(
            for: Book.self, Chapter.self, BookSource.self,
            configurations: config
        )
        let draft = AddBookPersistenceDraft(
            title: "Cover Test",
            author: "Author",
            sourceId: UUID(),
            sourceBookURL: "https://example.com/book",
            sourceName: "Test Source",
            coverURL: nil,
            chapters: [.init(index: 0, title: "Chapter", sourceURL: "https://example.com/1")]
        )
        let (bookId, firstApplied, secondApplied) = try await Task.detached {
            let bookId = try AddBookPersistenceWorker.addBook(draft, in: testContainer)
            let firstApplied = try AddBookPersistenceWorker.setCoverIfMissing(
                bookId: bookId,
                coverURL: "covers/first.jpg",
                in: testContainer
            )
            let secondApplied = try AddBookPersistenceWorker.setCoverIfMissing(
                bookId: bookId,
                coverURL: "covers/second.jpg",
                in: testContainer
            )
            return (bookId, firstApplied, secondApplied)
        }.value

        XCTAssertTrue(firstApplied)
        XCTAssertFalse(secondApplied)

        let verificationContext = ModelContext(testContainer)
        let expectedId = bookId
        let descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { $0.id == expectedId }
        )
        let persistedBook = try XCTUnwrap(verificationContext.fetch(descriptor).first)
        XCTAssertEqual(persistedBook.coverURL, "covers/first.jpg")
    }
}
