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

    var chapterTitleColor: Color {
        switch self {
        case .paper: return Self.colorCache["#9a8e7e"]!
        case .white: return Self.colorCache["#999999"]!
        case .dark: return Self.colorCache["#555555"]!
        }
    }

    var statusBarColor: Color {
        switch self {
        case .paper: return Self.colorCache["#b0a494"]!
        case .white: return Self.colorCache["#aaaaaa"]!
        case .dark: return Self.colorCache["#3a3a3a"]!
        }
    }

    // Pre-computed color cache — avoids hex parsing on every access
    private static let colorCache: [String: Color] = {
        let hexes = [
            "#f5efe4", "#ffffff", "#121212",
            "#2b2017", "#1a1a1a", "#d4d4d4",
            "#9a8e7e", "#999999", "#555555",
            "#b0a494", "#aaaaaa", "#3a3a3a"
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
