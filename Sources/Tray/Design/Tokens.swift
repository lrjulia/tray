import AppKit
import SwiftUI

// Tray design tokens, mirrored from the Tray design system (tokens.json).
// Every view reads colors, type, spacing and radii from here — never literal values —
// so Appearance and Accent settings restyle the whole app at once.

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// A color that resolves per appearance (light / dark), like an asset-catalog color.
    static func tray(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

extension Color {
    static func tray(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: .tray(light: NSColor(hex: light, alpha: lightAlpha), dark: NSColor(hex: dark, alpha: darkAlpha)))
    }

    static func fixed(_ hex: UInt32) -> Color {
        Color(nsColor: NSColor(hex: hex))
    }
}

enum Tokens {
    // MARK: Color
    enum C {
        static let surface = Color.tray(0xF6F5F2, 0x1C1C1E)
        static let surfaceRaised = Color.tray(0xFFFFFF, 0x2A2A2D)
        static let surfaceSunken = Color.tray(0xECEBE7, 0x141416)
        static let line = Color.tray(0xDCDAD4, 0x3A3A3E)
        static let lineStrong = Color.tray(0x8A877F, 0x73737A)
        static let ink = Color.tray(0x1D1C1A, 0xF2F1EE)
        static let inkMuted = Color.tray(0x5C5953, 0xAAA8A2)
        static let onAccent = Color.tray(0xFFFFFF, 0x1D1C1A)
        static let danger = Color.tray(0xB91C1C, 0xF87171)
        static let dangerSoft = Color.tray(0xFBE4E2, 0x3D1D1D)

        static let kindText = Color.fixed(0x57534E)
        static let kindLink = Color.fixed(0x1D4ED8)
        static let kindImage = Color.fixed(0x047857)
        static let kindCode = Color.fixed(0x9D174D)
        static let kindFile = Color.fixed(0x0E7490)
        static let onKind = Color.fixed(0xFFFFFF)
    }

    // MARK: Type (system font at macOS sizes)
    enum T {
        static let title = Font.system(size: 22, weight: .bold)
        static let headline = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13)
        static let callout = Font.system(size: 12)
        static let caption = Font.system(size: 11)
        static let captionStrong = Font.system(size: 11, weight: .semibold)
        static let snippet = Font.system(size: 12, design: .monospaced)
        static let search = Font.system(size: 17)
    }

    // MARK: Spacing (4px grid)
    enum S {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s6: CGFloat = 24
        static let s8: CGFloat = 32
    }

    // MARK: Radius
    enum R {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
    }

    // MARK: Size
    enum Size {
        static let cardSize: CGFloat = 216
        static let rowHeight: CGFloat = 32
        static let rowHeightComfortable: CGFloat = 40
        static let windowWidth: CGFloat = 920
        static let windowHeight: CGFloat = 600
        static let listWidth: CGFloat = 360
    }
}

// MARK: - Accent options

/// The seven tested accent options. Each passes 5.2:1 with `onAccent` and 4.3:1 as a ring on every surface.
enum AccentOption: String, Codable, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, green, graphite

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var hex: (light: UInt32, dark: UInt32) {
        switch self {
        case .blue: return (0x1F5FCC, 0x6BA4FF)
        case .purple: return (0x7040D6, 0xB597FF)
        case .pink: return (0xB8236F, 0xF585BD)
        case .red: return (0xC42727, 0xFF8A80)
        case .orange: return (0xB84A0E, 0xFF9D5C)
        case .green: return (0x1E7A3C, 0x5FD38A)
        case .graphite: return (0x57534E, 0xB5B2AB)
        }
    }

    var color: Color { Color.tray(hex.light, hex.dark) }
    /// The accent at 12% (light) / 18% (dark) — `accent-soft`.
    var soft: Color { Color.tray(hex.light, hex.dark, lightAlpha: 0.12, darkAlpha: 0.18) }

    /// Nearest option to the macOS accent color, so "Follow macOS" keeps contrast safe.
    static func nearestToSystem() -> AccentOption {
        guard let c = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return .blue }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if s < 0.15 { return .graphite }
        switch h {
        case ..<0.03, 0.95...: return .red
        case 0.03..<0.2: return .orange
        case 0.2..<0.45: return .green
        case 0.45..<0.72: return .blue
        case 0.72..<0.85: return .purple
        default: return .pink
        }
    }
}

enum PinColor: String, Codable, CaseIterable, Identifiable {
    case sky, grass, rose, slate
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .sky: return .fixed(0x0284C7)
        case .grass: return .fixed(0x15803D)
        case .rose: return .fixed(0xE11D48)
        case .slate: return .fixed(0x64748B)
        }
    }
}
