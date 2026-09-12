import SwiftUI

// ── Palette (ported verbatim from the Python `C` dict) ───────────────────────
extension Color {
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red:   Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >>  8) & 0xFF) / 255,
                  blue:  Double( v        & 0xFF) / 255,
                  opacity: 1)
    }
}

enum P {
    static let bg      = Color(hex: "#EDF5FB")
    static let card    = Color(hex: "#FFFFFF")
    static let card2   = Color(hex: "#F4F9FD")
    static let primary = Color(hex: "#5B9EC9")
    static let priLt   = Color(hex: "#BDD8EE")
    static let priDk   = Color(hex: "#3F7EA8")
    static let mint    = Color(hex: "#6DC8A0")
    static let mintLt  = Color(hex: "#BDE8D3")
    static let peach   = Color(hex: "#F4A07A")
    static let teal    = Color(hex: "#5BBCB0")
    static let tealLt  = Color(hex: "#B8ECE4")
    static let sip     = Color(hex: "#5A8FC8")
    static let sipLt   = Color(hex: "#C8DCFF")
    static let ringBg  = Color(hex: "#D5E8F5")
    static let textH   = Color(hex: "#2A4A6B")
    static let textB   = Color(hex: "#4A6A8B")
    static let textS   = Color(hex: "#8AABC9")
    static let border  = Color(hex: "#D5E8F5")

    // Calendar heat colours (no-data → goal met)
    static let calNone = Color(hex: "#EBEBEB")
    static let calLow  = Color(hex: "#F4CDBA")
    static let cal25   = Color(hex: "#F4A07A")
    static let cal50   = Color(hex: "#F4D875")
    static let cal75   = Color(hex: "#5B9EC9")
    static let cal100  = Color(hex: "#6DC8A0")
}

func pctColor(_ pct: Int?) -> Color {
    guard let p = pct else { return P.calNone }
    if p >= 100 { return P.cal100 }
    if p >= 75  { return P.cal75 }
    if p >= 50  { return P.cal50 }
    if p >= 25  { return P.cal25 }
    return P.calLow
}

func pctTextColor(_ pct: Int?) -> Color {
    if let p = pct, p >= 75 { return .white }
    return P.textH
}

// ── Typography — Avenir Next, matching the original FONT constant ────────────
enum F {
    static let name = "Avenir Next"
    static func r(_ size: CGFloat) -> Font { .custom(name, fixedSize: size) }
    static func b(_ size: CGFloat) -> Font { .custom(name, fixedSize: size).weight(.bold) }
    static func i(_ size: CGFloat) -> Font { .custom(name, fixedSize: size).italic() }
}

// ── Reusable chrome ──────────────────────────────────────────────────────────
/// White rounded card with a 1px border — the `highlightbackground` frames
/// used throughout the Tk layout.
struct CardBox<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(P.card)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(P.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// A tappable pill with hover feedback — the Tk `_mk_btn` / quick-add pills.
struct PillButton: View {
    let title: String
    let bg: Color
    let fg: Color
    var font: Font = F.b(11)
    var vPad: CGFloat = 9
    var hPad: CGFloat = 8
    var fill: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Text(title)
            .font(font)
            .foregroundStyle(fg)
            .padding(.vertical, vPad)
            .padding(.horizontal, hPad)
            .frame(maxWidth: fill ? .infinity : nil)
            .background(hovering ? bg.opacity(0.78) : bg)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onHover { hovering = $0 }
    }
}

/// Small text-only control (the ✎ / × / ✕ glyph buttons).
struct GlyphButton: View {
    let glyph: String
    var size: CGFloat = 13
    var base: Color = P.textS
    var hover: Color = P.primary
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Text(glyph)
            .font(F.r(size))
            .foregroundStyle(hovering ? hover : base)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onHover { hovering = $0 }
    }
}

/// Text field styled like the flat Tk entries.
struct FlatField: View {
    let placeholder: String
    @Binding var text: String
    var width: CGFloat? = nil
    var font: Font = F.r(13)
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(P.textB)
            .padding(.vertical, 8)
            .padding(.horizontal, 9)
            .frame(width: width)
            .background(P.card2)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onSubmit(onSubmit)
    }
}
