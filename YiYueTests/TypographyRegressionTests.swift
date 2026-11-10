import XCTest
import UIKit
@testable import YiYue

/// 排版回归:用测试 target 里的 `TypographyTest.txt`,不进 app 包。
final class TypographyRegressionTests: XCTestCase {
    private func sampleText() throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "TypographyTest", withExtension: "txt"),
            "TypographyTest.txt 没进测试 bundle"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func brokenLines(_ text: String) -> [String] {
        ReaderLineBreaker.lines(
            in: text,
            width: 346,
            firstLineIndent: ReaderTypography.firstLineIndent(
                fontSize: ReaderTypography.defaultFontSize,
                textWidth: 346
            ),
            attributes: [.font: UIFont.systemFont(ofSize: ReaderTypography.defaultFontSize)]
        )
    }

    func testNoForbiddenPunctuationAtLineEdges() throws {
        // 样本里有两行本身就是「禁则符号清单」(整行只有开引号/开括号),
        // 不给任何可跟随的正文,任何断行都无法避免它自己以开符号结尾;
        // 这两行只用来核对禁则字符集,不参与逐行边界断言。
        let prose = try sampleText()
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("下列符号不该落在") }
            .joined(separator: "\n")
        let lines = brokenLines(prose)
        XCTAssertGreaterThan(lines.count, 5)
        for line in lines where !line.isEmpty {
            XCTAssertFalse(
                ReaderLineBreaker.forbiddenLineStart.contains(line.first!),
                "行首出现禁则字符: \(line)"
            )
            XCTAssertFalse(
                ReaderLineBreaker.forbiddenLineEnd.contains(line.last!),
                "行尾出现禁则字符: \(line)"
            )
        }
    }

    func testLongDigitsAndEnglishWordsStayWhole() throws {
        let lines = brokenLines(try sampleText())
        for token in ["WeChat", "iPad", "PDF", "1,000,000", "2024", "3.14%"] {
            XCTAssertTrue(
                lines.contains { $0.contains(token) },
                "\(token) 被拆到了两行"
            )
        }
    }

    func testDefaultParagraphSpacingIs28() {
        XCTAssertEqual(ReaderTypography.baseParagraphSpacing, 28)
    }
}
