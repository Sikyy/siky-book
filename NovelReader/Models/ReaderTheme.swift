import SwiftUI

enum ReaderTheme: String, CaseIterable, Codable {
    case pureBlack
    case warmBlack
    case lightWhite
    case eyeCareGreen
    case system

    var backgroundHex: String {
        switch self {
        case .pureBlack: return "#121212"
        case .warmBlack: return "#1a1814"
        case .lightWhite: return "#f5f5f0"
        case .eyeCareGreen: return "#c7edcc"
        case .system: return "#121212"
        }
    }

    var textHex: String {
        switch self {
        case .pureBlack: return "#d4d4d4"
        case .warmBlack: return "#c8b89a"
        case .lightWhite: return "#2c2c2c"
        case .eyeCareGreen: return "#2c3e2c"
        case .system: return "#d4d4d4"
        }
    }

    var backgroundColor: Color {
        Color(hex: backgroundHex)
    }

    var textColor: Color {
        Color(hex: textHex)
    }

    var chapterTitleColor: Color {
        switch self {
        case .lightWhite, .eyeCareGreen: return Color(hex: "#999999")
        default: return Color(hex: "#555555")
        }
    }

    var statusBarColor: Color {
        switch self {
        case .lightWhite, .eyeCareGreen: return Color(hex: "#aaaaaa")
        default: return Color(hex: "#3a3a3a")
        }
    }

    var displayName: String {
        switch self {
        case .pureBlack: return "纯黑"
        case .warmBlack: return "暖黑"
        case .lightWhite: return "浅白"
        case .eyeCareGreen: return "护眼绿"
        case .system: return "跟随系统"
        }
    }

    var isDark: Bool {
        switch self {
        case .pureBlack, .warmBlack: return true
        case .lightWhite, .eyeCareGreen: return false
        case .system: return true
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
