import XCTest
import UIKit
@testable import YiYue

final class ReaderSettingsTests: XCTestCase {
    var settings: ReaderSettings!

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        for key in ["reader.fontSize", "reader.lineSpacing", "reader.horizontalPadding",
                     "reader.fontFamily", "reader.theme", "reader.pageMode",
                     "reader.pageMode.explicit", "reader.typographyVersion",
                     "reader.firstLineIndent", "reader.paragraphSpacing"] {
            defaults.removeObject(forKey: key)
        }
        settings = ReaderSettings()
    }

    func testDefaultValues() {
        XCTAssertEqual(settings.fontSize, 19)
        XCTAssertEqual(settings.lineSpacing, 1.5, accuracy: 0.01)
        // 行高 = 字号 × (档位 1.5 × 字体基准 1.2) = 34.2
        XCTAssertEqual(settings.lineHeightMultiplier, 1.8, accuracy: 0.001)
        XCTAssertEqual(settings.bodyLineHeight, 34.2, accuracy: 0.001)
        XCTAssertEqual(settings.fontFamily, .system)
        XCTAssertEqual(settings.theme, .paper)
        XCTAssertEqual(settings.horizontalPadding, 28)
        XCTAssertEqual(settings.pageMode, .horizontal)
    }

    func testLegacyScrollDefaultMigratesToHorizontal() {
        let defaults = UserDefaults.standard
        defaults.set(PageMode.scroll.rawValue, forKey: "reader.pageMode")

        let reloadedSettings = ReaderSettings()

        XCTAssertEqual(reloadedSettings.pageMode, .horizontal)
    }

    func testExplicitScrollPageModePersists() {
        settings.pageMode = .scroll
        settings.save(markPageModeExplicit: true)

        let reloadedSettings = ReaderSettings()

        XCTAssertEqual(reloadedSettings.pageMode, .scroll)
    }

    func testThemeColors() {
        let dark = ReaderTheme.dark
        XCTAssertEqual(dark.backgroundHex, "#121212")
        XCTAssertEqual(dark.textHex, "#d4d4d4")

        let paper = ReaderTheme.paper
        XCTAssertEqual(paper.backgroundHex, "#f5efe4")
    }

    func testFontSizeClamping() {
        settings.fontSize = 10
        XCTAssertEqual(settings.fontSize, 16)

        settings.fontSize = 50
        XCTAssertEqual(settings.fontSize, 40)
    }

    func testLineSpacingClamping() {
        settings.lineSpacing = 1.0
        XCTAssertEqual(settings.lineSpacing, 1.05, accuracy: 0.001)

        settings.lineSpacing = 3.0
        XCTAssertEqual(settings.lineSpacing, 1.95, accuracy: 0.001)
    }

    func testTypographyLevelTables() {
        XCTAssertEqual(
            ReaderTypography.fontSizeLevels,
            [16, 17, 18, 19, 20, 22, 24, 27, 30, 33, 36, 40]
        )
        XCTAssertEqual(
            ReaderTypography.lineSpacingLevels,
            [1.05, 1.20, 1.35, 1.50, 1.65, 1.80, 1.95]
        )
        XCTAssertEqual(
            ReaderTypography.horizontalPaddingLevels,
            [16, 20, 24, 28, 32, 36, 40]
        )
        XCTAssertEqual(settings.fontSizeLevelIndex, 3)
        XCTAssertEqual(settings.lineSpacingLevelIndex, 3)
        XCTAssertEqual(settings.horizontalPaddingLevelIndex, 3)
    }

    func testDefaultWidthFitsEighteenCharactersAtNineteenPoints() {
        let textWidth: CGFloat = 402 - 28 * 2
        let font = UIFont.systemFont(ofSize: 19)
        let advance = ("国" as NSString).size(withAttributes: [.font: font]).width
        let spacing = ReaderTypography.characterSpacing(
            fontSize: 19,
            textWidth: textWidth,
            font: font
        )

        XCTAssertEqual(ReaderTypography.charactersPerLine, 18)
        XCTAssertGreaterThanOrEqual(spacing, 0)
        // 18 字排得下,19 字排不下。
        XCTAssertLessThanOrEqual(18 * advance + 17 * spacing, textWidth)
        XCTAssertGreaterThan(19 * advance + 18 * spacing, textWidth)
        // 首行缩进固定两个字身 38 点,不跟着字距走。
        XCTAssertEqual(
            ReaderTypography.firstLineIndent(fontSize: 19, textWidth: textWidth),
            38,
            accuracy: 0.001
        )
    }

    func testPreparedWindowPrioritizesNextThenPreviousChapter() {
        XCTAssertEqual(
            ReaderPreparedChapterWindow.adjacentIndices(
                currentIndex: 2,
                chapterCount: 5
            ),
            [3, 1]
        )
        XCTAssertEqual(
            ReaderPreparedChapterWindow.adjacentIndices(
                currentIndex: 0,
                chapterCount: 5
            ),
            [1]
        )
    }

    func testPreparedWindowRequiresMatchingLayoutAndSource() {
        let chapterID = UUID()
        let source = ReaderChapterSourceIdentity(
            bookSourceID: UUID(),
            chapterSourceURL: "https://example.com/chapter/1"
        )
        let layout = makeLayoutKey(width: 390, fontSize: 17)
        var window = ReaderPreparedChapterWindow()
        window.store(
            chapterID: chapterID,
            sourceIdentity: source,
            content: "第一段",
            paragraphs: ["第一段"],
            pages: [[ReaderView.PageFragment(id: 1, text: "第一段", indent: true)]],
            layoutKey: layout
        )

        XCTAssertNotNil(
            window.preparedEntry(
                chapterID: chapterID,
                sourceIdentity: source,
                layoutKey: layout
            )
        )
        XCTAssertNil(
            window.preparedEntry(
                chapterID: chapterID,
                sourceIdentity: source,
                layoutKey: makeLayoutKey(width: 390, fontSize: 18)
            )
        )
        XCTAssertNil(
            window.preparedEntry(
                chapterID: chapterID,
                sourceIdentity: ReaderChapterSourceIdentity(
                    bookSourceID: source.bookSourceID,
                    chapterSourceURL: "https://example.com/chapter/changed"
                ),
                layoutKey: layout
            )
        )
    }

    func testPreparedWindowInvalidatesOnlyLayout() {
        let chapterID = UUID()
        let source = ReaderChapterSourceIdentity(
            bookSourceID: UUID(),
            chapterSourceURL: "https://example.com/chapter/1"
        )
        let layout = makeLayoutKey(width: 390, fontSize: 17)
        var window = ReaderPreparedChapterWindow()
        window.store(
            chapterID: chapterID,
            sourceIdentity: source,
            content: "第一段",
            paragraphs: ["第一段"],
            pages: [[ReaderView.PageFragment(id: 1, text: "第一段", indent: true)]],
            layoutKey: layout
        )

        window.invalidateLayouts()

        XCTAssertNil(
            window.preparedEntry(
                chapterID: chapterID,
                sourceIdentity: source,
                layoutKey: layout
            )
        )
        XCTAssertEqual(
            window.parsedEntry(chapterID: chapterID, sourceIdentity: source)?.content,
            "第一段"
        )
        XCTAssertEqual(
            window.content(chapterID: chapterID, sourceIdentity: source),
            "第一段"
        )
    }

    func testPreparedWindowRetainsOnlyThreeChapterWindow() {
        let source = ReaderChapterSourceIdentity(
            bookSourceID: UUID(),
            chapterSourceURL: nil
        )
        let ids = (0..<5).map { _ in UUID() }
        var window = ReaderPreparedChapterWindow()
        for id in ids {
            window.storeContent("正文", chapterID: id, sourceIdentity: source)
        }

        window.retain(chapterIDs: Set(ids[1...3]))

        XCTAssertEqual(window.count, 3)
        XCTAssertNil(window.content(chapterID: ids[0], sourceIdentity: source))
        XCTAssertNotNil(window.content(chapterID: ids[2], sourceIdentity: source))
        XCTAssertNil(window.content(chapterID: ids[4], sourceIdentity: source))
    }

    // MARK: - 中文标点禁则

    private func lineBreakAttributes() -> [NSAttributedString.Key: Any] {
        [.font: UIFont.systemFont(ofSize: 19), .kern: 0]
    }

    func testLineBreakerKeepsCommaOffLineStart() {
        let font = UIFont.systemFont(ofSize: 19)
        let advance = ("一" as NSString).size(withAttributes: [.font: font]).width
        let width = advance * 10 + 0.1
        let text = String(repeating: "一", count: 10) + "，" + String(repeating: "二", count: 10)

        let lines = ReaderLineBreaker.lines(
            in: text,
            width: width,
            firstLineIndent: 0,
            attributes: lineBreakAttributes()
        )

        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertEqual(lines.joined(), text)
        XCTAssertFalse(ReaderLineBreaker.forbiddenLineStart.contains(lines[0].last!))
        for line in lines.dropFirst() {
            XCTAssertFalse(ReaderLineBreaker.forbiddenLineStart.contains(line.first!))
        }
    }

    func testLineBreakerKeepsPeriodOffLineStartAndOpeningQuoteOffLineEnd() {
        let font = UIFont.systemFont(ofSize: 19)
        let advance = ("一" as NSString).size(withAttributes: [.font: font]).width
        let width = advance * 10 + 0.1
        let text = String(repeating: "一", count: 10) + "。" +
            String(repeating: "二", count: 9) + "“" +
            String(repeating: "三", count: 10) + "”"

        let lines = ReaderLineBreaker.lines(
            in: text,
            width: width,
            firstLineIndent: 0,
            attributes: lineBreakAttributes()
        )

        XCTAssertEqual(lines.joined(), text)
        for index in lines.indices {
            if index > 0 {
                XCTAssertFalse(ReaderLineBreaker.forbiddenLineStart.contains(lines[index].first!))
            }
            if index < lines.count - 1 {
                XCTAssertFalse(ReaderLineBreaker.forbiddenLineEnd.contains(lines[index].last!))
            }
        }
    }

    func testLineBreakerHandlesHalfwidthEnglishPunctuationAndQuotes() {
        let text = "Hello, world. This; is: a? test! (note) \"quoted\" end"
        var sawLineStartPunctuation = false

        for width in stride(from: 80.0, through: 220.0, by: 7.0) {
            let lines = ReaderLineBreaker.lines(
                in: text,
                width: CGFloat(width),
                firstLineIndent: 0,
                attributes: lineBreakAttributes()
            )
            XCTAssertEqual(lines.joined(), text)
            for (index, line) in lines.enumerated() {
                guard let first = line.first, let last = line.last else { continue }
                XCTAssertFalse(ReaderLineBreaker.forbiddenLineStart.contains(first))
                if index < lines.count - 1 {
                    XCTAssertFalse(ReaderLineBreaker.forbiddenLineEnd.contains(last))
                }
                if [",", ".", ";", ":", "?", "!", ")"].contains(first) {
                    sawLineStartPunctuation = true
                }
            }
        }
        XCTAssertFalse(sawLineStartPunctuation)
    }

    func testLineBreakerPreservesHardLineBreaks() {
        let text = "第一行没有标点\n第二行,也没有。"
        let lines = ReaderLineBreaker.lines(
            in: text,
            width: 200,
            firstLineIndent: 0,
            attributes: lineBreakAttributes()
        )

        XCTAssertEqual(lines, ["第一行没有标点", "第二行,也没有。"])
    }

    private func makeLayoutKey(width: Double, fontSize: Double) -> ReaderChapterLayoutKey {
        ReaderChapterLayoutKey(
            width: width,
            height: 844,
            fontSize: fontSize,
            lineSpacing: 2,
            fontFamily: "System",
            usesSystemFont: true,
            horizontalPadding: 28,
            bottomReserve: 72,
            paragraphSpacing: 28,
            firstLineIndent: true
        )
    }
}
