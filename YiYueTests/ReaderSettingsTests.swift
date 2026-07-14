import XCTest
@testable import YiYue

final class ReaderSettingsTests: XCTestCase {
    var settings: ReaderSettings!

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        for key in ["reader.fontSize", "reader.lineSpacing", "reader.horizontalPadding",
                     "reader.fontFamily", "reader.theme", "reader.pageMode",
                     "reader.pageMode.explicit"] {
            defaults.removeObject(forKey: key)
        }
        settings = ReaderSettings()
    }

    func testDefaultValues() {
        XCTAssertEqual(settings.fontSize, 17)
        XCTAssertEqual(settings.lineSpacing, 2.0, accuracy: 0.01)
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
        XCTAssertEqual(settings.fontSize, 12)

        settings.fontSize = 50
        XCTAssertEqual(settings.fontSize, 32)
    }

    func testLineSpacingClamping() {
        settings.lineSpacing = 1.0
        XCTAssertEqual(settings.lineSpacing, 1.5, accuracy: 0.01)

        settings.lineSpacing = 3.0
        XCTAssertEqual(settings.lineSpacing, 2.5, accuracy: 0.01)
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

    private func makeLayoutKey(width: Double, fontSize: Double) -> ReaderChapterLayoutKey {
        ReaderChapterLayoutKey(
            width: width,
            height: 844,
            fontSize: fontSize,
            lineSpacing: 2,
            fontFamily: "System",
            usesSystemFont: true,
            horizontalPadding: 28,
            bottomReserve: 72
        )
    }
}
