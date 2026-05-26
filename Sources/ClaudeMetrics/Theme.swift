import SwiftUI

extension Color {
    static let appBg          = Color(red: 0.047, green: 0.047, blue: 0.063)
    static let appSidebar     = Color(red: 0.055, green: 0.055, blue: 0.075)
    static let appSurface     = Color(red: 0.086, green: 0.086, blue: 0.110)
    static let appBorder      = Color(red: 0.145, green: 0.145, blue: 0.188)
    static let appAccent      = Color(red: 0.486, green: 0.416, blue: 0.969)
    static let appGold        = Color(red: 0.950, green: 0.780, blue: 0.220)

    static let appTextPrimary   = Color.white
    static let appTextSecondary = Color(white: 0.55)
    static let appTextTertiary  = Color(white: 0.35)

    static let modelOpus   = Color(red: 0.612, green: 0.384, blue: 0.922)
    static let modelSonnet = Color(red: 0.275, green: 0.565, blue: 0.902)
    static let modelHaiku  = Color(red: 0.306, green: 0.784, blue: 0.471)

    static func forModel(_ model: String) -> Color {
        if model.contains("opus")   { return .modelOpus }
        if model.contains("haiku")  { return .modelHaiku }
        return .modelSonnet
    }
}

func formatTokens(_ n: Int) -> String {
    switch n {
    case let x where x >= 1_000_000_000: return String(format: "%.1fB", Double(x) / 1_000_000_000)
    case let x where x >= 1_000_000:     return String(format: "%.1fM", Double(x) / 1_000_000)
    case let x where x >= 1_000:         return String(format: "%.1fK", Double(x) / 1_000)
    default: return "\(n)"
    }
}

func formatCost(_ cost: Double) -> String {
    if cost >= 1000  { return String(format: "$%.1fK", cost / 1000) }
    if cost >= 1     { return String(format: "$%.2f", cost) }
    if cost >= 0.001 { return String(format: "$%.3f", cost) }
    return String(format: "$%.4f", cost)
}

func modelDisplayName(_ model: String) -> String {
    model
        .replacingOccurrences(of: "claude-", with: "")
        .replacingOccurrences(of: "-20250929", with: "")
        .replacingOccurrences(of: "-20251001", with: "")
        .split(separator: "-")
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        .joined(separator: " ")
}
