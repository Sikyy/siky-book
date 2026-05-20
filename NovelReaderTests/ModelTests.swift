import XCTest
import SwiftData
@testable import NovelReader

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
}
