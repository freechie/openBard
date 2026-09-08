import SwiftUI

struct AbletonTheme {
    let background: Color
    let surface: Color
    let surfaceElevated: Color
    let border: Color
    
    let textPrimary: Color
    let textSecondary: Color
    
    let accent: Color
    let accentDim: Color
    
    let noteFill: Color
    let noteSelected: Color
    let noteLocked: Color
    
    let danger: Color
    let success: Color
    
    let gridLine: Color
    let pianoRollBackground: Color
    
    static let dark = AbletonTheme(
        background: Color(hex: 0x1A1A1A),
        surface: Color(hex: 0x262626),
        surfaceElevated: Color(hex: 0x2E2E2E),
        border: Color(hex: 0x3A3A3A),
        textPrimary: Color(hex: 0xE8E8E8),
        textSecondary: Color(hex: 0x8C8C8C),
        accent: Color(hex: 0xFF7A39),
        accentDim: Color(hex: 0xCC5F2D),
        noteFill: Color(hex: 0x6B9BCF),
        noteSelected: Color(hex: 0xFF7A39),
        noteLocked: Color(hex: 0x4CAF50),
        danger: Color(hex: 0xE74C3C),
        success: Color(hex: 0x4CAF50),
        gridLine: Color(hex: 0x303030),
        pianoRollBackground: Color(hex: 0x1E1E1E)
    )
    
    static let light = AbletonTheme(
        background: Color(hex: 0xE8E8E8),
        surface: Color(hex: 0xF5F5F5),
        surfaceElevated: Color(hex: 0xFFFFFF),
        border: Color(hex: 0xD0D0D0),
        textPrimary: Color(hex: 0x2A2A2A),
        textSecondary: Color(hex: 0x707070),
        accent: Color(hex: 0xFF7A39),
        accentDim: Color(hex: 0xE56830),
        noteFill: Color(hex: 0x5A8AC0),
        noteSelected: Color(hex: 0xFF7A39),
        noteLocked: Color(hex: 0x43A047),
        danger: Color(hex: 0xD32F2F),
        success: Color(hex: 0x43A047),
        gridLine: Color(hex: 0xD8D8D8),
        pianoRollBackground: Color(hex: 0xFAFAFA)
    )
    
    static func current(for colorScheme: ColorScheme) -> AbletonTheme {
        colorScheme == .dark ? .dark : .light
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
