import XCTest
import SwiftData
@testable import YiYue

final class ImportServiceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var importService: ImportService!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: Book.self, Chapter.self, BookSource.self,
            configurations: config
        )
        context = ModelContext(container)
        importService = ImportService(modelContext: context)
    }

    func testImportTXTWithChapters() throws {
        let content = """
        第一章 开始
        这是第一章的正文内容。非常精彩。

        第二章 发展
        这是第二章的正文内容。更加精彩。

        第三章 高潮
        这是第三章的正文内容。最为精彩。
        """

        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_novel.txt")
        try content.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let book = try importService.importTXT(from: tmpFile)

        XCTAssertEqual(book.title, "test_novel")
        XCTAssertEqual(book.sourceType, .localFile)
        XCTAssertEqual(book.totalChapters, 3)
        XCTAssertEqual(book.readingStatus, .unread)

        let bookId = book.id
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.book?.id == bookId },
            sortBy: [SortDescriptor(\Chapter.index)]
        )
        let chapters = try context.fetch(descriptor)
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[0].title, "第一章 开始")
        XCTAssertTrue(chapters[0].isCached)
        XCTAssertTrue(chapters[0].content?.contains("非常精彩") ?? false)
    }

    func testImportTXTWithoutChapters() throws {
        let content = "这是一段没有章节的纯文本小说。很短。"

        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("short.txt")
        try content.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let book = try importService.importTXT(from: tmpFile)

        XCTAssertEqual(book.totalChapters, 1)

        let bookId = book.id
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.book?.id == bookId }
        )
        let chapters = try context.fetch(descriptor)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].title, "全文")
    }

    func testImportTXTCustomTitle() throws {
        let content = "第一章 Test\n内容。"

        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("file.txt")
        try content.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let book = try importService.importTXT(from: tmpFile, title: "自定义书名")

        XCTAssertEqual(book.title, "自定义书名")
    }
}
