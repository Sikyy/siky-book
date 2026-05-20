import XCTest
@testable import NovelReader

final class ChapterSplitterTests: XCTestCase {
    func testBasicChineseChapters() {
        let text = """
        第一章 少年
        少年站在山巅之上。

        第二章 下山
        他决定下山去看看。
        """
        let chapters = ChapterSplitter.split(text)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "第一章 少年")
        XCTAssertTrue(chapters[0].content.contains("少年站在山巅"))
        XCTAssertEqual(chapters[1].title, "第二章 下山")
    }

    func testNumericChapterMarkers() {
        let text = """
        第1章 开始
        内容一。

        第2章 发展
        内容二。

        第10章 高潮
        内容十。
        """
        let chapters = ChapterSplitter.split(text)
        XCTAssertEqual(chapters.count, 3)
    }

    func testChineseNumerals() {
        let text = """
        第一百二十三章 大战
        战斗开始了。

        第一百二十四章 结束
        战斗结束了。
        """
        let chapters = ChapterSplitter.split(text)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "第一百二十三章 大战")
    }

    func testNoChapterMarkers() {
        let text = "这是一段没有章节标记的纯文本内容。\n就是一段文字。"
        let chapters = ChapterSplitter.split(text)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].title, "全文")
    }

    func testPrologueBeforeFirstChapter() {
        let text = """
        这是序言内容。

        第一章 正文开始
        正文内容。
        """
        let chapters = ChapterSplitter.split(text)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "序")
        XCTAssertEqual(chapters[1].title, "第一章 正文开始")
    }

    func testSectionAndVolumeMarkers() {
        let text = """
        第一节 引子
        内容。

        第一回 开场
        内容。
        """
        let chapters = ChapterSplitter.split(text)
        XCTAssertEqual(chapters.count, 2)
    }
}
