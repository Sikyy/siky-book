import XCTest
@testable import YiYue

final class ReaderChromeStatsTests: XCTestCase {
    func testStatsRowsUseOnlyRealData() {
        let stats = ReaderReadingStats(
            readingDays: 5,
            pagesRead: 380,
            bookmarkCount: 3,
            finishedChapters: 12
        )
        XCTAssertEqual(
            stats.rows.map(\.title),
            ["阅读天数", "翻页", "书签", "读完"]
        )
        XCTAssertEqual(
            stats.rows.map(\.value),
            ["5 天", "380 页", "3 条", "12 章"]
        )
    }

    func testStatsOmitsZeroRows() {
        let stats = ReaderReadingStats(
            readingDays: 0,
            pagesRead: 0,
            bookmarkCount: 3,
            finishedChapters: 2
        )
        XCTAssertEqual(stats.rows.map(\.title), ["书签", "读完"])
        XCTAssertFalse(stats.isEmpty)
    }

    func testEmptyStats() {
        let stats = ReaderReadingStats(
            readingDays: 0,
            pagesRead: 0,
            bookmarkCount: 0,
            finishedChapters: 0
        )
        XCTAssertTrue(stats.isEmpty)
        XCTAssertTrue(stats.rows.isEmpty)
    }

    func testActivityStoreCountsDaysAndPagesPerBook() throws {
        let suite = "reader-activity-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bookID = UUID()
        let otherBook = UUID()
        var components = DateComponents()
        components.year = 2024
        components.month = 5
        components.day = 1
        components.hour = 12
        let day1 = Calendar.current.date(from: components)!
        let day1Later = day1.addingTimeInterval(3600)
        let day2 = day1.addingTimeInterval(86_400)

        ReaderActivityStore.recordReadingDay(bookID: bookID, date: day1, defaults: defaults)
        ReaderActivityStore.recordReadingDay(bookID: bookID, date: day1Later, defaults: defaults)
        ReaderActivityStore.recordReadingDay(bookID: bookID, date: day2, defaults: defaults)
        ReaderActivityStore.recordPageFlip(bookID: bookID, defaults: defaults)
        ReaderActivityStore.recordPageFlip(bookID: bookID, defaults: defaults)

        XCTAssertEqual(ReaderActivityStore.readingDays(bookID: bookID, defaults: defaults), 2)
        XCTAssertEqual(ReaderActivityStore.pagesRead(bookID: bookID, defaults: defaults), 2)
        XCTAssertEqual(ReaderActivityStore.readingDays(bookID: otherBook, defaults: defaults), 0)
    }

    func testCharacterCountIgnoresWhitespaceAndLineBreaks() {
        XCTAssertEqual(ReaderCharacterCount.count("第一行\n第二行 三"), 8)
        XCTAssertEqual(ReaderCharacterCount.count("  \n\t"), 0)
    }
}
