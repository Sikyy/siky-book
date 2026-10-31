import UIKit
import SwiftUI
import CoreText

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

    /// UIFont(name:) 要的是 PostScript 名,不是家族名;"Songti SC" 直接传进去
    /// 会静默拿到 nil 再回退系统无衬线。这里先按家族名查可用字面,取 Regular。
    private static let postScriptNames: [String: String] = {
        var names: [String: String] = [:]
        for family in FontFamily.allCases where !family.isSystem {
            let available = UIFont.fontNames(forFamilyName: family.rawValue)
            names[family.rawValue] = available.first {
                $0.localizedCaseInsensitiveContains("regular")
            } ?? available.first
        }
        return names
    }()

    /// 供 SwiftUI `Font.custom` 用的字体名(同样是 PostScript 名)。
    var postScriptName: String {
        Self.postScriptNames[rawValue] ?? rawValue
    }

    /// 统一解析字体:分页测量、TextKit 渲染和 SwiftUI 滚动正文必须拿到同一个字体。
    func uiFont(size: CGFloat) -> UIFont {
        Self.uiFont(family: rawValue, size: size, usesSystemFont: isSystem)
    }

    static func uiFont(family: String, size: CGFloat, usesSystemFont: Bool) -> UIFont {
        if usesSystemFont { return .systemFont(ofSize: size) }
        if let name = postScriptNames[family], let font = UIFont(name: name, size: size) {
            return font
        }
        // 家族名兜底:即使字面名和系统版本对不上,也尽量留在同一字族里。
        let descriptor = UIFontDescriptor(fontAttributes: [.family: family])
        return UIFont(descriptor: descriptor, size: size)
    }
}

enum PageMode: String, CaseIterable, Codable {
    case scroll
    case horizontal
    case tap

    var displayName: String {
        switch self {
        case .scroll: return "上下滑动"
        case .horizontal: return "左右翻页"
        case .tap: return "点击翻页"
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
    static let lineSpacingLevels: [Double] = [1.05, 1.20, 1.35, 1.50, 1.65, 1.80, 1.95]

    /// 第 3 步:倍率与行高。
    static func lineHeightMultiplier(level: Double) -> CGFloat {
        CGFloat(level) * fontScaleBase
    }

    static func bodyLineHeight(fontSize: CGFloat, level: Double) -> CGFloat {
        fontSize * lineHeightMultiplier(level: level)
    }

    static let defaultFontSize: CGFloat = 19
    /// 12 档字号,19 是默认档(第 4 档)。
    static let fontSizeLevels: [CGFloat] = [16, 17, 18, 19, 20, 22, 24, 27, 30, 33, 36, 40]

    /// 七档边距,默认 28,每档 +4。
    static let defaultHorizontalPadding: CGFloat = 28
    static let horizontalPaddingLevels: [CGFloat] = [16, 20, 24, 28, 32, 36, 40]

    /// 每行 18 字:346 点行宽、19 号字,放不下 19 个 19 点字(346 / 19 = 18.2)。
    /// 系统中文实际字宽略小于字号,自然排版会挤进 19 个,所以只补一点点正字距,
    /// 把每格归一到 346 / 18,不压字号、也不裁字。
    static let charactersPerLine: CGFloat = 18
    static func characterSpacing(
        fontSize: CGFloat,
        textWidth: CGFloat,
        font: UIFont? = nil
    ) -> CGFloat {
        guard charactersPerLine > 0 else { return 0 }
        // 只在默认 19 号这一档把行宽归一到 18 格;换字号后按字体的自然字宽重排,
        // 字越小一行越多,不做比例夸张的字距。
        guard abs(fontSize - defaultFontSize) < 0.01 else { return 0 }
        let font = font ?? UIFont.systemFont(ofSize: fontSize)
        let advance = ("国" as NSString).size(withAttributes: [.font: font]).width
        let targetAdvance = textWidth / charactersPerLine
        // 留 0.06 点余量,保证第 18 字刚好收在行内,第 19 字被挤到下一行。
        return max(0, targetAdvance - advance - 0.06)
    }

    /// 首行缩进两个字身 = 38 点,不跟着字距走。
    static let firstLineIndentCharacters: CGFloat = 2
    static func firstLineIndent(fontSize: CGFloat, textWidth: CGFloat) -> CGFloat {
        fontSize * firstLineIndentCharacters
    }

    /// 段间距 28;设置里的「段间距」开关打开时再加 28。
    static let baseParagraphSpacing: CGFloat = 28
    static let extraParagraphSpacing: CGFloat = 28

    /// 首行字顶(屏幕坐标)、章节名字顶、页脚字底离屏幕底。
    static let bodyTopInkY: CGFloat = 116
    static let chapterTitleTopInkY: CGFloat = 76
    static let footerBottomInset: CGFloat = 55

    /// 默认字号下的一页行数,只作为兜底;真实行数由首行框顶到页脚上沿算出。
    static let bodyLineCount: CGFloat = 20

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
    private static let fontSizeRange: ClosedRange<CGFloat> = 16...40
    private static let lineSpacingRange: ClosedRange<Double> = 1.05...1.95
    private static let paddingRange: ClosedRange<CGFloat> = 16...40
    private static let typographyVersionKey = "reader.typographyVersion"
    private static let currentTypographyVersion = 10
    private static let pageModeKey = "reader.pageMode"
    private static let pageModeExplicitKey = "reader.pageMode.explicit"
    /// 背景只存这一个键:颜色写 "color:paper",照片写 "photo:bg-sea:paper"
    /// (照片后面的颜色是上次选的颜色,照片摘掉时回到它)。
    private static let backgroundKey = "reader.background"
    private static let defaultPageMode: PageMode = .scroll

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
    /// 当前颜色。选照片时不改它:照片摘掉后「上次选的颜色」还在。
    var theme: ReaderTheme {
        didSet {
            // 颜色是「当前背景」的另一半:只要写 theme 就表示回到颜色,
            // 照片必须同时摘掉,两种背景不能同时成立。
            if backgroundPhoto != nil { backgroundPhoto = nil }
        }
    }
    /// 当前照片。非 nil 时它就是「当前背景」,theme 只负责记着上次的颜色。
    private(set) var backgroundPhoto: ReaderBackgroundPhoto?
    var pageMode: PageMode
    /// Keeps the screen awake while the reader is open. On by default.
    var keepScreenAwake: Bool
    /// 首行缩进两字,默认开。
    var firstLineIndentEnabled: Bool
    /// 段间距开关,默认关。关着也有 28 的段间距,打开再加 28。
    var paragraphSpacingEnabled: Bool

    /// 当前背景是不是照片。亮度面板的分组选中、正文颜色都看它。
    var isPhotoBackground: Bool { backgroundPhoto != nil }

    /// 正文颜色:照片背景上是 #F6F2EA,其余跟颜色主题走。
    var readingTextColor: Color {
        backgroundPhoto == nil ? theme.textColor : Color(hex: "#F6F2EA")
    }

    /// 照片背景上次要文字取正文白的 65%,不另开一套灰。
    var readingSecondaryColor: Color {
        backgroundPhoto == nil
            ? theme.secondaryColor
            : Color(hex: "#F6F2EA").opacity(0.65)
    }

    /// 照片上正文是白字,状态栏也要跟着变浅,所以外观按深色走。
    var isDarkAppearance: Bool {
        backgroundPhoto != nil || theme.isDark
    }

    /// 菜单 / 顶栏 / 面板的配色:照片背景上统一走夜间,图标和面板才看得清。
    var chromeTheme: ReaderTheme {
        backgroundPhoto == nil ? theme : .dark
    }

    /// 阅读页的底色。照片由 ReaderView 全屏铺,占位处用透明,
    /// 避免翻页边界或下拉时露出纸色。
    var pageBackgroundColor: Color {
        backgroundPhoto == nil ? theme.backgroundColor : .clear
    }

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
            // 1.0.8(10) 起档位表换成 16…40 / 1.05…1.95 / 16…40,
            // 三组默认都停在第 4 档(19 / 1.5 / 28),升级时迁到新基准。
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
        let stored = Self.loadBackground(from: defaults)
        self.theme = stored.color
        self.backgroundPhoto = stored.photo
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
        // 「当前背景」只写 reader.background 一处;reader.theme 是旧存档,不再写。
        if let photo = backgroundPhoto {
            defaults.set("photo:\(photo.rawValue):\(theme.rawValue)", forKey: Self.backgroundKey)
        } else {
            defaults.set("color:\(theme.rawValue)", forKey: Self.backgroundKey)
        }
        // 旧键不再写也不留:读的时候还会认,存的时候只保留 reader.background 这一个值。
        defaults.removeObject(forKey: "reader.theme")
        defaults.set(pageMode.rawValue, forKey: Self.pageModeKey)
        defaults.set(keepScreenAwake, forKey: "reader.keepScreenAwake")
        defaults.set(firstLineIndentEnabled, forKey: "reader.firstLineIndent")
        defaults.set(paragraphSpacingEnabled, forKey: "reader.paragraphSpacing")
        defaults.set(Self.currentTypographyVersion, forKey: Self.typographyVersionKey)
        if markPageModeExplicit {
            defaults.set(true, forKey: Self.pageModeExplicitKey)
        }
    }

    /// 选颜色:照片先摘掉,再把颜色换过去。写 theme 时 didSet 也会同步清照片。
    func selectColour(_ colour: ReaderTheme) {
        backgroundPhoto = nil
        theme = colour
        save()
    }

    /// 选照片:只改照片,不动 theme——这样「上次选的颜色」还留着。
    func selectPhoto(_ photo: ReaderBackgroundPhoto) {
        backgroundPhoto = photo
        save()
    }

    /// 旧存档只有 reader.theme;新存档读 reader.background。
    /// 「青灰」这类已经不在表里的值一律落回米黄。
    private static func loadBackground(
        from defaults: UserDefaults
    ) -> (color: ReaderTheme, photo: ReaderBackgroundPhoto?) {
        let legacy = ReaderTheme(rawValue: defaults.string(forKey: "reader.theme") ?? "") ?? .paper
        guard let raw = defaults.string(forKey: backgroundKey) else {
            return (legacy, nil)
        }
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        switch parts.first {
        case "photo":
            let photo = parts.count > 1 ? ReaderBackgroundPhoto(rawValue: parts[1]) : nil
            let color = parts.count > 2
                ? (ReaderTheme(rawValue: parts[2]) ?? .paper)
                : legacy
            return (color, photo)
        case "color":
            let color = parts.count > 1 ? (ReaderTheme(rawValue: parts[1]) ?? .paper) : .paper
            return (color, nil)
        default:
            return (legacy, nil)
        }
    }

    private static func loadPageMode(from defaults: UserDefaults) -> PageMode {
        guard let rawValue = defaults.string(forKey: pageModeKey),
              let savedMode = PageMode(rawValue: rawValue) else {
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

/// 中文标点禁则断行。
///
/// 排版测量、分页和渲染必须共用同一套断行结果:这里按行做贪心装箱,
/// 装箱边界落在禁则字符上时把前一个字一起挪到下一行,再把算好的行
/// 用硬换行拼回去。这样 TextKit 渲染时不会再自行改断点,页数和实际
/// 显示就不会错位。
enum ReaderLineBreaker {
    /// 不能出现在行首的标点(中英文、全角/半角)。
    static let forbiddenLineStart: Set<Character> = [
        "。", "，", "、", "；", "：", "？", "！", "）", "］", "｝",
        "」", "』", "》", "〉", "】", "％", "%",
        ",", ".", ";", ":", "?", "!", ")", "]",
        "”", "’"
    ]

    /// 不能出现在行尾的标点(中英文、全角/半角)。
    static let forbiddenLineEnd: Set<Character> = [
        "（", "［", "｛", "「", "『", "《", "〈", "【",
        "(", "[", "“", "‘"
    ]

    /// 把一段文字断成显示行。已有的硬换行会保留;`firstLineIndent`
    /// 只作用于整段的第一行。`attributes` 只带字体/字距,不要带
    /// `firstLineHeadIndent`,缩进由参数单独控制,避免重复扣减。
    static func lines(
        in text: String,
        width: CGFloat,
        firstLineIndent: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> [String] {
        guard width > 1 else { return [text] }
        var result: [String] = []
        var isFirstLine = true

        for segment in text.components(separatedBy: "\n") where !segment.isEmpty {
            let indent = isFirstLine ? min(max(0, firstLineIndent), width - 1) : 0
            result.append(contentsOf: breakSegment(
                segment,
                width: width,
                firstLineIndent: indent,
                attributes: attributes
            ))
            isFirstLine = false
        }
        return result.isEmpty ? [text] : result
    }

    private static func breakSegment(
        _ text: String,
        width: CGFloat,
        firstLineIndent: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> [String] {
        let characters = Array(text)
        guard !characters.isEmpty else { return [] }

        let attributed = NSAttributedString(string: text, attributes: attributes)
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)

        // Character 下标到 UTF-16 下标的映射,CTTypesetter 用的是后者。
        var utf16Starts: [Int] = []
        utf16Starts.reserveCapacity(characters.count + 1)
        var utf16Location = 0
        for character in characters {
            utf16Starts.append(utf16Location)
            utf16Location += String(character).utf16.count
        }
        utf16Starts.append(utf16Location)

        // 半角双引号本身分不出左右,按出现顺序交替判断。
        var isOpeningQuote = [Bool](repeating: false, count: characters.count)
        var quoteOpen = true
        for index in characters.indices where characters[index] == "\"" {
            isOpeningQuote[index] = quoteOpen
            quoteOpen.toggle()
        }

        var lines: [String] = []
        var lineStart = 0
        var firstLine = true

        while lineStart < characters.count {
            let available = firstLine ? max(1, width - firstLineIndent) : width
            // 优先按词断行:英文单词不会被拆成两半;中文没有词间空格时
            // 仍会落在一个字簇的边界上。没有可用断点(超长单词)再退回字簇。
            var suggested = CTTypesetterSuggestLineBreak(
                typesetter,
                utf16Starts[lineStart],
                available
            )
            if suggested <= 0 {
                suggested = CTTypesetterSuggestClusterBreak(
                    typesetter,
                    utf16Starts[lineStart],
                    available
                )
            }
            if suggested <= 0 {
                suggested = max(1, String(characters[lineStart]).utf16.count)
            }
            let target = utf16Starts[lineStart] + suggested

            var lineEnd = lineStart
            while lineEnd < characters.count, utf16Starts[lineEnd + 1] <= target {
                lineEnd += 1
            }
            if lineEnd <= lineStart {
                lineEnd = lineStart + 1
            }

            lineEnd = adjustedBreak(
                characters,
                isOpeningQuote: isOpeningQuote,
                start: lineStart,
                end: lineEnd
            )
            lines.append(String(characters[lineStart..<lineEnd]))
            lineStart = lineEnd
            firstLine = false
        }
        return lines
    }

    /// 遇到行首禁则字符(或行尾禁则字符)就把断点往回挪。
    /// 英文标点前会尽量带上整个单词,但不把整行挪空。
    private static func adjustedBreak(
        _ characters: [Character],
        isOpeningQuote: [Bool],
        start: Int,
        end: Int
    ) -> Int {
        var lineEnd = end
        while true {
            var moved = false

            if lineEnd < characters.count,
               isForbiddenAtLineStart(characters, isOpeningQuote: isOpeningQuote, index: lineEnd),
               lineEnd > start + 1 {
                var candidate = lineEnd - 1
                while candidate > start, isASCIIWordCharacter(characters[candidate - 1]) {
                    candidate -= 1
                }
                if candidate <= start {
                    candidate = start + 1
                }
                if candidate < lineEnd {
                    lineEnd = candidate
                    moved = true
                }
            }

            if lineEnd > start + 1,
               isForbiddenAtLineEnd(characters, isOpeningQuote: isOpeningQuote, index: lineEnd - 1) {
                lineEnd -= 1
                moved = true
            }

            if !moved { break }
        }
        return max(lineEnd, start + 1)
    }

    private static func isForbiddenAtLineStart(
        _ characters: [Character],
        isOpeningQuote: [Bool],
        index: Int
    ) -> Bool {
        let character = characters[index]
        if character == "\"" {
            return !isOpeningQuote[index]
        }
        return forbiddenLineStart.contains(character)
    }

    private static func isForbiddenAtLineEnd(
        _ characters: [Character],
        isOpeningQuote: [Bool],
        index: Int
    ) -> Bool {
        let character = characters[index]
        if character == "\"" {
            return isOpeningQuote[index]
        }
        return forbiddenLineEnd.contains(character)
    }

    private static func isASCIIWordCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }
}
