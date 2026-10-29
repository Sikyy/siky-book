import XCTest
@testable import YiYue

final class TocMergerTests: XCTestCase {
    func testAppendsOnlyChaptersTheShelfDoesNotHave() {
        let existingTitles = ["第一章 开篇", "第二章 夜行"]
        let incoming = [
            ChapterInfo(title: "第一章 开篇", url: "https://example.com/1"),
            ChapterInfo(title: "第二章 夜行", url: "https://example.com/2"),
            ChapterInfo(title: "第三章 归途", url: "https://example.com/3")
        ]

        let fresh = TocMerger.newChapters(
            existingTitles: existingTitles,
            existingURLs: [],
            incoming: incoming
        )

        XCTAssertEqual(fresh.map(\.title), ["第三章 归途"])
    }

    func testMatchesTitlesRegardlessOfSpacingAndCase() {
        let incoming = [ChapterInfo(title: "  chapter  1 ", url: "https://example.com/1")]

        let fresh = TocMerger.newChapters(
            existingTitles: ["Chapter1"],
            existingURLs: [],
            incoming: incoming
        )

        XCTAssertTrue(fresh.isEmpty)
    }

    func testSkipsChaptersAlreadyKnownByURL() {
        let incoming = [ChapterInfo(title: "改过名的旧章", url: "https://example.com/9")]

        let fresh = TocMerger.newChapters(
            existingTitles: [],
            existingURLs: ["https://example.com/9"],
            incoming: incoming
        )

        XCTAssertTrue(fresh.isEmpty)
    }

    func testDeduplicatesIncomingChapters() {
        let incoming = [
            ChapterInfo(title: "第五章", url: "https://example.com/5"),
            ChapterInfo(title: "第五章", url: "https://example.com/5"),
            ChapterInfo(title: "第六章", url: "https://example.com/6")
        ]

        let fresh = TocMerger.newChapters(existingTitles: [], existingURLs: [], incoming: incoming)

        XCTAssertEqual(fresh.map(\.title), ["第五章", "第六章"])
    }

    func testDropsBlankTitles() {
        let incoming = [
            ChapterInfo(title: "   ", url: "https://example.com/blank"),
            ChapterInfo(title: "第七章", url: "https://example.com/7")
        ]

        let fresh = TocMerger.newChapters(existingTitles: [], existingURLs: [], incoming: incoming)

        XCTAssertEqual(fresh.map(\.title), ["第七章"])
    }
}
