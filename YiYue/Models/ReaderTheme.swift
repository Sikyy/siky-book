import SwiftUI

/// 背景是一个值:要么四色之一,要么五张照片之一(「已定的实现口径」)。
/// 顺序就是亮度面板里的顺序:白色、米黄、护眼绿、夜间。
/// 青灰已撤:旧存档里的 "blueGray" 解析不出来,统一回落到米黄。
enum ReaderTheme: String, CaseIterable, Codable {
    case paper
    case white
    case green
    case dark

    /// 亮度面板的四格顺序:白、米黄、护眼绿、夜间。
    /// allCases 保持旧顺序不动,设置页那行就不会因为这一版换排列。
    static let palette: [ReaderTheme] = [.white, .paper, .green, .dark]

    // MARK: - 四套颜色(名字与色值见 design-diff-16 §4)

    var backgroundHex: String {
        switch self {
        case .white: return "#FFFFFF"
        case .paper: return "#F7F0DF"
        case .green: return "#CCF0CF"
        case .dark: return "#121212"
        }
    }

    var textHex: String {
        switch self {
        case .white: return "#1B1B1D"
        case .paper: return "#2A2017"
        case .green: return "#23301F"
        case .dark: return "#D4D4D4"
        }
    }

    /// 页脚、标签、章节名共用这一档次要色。
    var secondaryHex: String {
        switch self {
        case .white: return "#6E6E73"
        case .paper: return "#6B6153"
        case .green: return "#55634E"
        case .dark: return "#8A8A8A"
        }
    }

    /// 强调色:当前章、书签丝带、选字手柄、选中格和进度环都用它。
    var accentHex: String {
        switch self {
        case .white, .paper: return "#9A4A31"
        case .green: return "#8A4B2A"
        case .dark: return "#C9825C"
        }
    }

    /// 菜单分隔线 / 面板描边。
    var separatorHex: String {
        switch self {
        case .white: return "#E5E5EA"
        case .paper: return "#E0D6C2"
        case .green: return "#CBD8C0"
        case .dark: return "#2A2A2C"
        }
    }

    var backgroundColor: Color { Self.color(backgroundHex) }
    var textColor: Color { Self.color(textHex) }
    var secondaryColor: Color { Self.color(secondaryHex) }
    var accentColor: Color { Self.color(accentHex) }
    var separatorColor: Color { Self.color(separatorHex) }

    var chapterTitleColor: Color { secondaryColor }
    var statusBarColor: Color { secondaryColor }

    /// 菜单开(只有顶栏图标、没有面板)时,顶栏底下那条 0–100 的实色带。
    /// 夜间是 #131314,正文底是纯黑,所以带子要单独给一个值,不能用纸色。
    var topBarBandHex: String {
        switch self {
        // TODO(浅色带待设计定值): 浅色主题的带色还没有设计值,先按纸色深一档压。
        case .paper: return "#EFE8DA"
        case .white: return "#F7F7F7"
        case .green: return "#D7E1CE"
        case .dark: return "#131314"
        }
    }

    var topBarBand: Color { Self.color(topBarBandHex) }

    // MARK: - Menu (reader overlay)

    /// 菜单是不透明面板,不用 material,浅色主题上也不会泛灰。
    var menuBackgroundHex: String {
        isDark ? "#1C1C1E" : backgroundHex
    }

    /// Fully opaque: the page underneath must not show through the menu panels.
    var menuBackground: Color { Self.color(menuBackgroundHex) }
    var menuPrimary: Color { textColor }
    var menuSecondary: Color { secondaryColor }
    var menuDisabled: Color { textColor.opacity(0.3) }
    var menuSelectedFill: Color { textColor.opacity(0.08) }
    var menuUnselectedFill: Color { Color.clear }
    var menuSeparator: Color { separatorColor }

    // Pre-computed color cache — avoids hex parsing on every access
    private static let colorCache: [String: Color] = {
        var cache: [String: Color] = [:]
        for theme in ReaderTheme.allCases {
            for hex in [
                theme.backgroundHex,
                theme.textHex,
                theme.secondaryHex,
                theme.accentHex,
                theme.separatorHex,
                theme.menuBackgroundHex,
                theme.topBarBandHex
            ] {
                cache[hex.lowercased()] = Color(hex: hex)
            }
        }
        return cache
    }()

    private static func color(_ hex: String) -> Color {
        colorCache[hex.lowercased()] ?? Color(hex: hex)
    }

    var displayName: String {
        switch self {
        case .white: return "白色"
        case .paper: return "米黄"
        case .green: return "护眼绿"
        case .dark: return "夜间"
        }
    }

    var isDark: Bool {
        self == .dark
    }
}

/// 五张实景背景。id 就是资源名,压暗比例按 id 各给各的,
/// 不做「一个全局暗化值」——五张图本身的明度差很多。
enum ReaderBackgroundPhoto: String, CaseIterable, Codable, Identifiable {
    case mountain = "bg-mountain"
    case sea = "bg-sea"
    case night = "bg-night"
    case forest = "bg-forest"
    case warm = "bg-warm"

    var id: String { rawValue }
    var assetName: String { rawValue }

    /// 亮度面板那排 64×38 的预览只解这份缩略图(198×114,3 KB);
    /// 整幅 1200×2608 解出来一张十二三兆,四张一起解,第一次开面板要 190 毫秒。
    var thumbAssetName: String { rawValue + "-thumb" }

    /// 只做读屏名,缩略图上不写字。
    var displayName: String {
        switch self {
        case .mountain: return "远山"
        case .sea: return "海面"
        case .night: return "夜色"
        case .forest: return "林间"
        case .warm: return "暖光"
        }
    }

    /// 照片上的黑色压暗比例(design-diff-16:远山/海面 15%,夜色/林间 10%,暖光 25%)。
    var dimmingOpacity: Double {
        switch self {
        case .mountain: return 0.15
        case .sea: return 0.15
        case .night: return 0.10
        case .forest: return 0.10
        case .warm: return 0.25
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        self.init(
            red: Double((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: Double((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgbValue & 0x0000FF) / 255.0
        )
    }
}
