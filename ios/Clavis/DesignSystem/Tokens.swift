// ─────────────────────────────────────────────────────────────
// Tokens.swift
// Clavix design tokens for SwiftUI. Pasted from design_handoff_clavix/tokens/Tokens.swift
// (source of truth: tokens.json). Uses @Observable per the bundle spec
// (deployment target is iOS 17+).
//
// This is the canonical token source. The older App/ClavixDesignTokens.swift
// `clavix*` palette remains for legacy views and will be migrated over time.
// All NEW views must use Color.cxInk, CXSpace.lg, CXType.sectionTitle.font, etc.
// ─────────────────────────────────────────────────────────────

import SwiftUI

// MARK: - Color palette ----------------------------------------------------

extension Color {
    // Ink (foreground)
    static let cxInk   = clavixAdaptive(light: "#1A1814", dark: "#E8E6DF")
    static let cxInk2  = clavixAdaptive(light: "#3A342B", dark: "#BFC0BC")
    static let cxInk3  = clavixAdaptive(light: "#6B6357", dark: "#9A9C98")
    static let cxInk4  = clavixAdaptive(light: "#A39B8D", dark: "#5C6068")
    static let cxInk5  = clavixAdaptive(light: "#C8C0B0", dark: "#44464C")

    // Paper (background)
    static let cxCanvas = clavixAdaptive(light: "#F0EADB", dark: "#0E0F12")
    static let cxPage   = clavixAdaptive(light: "#F7F2E6", dark: "#0E0F12")
    static let cxPaper  = clavixAdaptive(light: "#FFFDF7", dark: "#16181D")
    static let cxPaper2 = clavixAdaptive(light: "#F3EDE0", dark: "#1E2127")

    // Hairlines
    static let cxRule  = clavixAdaptive(light: "#D6CEBD", dark: "#2A2C31")
    static let cxRule2 = clavixAdaptive(light: "#E6DFCF", dark: "#202227")

    // Accent — Ink Blue (default; runtime-swappable via `Theme.accent`)
    static let cxAccent     = clavixAdaptive(light: "#1D3A6E", dark: "#E8E6DF")
    static let cxAccentSoft = clavixAdaptive(light: "#E3E9F3", dark: "#1E2127")
    static let cxAccentInk  = clavixAdaptive(light: "#11264A", dark: "#E8E6DF")

    // Risk — bond-grade, never neon
    static let cxGood      = clavixAdaptive(light: "#1F6F43", dark: "#3FB984")
    static let cxGoodSoft  = clavixAdaptive(light: "#DDE9D8", dark: "#10342B")
    static let cxGoodInk   = clavixAdaptive(light: "#0D4A2A", dark: "#3FB984")

    static let cxWarn      = clavixAdaptive(light: "#9A6B1A", dark: "#E0A33E")
    static let cxWarnSoft  = clavixAdaptive(light: "#F1E3C2", dark: "#3A2B12")
    static let cxWarnInk   = clavixAdaptive(light: "#5A3E0C", dark: "#E0A33E")

    static let cxBad       = clavixAdaptive(light: "#8E1F1F", dark: "#E2604A")
    static let cxBadSoft   = clavixAdaptive(light: "#F0D8D4", dark: "#3A1A12")
    static let cxBadInk    = clavixAdaptive(light: "#5E1313", dark: "#E2604A")
}

enum ClavixDark {
    static let ink   = Color(cxHex: 0xE8E6DF)
    static let ink2  = Color(cxHex: 0xBFC0BC)
    static let ink3  = Color(cxHex: 0x9A9C98)
    static let ink4  = Color(cxHex: 0x5C6068)
    static let ink5  = Color(cxHex: 0x44464C)

    static let canvas = Color(cxHex: 0x0E0F12)
    static let page   = Color(cxHex: 0x0E0F12)
    static let paper  = Color(cxHex: 0x16181D)
    static let paper2 = Color(cxHex: 0x1E2127)

    static let rule   = Color(cxHex: 0x2A2C31)
    static let rule2  = Color(cxHex: 0x202227)

    static let accentSoft = Color(cxHex: 0x1E2127)
    static let goodSoft   = Color(cxHex: 0x10342B)
    static let warnSoft   = Color(cxHex: 0x3A2B12)
    static let badSoft    = Color(cxHex: 0x3A1A12)
}

enum ClavixAccent: String, CaseIterable, Identifiable {
    case inkBlue     = "Ink Blue"
    case burntOrange = "Burnt Orange"
    case forest      = "Forest"
    case bordeaux    = "Bordeaux"

    var id: String { rawValue }

    var accent: Color {
        switch self {
        case .inkBlue:     return Color(cxHex: 0x1D3A6E)
        case .burntOrange: return Color(cxHex: 0xB34A14)
        case .forest:      return Color(cxHex: 0x1F5B3A)
        case .bordeaux:    return Color(cxHex: 0x7A1E2C)
        }
    }
    var accentSoft: Color {
        switch self {
        case .inkBlue:     return Color(cxHex: 0xE3E9F3)
        case .burntOrange: return Color(cxHex: 0xF5E2D2)
        case .forest:      return Color(cxHex: 0xDDE9D8)
        case .bordeaux:    return Color(cxHex: 0xEFD9DD)
        }
    }
    var accentInk: Color {
        switch self {
        case .inkBlue:     return Color(cxHex: 0x11264A)
        case .burntOrange: return Color(cxHex: 0x7A3208)
        case .forest:      return Color(cxHex: 0x0D3A22)
        case .bordeaux:    return Color(cxHex: 0x4A0F1C)
        }
    }
}

extension Color {
    /// `Color(cxHex: 0x1D3A6E)` — 6-digit RGB literal. Named `cxHex:` to avoid
    /// colliding with the existing `Color(hex: "#...")` initializer that takes
    /// a string and lives in App/ClavixDesignTokens.swift.
    init(cxHex: UInt32, alpha: Double = 1.0) {
        let r = Double((cxHex >> 16) & 0xFF) / 255
        let g = Double((cxHex >>  8) & 0xFF) / 255
        let b = Double( cxHex        & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Typography -------------------------------------------------------

/// Source Serif 4 / Inter / JetBrains Mono are registered via
/// `Info.plist > UIAppFonts`. Existing ClavisTypography helpers register the
/// same files; these enums simply offer the bundle's canonical naming.
enum CXFont {
    static func serif(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom("SourceSerif4-\(weight.serifSuffix)", size: size)
    }
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Inter-\(weight.sansSuffix)", size: size)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("JetBrainsMono-\(weight.monoSuffix)", size: size)
    }
}

private extension Font.Weight {
    var serifSuffix: String {
        switch self {
        case .regular:  return "Regular"
        case .medium:   return "Medium"
        case .semibold: return "Semibold"
        case .bold:     return "Bold"
        default:        return "Regular"
        }
    }
    var sansSuffix: String {
        switch self {
        case .regular:  return "Regular"
        case .medium:   return "Medium"
        case .semibold: return "SemiBold"
        case .bold:     return "Bold"
        default:        return "Regular"
        }
    }
    var monoSuffix: String {
        switch self {
        case .regular:  return "Regular"
        case .medium:   return "Medium"
        case .semibold: return "SemiBold"
        default:        return "Regular"
        }
    }
}

struct TypeStyle {
    enum Family { case serif, sans, mono }
    let family: Family
    let size: CGFloat
    let weight: Font.Weight
    let tracking: CGFloat
    let lineHeight: CGFloat
    var uppercase: Bool = false

    var font: Font {
        switch family {
        case .serif: return CXFont.serif(size, weight: weight)
        case .sans:  return CXFont.sans(size, weight: weight)
        case .mono:  return CXFont.mono(size, weight: weight)
        }
    }
}

/// Named type styles. Sizes are in points and match the design source 1:1.
enum CXType {
    static let display         = TypeStyle(family: .serif, size: 36, weight: .medium, tracking: -0.8, lineHeight: 1.05)
    static let screenTitleLg   = TypeStyle(family: .serif, size: 32, weight: .medium, tracking: -0.6, lineHeight: 1.05)
    static let sectionTitle    = TypeStyle(family: .serif, size: 26, weight: .medium, tracking: -0.3, lineHeight: 1.10)
    static let cardHeadline    = TypeStyle(family: .serif, size: 22, weight: .medium, tracking: -0.3, lineHeight: 1.10)
    static let cardSubheadline = TypeStyle(family: .serif, size: 20, weight: .medium, tracking: -0.2, lineHeight: 1.20)
    static let bodyLarge       = TypeStyle(family: .sans,  size: 15, weight: .regular, tracking: 0,   lineHeight: 1.50)
    static let body            = TypeStyle(family: .sans,  size: 14, weight: .regular, tracking: 0,   lineHeight: 1.40)
    static let bodySmall       = TypeStyle(family: .sans,  size: 13, weight: .regular, tracking: 0,   lineHeight: 1.55)
    static let caption         = TypeStyle(family: .sans,  size: 12, weight: .regular, tracking: 0,   lineHeight: 1.45)
    static let eyebrow         = TypeStyle(family: .mono,  size: 10, weight: .bold,    tracking: 0.7, lineHeight: 1.20, uppercase: true)
    static let microCaption    = TypeStyle(family: .mono,  size: 9,  weight: .semibold, tracking: 0.5, lineHeight: 1.20)
    static let numericStat     = TypeStyle(family: .mono,  size: 26, weight: .semibold, tracking: -0.4, lineHeight: 1.00)
    static let inlineNumber    = TypeStyle(family: .mono,  size: 11, weight: .regular,  tracking: 0,   lineHeight: 1.00)
}

extension View {
    func cxType(_ style: TypeStyle) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .lineSpacing((style.lineHeight - 1) * style.size)
            .textCase(style.uppercase ? .uppercase : nil)
    }
}

// MARK: - Spacing & layout -------------------------------------------------

enum CXSpace {
    static let xxs:  CGFloat = 2
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 12
    static let lg:   CGFloat = 16
    static let xl:   CGFloat = 20
    static let xxl:  CGFloat = 24
    static let huge: CGFloat = 32

    /// Standard screen horizontal padding. Use these instead of magic numbers.
    static let screenH:      CGFloat = 20  // Today, Holdings, Ticker
    static let screenHTight: CGFloat = 16  // tab-bar adjacent
    static let screenHAuth:  CGFloat = 24  // auth / onboarding hero
}

enum CXRadius {
    static let micro: CGFloat = 2
    static let xs:    CGFloat = 3
    static let sm:    CGFloat = 4   // grade pills
    static let md:    CGFloat = 7
    static let lg:    CGFloat = 10  // cards, buttons
    static let xl:    CGFloat = 14
    static let huge:  CGFloat = 44  // phone bezel (mock only)
}

enum CXLine {
    static let hair:     CGFloat = 1
    static let rule:     CGFloat = 1
    static let emphasis: CGFloat = 1.5
}

// MARK: - Motion -----------------------------------------------------------

enum CXMotion {
    static let microTap:     Animation = .easeOut(duration: 0.12)
    static let snap:         Animation = .interactiveSpring(response: 0.28, dampingFraction: 0.86)
    static let stateChange:  Animation = .easeInOut(duration: 0.22)
    static let splashDrawIn: Animation = .timingCurve(0.4, 0, 0.2, 1, duration: 0.5)
    static let splashEcgIn:  Animation = .timingCurve(0.4, 0, 0.2, 1, duration: 0.55).delay(0.4)
}

// MARK: - Theme environment ------------------------------------------------

/// Runtime-swappable theme: accent palette + dark mode + density multiplier.
/// Reachable via `@Environment(\.theme)`; views automatically re-render when
/// `accent`/`isDark`/`density` change thanks to `@Observable`.
@Observable
final class Theme {
    var accent: ClavixAccent = .inkBlue
    var isDark: Bool = true
    var density: Double = 1.0   // 0.9 … 1.1

    // Resolved colors — prefer these in views over raw `Color.cx*`.
    var ink: Color    { isDark ? ClavixDark.ink   : .cxInk }
    var ink2: Color   { isDark ? ClavixDark.ink2  : .cxInk2 }
    var ink3: Color   { isDark ? ClavixDark.ink3  : .cxInk3 }
    var ink4: Color   { isDark ? ClavixDark.ink4  : .cxInk4 }
    var page: Color   { isDark ? ClavixDark.page  : .cxPage }
    var paper: Color  { isDark ? ClavixDark.paper : .cxPaper }
    var paper2: Color { isDark ? ClavixDark.paper2 : .cxPaper2 }
    var rule: Color   { isDark ? ClavixDark.rule  : .cxRule }
    var rule2: Color  { isDark ? ClavixDark.rule2 : .cxRule2 }
    var accentColor:  Color { isDark ? ClavixDark.ink : accent.accent }
    var accentSoft:   Color { isDark ? ClavixDark.accentSoft : accent.accentSoft }
    var accentInk:    Color { isDark ? ClavixDark.ink : accent.accentInk }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = Theme()
}
extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
