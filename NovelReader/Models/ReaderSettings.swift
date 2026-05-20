import SwiftUI

enum FontFamily: String, CaseIterable, Codable {
    case pingfang = "PingFang SC"
    case songti = "Songti SC"
    case kaiti = "Kaiti SC"

    var displayName: String {
        switch self {
        case .pingfang: return "苹方"
        case .songti: return "宋体"
        case .kaiti: return "楷体"
        }
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
}

@Observable
class ReaderSettings {
    private static let fontSizeRange: ClosedRange<CGFloat> = 12...32
    private static let lineSpacingRange: ClosedRange<Double> = 1.5...2.5
    private static let paddingRange: ClosedRange<CGFloat> = 16...48

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

    private var _fontSize: CGFloat = 17
    private var _lineSpacing: Double = 2.0
    private var _horizontalPadding: CGFloat = 28

    var fontFamily: FontFamily
    var theme: ReaderTheme
    var pageMode: PageMode

    init() {
        let defaults = UserDefaults.standard
        self._fontSize = CGFloat(defaults.double(forKey: "reader.fontSize")).nonZeroOr(17)
        self._lineSpacing = defaults.double(forKey: "reader.lineSpacing").nonZeroOr(2.0)
        self._horizontalPadding = CGFloat(defaults.double(forKey: "reader.horizontalPadding")).nonZeroOr(28)
        self.fontFamily = FontFamily(rawValue: defaults.string(forKey: "reader.fontFamily") ?? "") ?? .pingfang
        self.theme = ReaderTheme(rawValue: defaults.string(forKey: "reader.theme") ?? "") ?? .pureBlack
        self.pageMode = PageMode(rawValue: defaults.string(forKey: "reader.pageMode") ?? "") ?? .scroll
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Double(fontSize), forKey: "reader.fontSize")
        defaults.set(lineSpacing, forKey: "reader.lineSpacing")
        defaults.set(Double(horizontalPadding), forKey: "reader.horizontalPadding")
        defaults.set(fontFamily.rawValue, forKey: "reader.fontFamily")
        defaults.set(theme.rawValue, forKey: "reader.theme")
        defaults.set(pageMode.rawValue, forKey: "reader.pageMode")
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
