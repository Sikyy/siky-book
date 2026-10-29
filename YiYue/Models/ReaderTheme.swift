import SwiftUI

enum ReaderTheme: String, CaseIterable, Codable {
    case paper
    case white
    case dark

    var backgroundHex: String {
        switch self {
        case .paper: return "#f5efe4"
        case .white: return "#ffffff"
        case .dark: return "#121212"
        }
    }

    var textHex: String {
        switch self {
        case .paper: return "#2b2017"
        case .white: return "#1a1a1a"
        case .dark: return "#d4d4d4"
        }
    }

    var backgroundColor: Color { Self.colorCache[backgroundHex]! }
    var textColor: Color { Self.colorCache[textHex]! }

    /// Chapter title and footer share one secondary colour, at least 4.5:1 on this theme's background.
    var chapterTitleColor: Color {
        switch self {
        case .paper: return Self.colorCache["#6b6153"]!
        case .white: return Self.colorCache["#767676"]!
        case .dark: return Self.colorCache["#808080"]!
        }
    }

    var statusBarColor: Color { chapterTitleColor }

    // MARK: - Menu (reader overlay)

    /// The menu is a solid theme-coloured panel, not a material, so it never turns grey over light themes.
    var menuBackgroundHex: String {
        switch self {
        case .paper: return "#f5efe4"
        case .white: return "#ffffff"
        case .dark: return "#1c1c1c"
        }
    }

    var menuBackground: Color { Self.colorCache[menuBackgroundHex]!.opacity(0.96) }
    var menuPrimary: Color { textColor }
    var menuSecondary: Color { textColor.opacity(0.55) }
    var menuDisabled: Color { textColor.opacity(0.3) }
    var menuSelectedFill: Color { textColor.opacity(0.08) }
    var menuUnselectedFill: Color { Color.clear }
    var menuSeparator: Color { isDark ? Color.white.opacity(0.1) : textColor.opacity(0.12) }

    // Pre-computed color cache — avoids hex parsing on every access
    private static let colorCache: [String: Color] = {
        let hexes = [
            "#f5efe4", "#ffffff", "#121212",
            "#2b2017", "#1a1a1a", "#d4d4d4",
            "#6b6153", "#767676", "#808080",
            "#1c1c1c"
        ]
        var cache: [String: Color] = [:]
        for hex in hexes {
            cache[hex] = Color(hex: hex)
        }
        return cache
    }()

    var displayName: String {
        switch self {
        case .paper: return "纸质"
        case .white: return "白色"
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
