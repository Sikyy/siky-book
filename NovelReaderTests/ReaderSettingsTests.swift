import XCTest
@testable import NovelReader

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
        XCTAssertEqual(settings.fontFamily, .pingfang)
        XCTAssertEqual(settings.theme, .pureBlack)
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
        let pureBlack = ReaderTheme.pureBlack
        XCTAssertEqual(pureBlack.backgroundHex, "#121212")
        XCTAssertEqual(pureBlack.textHex, "#d4d4d4")

        let warmBlack = ReaderTheme.warmBlack
        XCTAssertEqual(warmBlack.backgroundHex, "#1a1814")
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
}
