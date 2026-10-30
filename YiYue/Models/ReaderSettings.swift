import UIKit
import SwiftUI

enum FontFamily: String, CaseIterable, Codable {
    case system = "system-default"
    case songti = "Songti SC"
    case kaiti = "Kaiti SC"

    var displayName: String {
        switch self {
        case .system: return "默认"
        case .songti: return "宋体"
        case .kaiti: return "楷体"
        }
    }

    var isSystem: Bool { self == .system }
}

enum PageMode: String, CaseIterable, Codable {
    case scroll
    case horizontal
    case tap

    var displayName: String {
        switch self {
        case .scroll: return "滚动"
        case .horizontal, .tap: return "翻页"
        }
    }

    /// 设置面板只给两项:翻页 / 滚动。
    var isPaging: Bool { self != .scroll }
}

/// 正文排版的基准数值。
///
/// 行高三步走,不要合并成一个魔法数:
///   1. 字体基准 `fontScaleBase` = 1.2(单独常量)
///   2. 行距档位 `lineSpacing` = 1.5(存的是档位,界面也显示 1.5)
///   3. 倍率 = 档位 × 字体基准 = 1.8,行高 = 字号 × 倍率 = 19 × 1.8 = 34.2
enum ReaderTypography {
    /// 第 1 步:字体基准。行距档位要在它之上再乘一次。
    static let fontScaleBase: CGFloat = 1.2

    /// 第 2 步:行距档位。默认 1.5,七档。
    static let defaultLineSpacingLevel: Double = 1.5
    static let lineSpacingLevels: [Double] = [1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8]

    /// 第 3 步:倍率与行高。
    static func lineHeightMultiplier(level: Double) -> CGFloat {
        CGFloat(level) * fontScaleBase
    }

    static func bodyLineHeight(fontSize: CGFloat, level: Double) -> CGFloat {
        fontSize * lineHeightMultiplier(level: level)
    }

    static let defaultFontSize: CGFloat = 19
    /// 12 档字号,19 是默认档。
    static let fontSizeLevels: [CGFloat] = [12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24, 28]

    /// 七档边距,默认 28,每档 +4。
    static let defaultHorizontalPadding: CGFloat = 28
    static let horizontalPaddingLevels: [CGFloat] = [16, 20, 24, 28, 32, 36, 40]

    /// 每行 19 字:19 号字在 346 点行宽里排不下 19 个全角字,
    /// 用一点负字距把字身压到 346 / 19 = 18.21 点。
    static let charactersPerLine: CGFloat = 19
    static func characterSpacing(fontSize: CGFloat, textWidth: CGFloat) -> CGFloat {
        guard charactersPerLine > 0 else { return 0 }
        // 留 0.06 点余量,否则 19 字刚好顶满行宽时 TextKit 会把最后一字挤到下一行。
        return textWidth / charactersPerLine - fontSize - 0.06
    }

    /// 首行缩进两个字身。
    static let firstLineIndentCharacters: CGFloat = 2
    static func firstLineIndent(fontSize: CGFloat, textWidth: CGFloat) -> CGFloat {
        let advance = fontSize + characterSpacing(fontSize: fontSize, textWidth: textWidth)
        return advance * firstLineIndentCharacters
    }

    /// 段间距 28;设置里的「段间距」开关打开时再加 28。
    static let baseParagraphSpacing: CGFloat = 28
    static let extraParagraphSpacing: CGFloat = 28

    /// 首行字顶(屏幕坐标)、章节名字顶、页脚字底离屏幕底。
    static let bodyTopInkY: CGFloat = 116
    static let chapterTitleTopInkY: CGFloat = 76
    static let footerBottomInset: CGFloat = 55

    /// 一页正文固定 18 行的容量(默认字号)。
    static let bodyLineCount: CGFloat = 18

    /// 文本容器顶到首行字墨顶的实测差值(19 号 / 34.2 行高)。
    /// 规格要字顶 116,容器因此再往下补 6.7。
    static let bodyInkCalibration: CGFloat = 6.7

    /// TextKit 行内字顶到行顶的距离:maxLineHeight 把基线放在行底再减 descender,
    /// 中文字面顶大约在基线往上 0.93 em。这个常数由实测校准。
    static func inkTopOffset(fontSize: CGFloat, lineHeight: CGFloat, font: UIFont) -> CGFloat {
        let baselineFromTop = lineHeight - font.descender
        let inkFromBaseline = fontSize * 0.93
        return max(0, baselineFromTop - inkFromBaseline)
    }
}

@Observable
class ReaderSettings {
    private static let fontSizeRange: ClosedRange<CGFloat> = 12...28
    private static let lineSpacingRange: ClosedRange<Double> = 1.2...1.8
    private static let paddingRange: ClosedRange<CGFloat> = 16...40
    private static let typographyVersionKey = "reader.typographyVersion"
    private static let currentTypographyVersion = 9
    private static let pageModeKey = "reader.pageMode"
    private static let pageModeExplicitKey = "reader.pageMode.explicit"
    private static let defaultPageMode: PageMode = .horizontal
    private static let legacyDefaultPageMode: PageMode = .scroll

    var fontSize: CGFloat {
        get { _fontSize }
        set { _fontSize = newValue.clamped(to: Self.fontSizeRange) }
    }

    var lineSpacing: Double {
        get { _lineSpacing }
        set { _lineSpacing = newValue.clamped(to: Self.lineSpacingRange) }
    }

    var horizontalPadding: CGFloat {
        get { _horizontalPadding }
        set { _horizontalPadding = newValue.clamped(to: Self.paddingRange) }
    }

    private var _fontSize: CGFloat = ReaderTypography.defaultFontSize
    private var _lineSpacing: Double = ReaderTypography.defaultLineSpacingLevel
    private var _horizontalPadding: CGFloat = ReaderTypography.defaultHorizontalPadding

    var fontFamily: FontFamily
    var theme: ReaderTheme
    var pageMode: PageMode
    /// Keeps the screen awake while the reader is open. On by default.
    var keepScreenAwake: Bool
    /// 首行缩进两字,默认开。
    var firstLineIndentEnabled: Bool
    /// 段间距开关,默认关。关着也有 28 的段间距,打开再加 28。
    var paragraphSpacingEnabled: Bool

    /// 行高 = 字号 × (行距档位 × 字体基准),排版和几何都用这一个算法。
    var lineHeightMultiplier: CGFloat {
        ReaderTypography.lineHeightMultiplier(level: lineSpacing)
    }

    var bodyLineHeight: CGFloat {
        ReaderTypography.bodyLineHeight(fontSize: fontSize, level: lineSpacing)
    }

    var paragraphSpacing: CGFloat {
        ReaderTypography.baseParagraphSpacing
            + (paragraphSpacingEnabled ? ReaderTypography.extraParagraphSpacing : 0)
    }

    var fontSizeLevelIndex: Int {
        ReaderTypography.fontSizeLevels.enumerated()
            .min { abs($0.element - fontSize) < abs($1.element - fontSize) }?
            .offset ?? 0
    }

    var lineSpacingLevelIndex: Int {
        ReaderTypography.lineSpacingLevels.enumerated()
            .min { abs($0.element - lineSpacing) < abs($1.element - lineSpacing) }?
            .offset ?? 0
    }

    var horizontalPaddingLevelIndex: Int {
        ReaderTypography.horizontalPaddingLevels.enumerated()
            .min { abs($0.element - horizontalPadding) < abs($1.element - horizontalPadding) }?
            .offset ?? 0
    }

    init() {
        let defaults = UserDefaults.standard
        let storedVersion = defaults.integer(forKey: Self.typographyVersionKey)
        if storedVersion < Self.currentTypographyVersion {
            // 1.0.8(9) 起正文换成 19 号 / 行距档位 1.5 / 边距 28,
            // 旧版本的 17 号、2.0 是另一套排版,升级时迁到新基准。
            defaults.set(Double(ReaderTypography.defaultFontSize), forKey: "reader.fontSize")
            defaults.set(ReaderTypography.defaultLineSpacingLevel, forKey: "reader.lineSpacing")
            defaults.set(Double(ReaderTypography.defaultHorizontalPadding), forKey: "reader.horizontalPadding")
            defaults.set(Self.currentTypographyVersion, forKey: Self.typographyVersionKey)
        }
        self._fontSize = CGFloat(defaults.double(forKey: "reader.fontSize"))
            .nonZeroOr(ReaderTypography.defaultFontSize)
        self._lineSpacing = defaults.double(forKey: "reader.lineSpacing")
            .nonZeroOr(ReaderTypography.defaultLineSpacingLevel)
        self._horizontalPadding = CGFloat(defaults.double(forKey: "reader.horizontalPadding"))
            .nonZeroOr(ReaderTypography.defaultHorizontalPadding)
        self.fontFamily = FontFamily(rawValue: defaults.string(forKey: "reader.fontFamily") ?? "") ?? .system
        self.theme = ReaderTheme(rawValue: defaults.string(forKey: "reader.theme") ?? "") ?? .paper
        self.pageMode = Self.loadPageMode(from: defaults)
        let storedKeepAwake = defaults.object(forKey: "reader.keepScreenAwake") as? Bool
        self.keepScreenAwake = storedKeepAwake ?? true
        self.firstLineIndentEnabled = defaults.object(forKey: "reader.firstLineIndent") as? Bool ?? true
        self.paragraphSpacingEnabled = defaults.object(forKey: "reader.paragraphSpacing") as? Bool ?? false
    }

    func save(markPageModeExplicit: Bool = false) {
        let defaults = UserDefaults.standard
        defaults.set(Double(fontSize), forKey: "reader.fontSize")
        defaults.set(lineSpacing, forKey: "reader.lineSpacing")
        defaults.set(Double(horizontalPadding), forKey: "reader.horizontalPadding")
        defaults.set(fontFamily.rawValue, forKey: "reader.fontFamily")
        defaults.set(theme.rawValue, forKey: "reader.theme")
        defaults.set(pageMode.rawValue, forKey: Self.pageModeKey)
        defaults.set(keepScreenAwake, forKey: "reader.keepScreenAwake")
        defaults.set(firstLineIndentEnabled, forKey: "reader.firstLineIndent")
        defaults.set(paragraphSpacingEnabled, forKey: "reader.paragraphSpacing")
        defaults.set(Self.currentTypographyVersion, forKey: Self.typographyVersionKey)
        if markPageModeExplicit {
            defaults.set(true, forKey: Self.pageModeExplicitKey)
        }
    }

    private static func loadPageMode(from defaults: UserDefaults) -> PageMode {
        guard let rawValue = defaults.string(forKey: pageModeKey),
              let savedMode = PageMode(rawValue: rawValue) else {
            return defaultPageMode
        }

        let hasExplicitPageMode = defaults.bool(forKey: pageModeExplicitKey)
        if savedMode == legacyDefaultPageMode && !hasExplicitPageMode {
            return defaultPageMode
        }

        return savedMode
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Double {
    func nonZeroOr(_ fallback: Double) -> Double {
        self == 0 ? fallback : self
    }
}

private extension CGFloat {
    func nonZeroOr(_ fallback: CGFloat) -> CGFloat {
        self == 0 ? fallback : self
    }
}
