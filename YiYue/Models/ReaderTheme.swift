import SwiftUI

enum ReaderTheme: String, CaseIterable, Codable {
    case paper
    case white
    case green
    case blueGray
    case dark

    // MARK: - 五套主题(名字与色值见 reader-chrome-replica-spec §7)

    var backgroundHex: String {
        switch self {
        case .paper: return "#F6F0E4"
        case .white: return "#FFFFFF"
        case .green: return "#DEE8D5"
        case .blueGray: return "#E7EDF1"
        case .dark: return "#121212"
        }
    }

    var textHex: String {
        switch self {
        case .paper: return "#2A2017"
        case .white: return "#1B1B1D"
        case .green: return "#23301F"
        case .blueGray: return "#1F2A33"
        case .dark: return "#D4D4D4"
        }
    }

    /// 页脚、标签、章节名共用这一档次要色。
    var secondaryHex: String {
        switch self {
        case .paper: return "#6B6153"
        case .white: return "#6E6E73"
        case .green: return "#55634E"
        case .blueGray: return "#556571"
        case .dark: return "#8A8A8A"
        }
    }

    /// 强调色:当前章、书签丝带、选字手柄、选中格和进度环都用它。
    var accentHex: String {
        switch self {
        case .paper: return "#9A4A31"
        case .white: return "#9A4A31"
        case .green: return "#8A4B2A"
        case .blueGray: return "#9A4A31"
        case .dark: return "#C9825C"
        }
    }

    /// 菜单分隔线 / 面板描边。
    var separatorHex: String {
        switch self {
        case .paper: return "#E0D6C2"
        case .white: return "#E5E5EA"
        case .green: return "#CBD8C0"
        case .blueGray: return "#D2DBE2"
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
        case .blueGray: return "#DFE6EB"
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
        case .paper: return "纸色"
        case .white: return "纯白"
        case .green: return "护眼绿"
        case .blueGray: return "青灰"
        case .dark: return "夜间"
        }
    }

    var isDark: Bool {
        self == .dark
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
