import SwiftUI

// Cream/paper design tokens. These are the production-available versions of
// the private vqa* tokens that live inside the (debug-only) ClavixVisualQA.swift.
// New live-tab views consume `Clavix*` tokens; the debug VisualQA file keeps
// its private mirror so it can be edited without touching production.

// Canonical Clavix Hi-Fi v2 palette, extracted from
// docs/design/clavix-hifi-v2.html (the design source of truth).
// Editorial ink-on-cream, bond-rating fills, mono numerics.
extension Color {
    static func clavixAdaptive(light: String, dark: String) -> Color {
        Color(
            UIColor { traits in
                UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
            }
        )
    }

    // Dark "calm instrument" theme (2026-06-22 redesign).
    // See docs/design/mockups/README.md for the token spec.

    // Ink ramp (light text on dark)
    static let clavixInk    = clavixAdaptive(light: "#1A1814", dark: "#E8E6DF")
    static let clavixInk2   = clavixAdaptive(light: "#3A342B", dark: "#BFC0BC")
    static let clavixInk3   = clavixAdaptive(light: "#777777", dark: "#9A9C98")
    static let clavixInk4   = clavixAdaptive(light: "#999999", dark: "#5C6068")
    static let clavixInk5   = clavixAdaptive(light: "#C8C0B0", dark: "#44464C")

    // Instrument surfaces
    static let clavixCanvas = clavixAdaptive(light: "#F0EADB", dark: "#0E0F12")
    static let clavixPage   = clavixAdaptive(light: "#F0EADB", dark: "#0E0F12")
    static let clavixPaper  = clavixAdaptive(light: "#F3ECE0", dark: "#16181D")
    static let clavixPaper2 = clavixAdaptive(light: "#E8E0CC", dark: "#1E2127")

    // Rules / dividers (hairlines)
    static let clavixRule   = clavixAdaptive(light: "#D6CEBD", dark: "#2A2C31")
    static let clavixRule2  = clavixAdaptive(light: "#E6DFCF", dark: "#202227")

    // Accent: cream (interactive / active states)
    static let clavixAccent     = clavixAdaptive(light: "#1D3A6E", dark: "#E8E6DF")
    static let clavixAccentSoft = clavixAdaptive(light: "#E3E9F3", dark: "#1E2127")
    static let clavixAccentInk  = clavixAdaptive(light: "#11264A", dark: "#E8E6DF")

    // Strong (teal) — risk: low
    static let clavixGood     = clavixAdaptive(light: "#1F5B3A", dark: "#3FB984")
    static let clavixGoodSoft = clavixAdaptive(light: "#DDE9D8", dark: "#10342B")
    static let clavixGoodInk  = clavixAdaptive(light: "#0D3A22", dark: "#3FB984")

    // Watch (amber) — risk: rising
    static let clavixWarn     = clavixAdaptive(light: "#B34A14", dark: "#E0A33E")
    static let clavixWarnSoft = clavixAdaptive(light: "#F4DCC4", dark: "#3A2B12")
    static let clavixWarnInk  = clavixAdaptive(light: "#6E2C09", dark: "#E0A33E")

    // Alarm (coral) — risk: high
    static let clavixBad     = clavixAdaptive(light: "#7A1E2C", dark: "#E2604A")
    static let clavixBadSoft = clavixAdaptive(light: "#F0D8D4", dark: "#3A1A12")
    static let clavixBadInk  = clavixAdaptive(light: "#5C2B2E", dark: "#E2604A")
}

extension ClavisTypography {
    /// JetBrainsMono Regular at the requested size and weight. Used for ledger
    /// rows, numeric values, timestamps, and eyebrow chips.
    static func clavixMono(_ size: CGFloat, weight: Font.Weight) -> Font {
        Font.custom("JetBrainsMono-Regular", size: size).weight(weight)
    }

    /// Compatibility name for legacy call sites. All product copy uses Inter.
    static func clavixSerif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        inter(size, weight: weight == .medium ? .semibold : weight)
    }

    static var clavixCaption: Font { inter(12, weight: .regular) }
}

enum ClavixLayout {
    static let pad: CGFloat = 20
    static let bottomPad: CGFloat = 28
    static let cardRadius: CGFloat = 11
    static let controlRadius: CGFloat = 8
}
