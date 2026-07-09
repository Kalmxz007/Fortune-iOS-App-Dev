//
//  Theme.swift
//  Fortune
//
//  Changing a color here will change it or update it everywhere else in the app.
//

import SwiftUI

extension Color {
    /// Create a color from a 0xRRGGBB hex value, e.g. Color(hex: 0x38D4FF).
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Theme {

    // MARK: Base surfaces

    static let background = Color(hex: 0x08090C)        // --background
    static let card = Color(hex: 0x111318)              // --card
    static let popover = Color(hex: 0x1A1D24)           // --popover
    static let secondary = Color(hex: 0x1A1D24)         // --secondary
    static let foreground = Color(hex: 0xE8EAED)        // --foreground
    static let secondaryForeground = Color(hex: 0xA0A8B4)
    static let mutedForeground = Color(hex: 0x6B7280)   // --muted-foreground
    static let border = Color.white.opacity(0.08)       // --border
    static let switchBackground = Color(hex: 0x2D3748)  // --switch-background

    // MARK: Brand colors

    static let primary = Color(hex: 0x38D4FF)           // cyan  (--primary)
    static let indigo = Color(hex: 0x6D74FF)            // indigo (--chart-5)
    static let accent = Color(hex: 0xB06AFF)            // purple (--accent)

    // MARK: Semantic colors

    static let green = Color(hex: 0x4ADE80)             // green-400
    static let emerald = Color(hex: 0x34D399)           // emerald-400
    static let red = Color(hex: 0xF87171)               // red-400
    static let destructive = Color(hex: 0xEF4444)       // --destructive

    // MARK: Gradients

    /// The  cyan → indigo → purple brand gradient.
    static let brandGradient = LinearGradient(
        colors: [primary, indigo, accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let buyGradient = LinearGradient(
        colors: [Color(hex: 0x16A34A), Color(hex: 0x22C55E)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let sellGradient = LinearGradient(
        colors: [Color(hex: 0xDC2626), Color(hex: 0xEF4444)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Font {
    /// `.custom("JetBrainsMono-Regular", size: size)`.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Double {
    func money(_ decimals: Int = 2) -> String {
        formatted(.number.precision(.fractionLength(decimals)))
    }

    var signPrefix: String { self >= 0 ? "+" : "" }
}
