import SwiftUI

// MARK: - Palette
//
// Exact tokens from the editorial design bundle (`x5fXQb8P9axtn_5Mfw1Rhg`).
// Used across the dark, premium screens (Onboarding, Flashcards, Tests,
// Names list, Profile). Home stays on its existing palette.

enum EditorialPalette {
    /// Pure black canvas.
    static let bg          = Color(red: 0,           green: 0,           blue: 0)
    /// Soft black for layered glass surfaces.
    static let bgSoft      = Color(red: 10  / 255,   green: 9   / 255,   blue: 7   / 255)
    /// Off-white editorial text.
    static let text        = Color(red: 244 / 255,   green: 239 / 255,   blue: 227 / 255)
    static let textDim     = Color(red: 244 / 255,   green: 239 / 255,   blue: 227 / 255).opacity(0.55)
    static let textMute    = Color(red: 244 / 255,   green: 239 / 255,   blue: 227 / 255).opacity(0.32)
    static let textFaint   = Color(red: 244 / 255,   green: 239 / 255,   blue: 227 / 255).opacity(0.16)

    static let gold        = Color(red: 201 / 255,   green: 168 / 255,   blue: 106 / 255)
    static let goldSoft    = Color(red: 201 / 255,   green: 168 / 255,   blue: 106 / 255).opacity(0.72)
    static let goldFaint   = Color(red: 201 / 255,   green: 168 / 255,   blue: 106 / 255).opacity(0.32)

    static let glassBg       = Color.white.opacity(0.035)
    static let glassBgDeep   = Color.white.opacity(0.05)
    static let glassBorder   = Color.white.opacity(0.09)
    static let glassBorderSoft = Color.white.opacity(0.06)

    // Warm coral used to flag pronunciation mistakes in Practice. Tuned to
    // sit next to gold without screaming — soft hue, no saturation spike.
    static let warn      = Color(red: 224 / 255, green: 122 / 255, blue: 102 / 255)
    static let warnSoft  = Color(red: 224 / 255, green: 122 / 255, blue: 102 / 255).opacity(0.55)
}

// MARK: - Typography
//
// Inter Tight for display & UI. System Arabic for actual learning content
// (San Francisco's Arabic is highly legible — preferred over Amiri for the
// names you're memorising). Amiri remains available for Onboarding's
// decorative Arabic header only.

enum EditorialFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Inter Tight", size: size).weight(weight)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Inter Tight", size: size).weight(weight)
    }

    /// System Arabic (San Francisco). Used for all learning content where
    /// readability matters more than ornament.
    static func arabic(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Amiri — only for decorative Arabic (Onboarding header). Falls back
    /// to system serif if Amiri isn't loaded.
    static func amiri(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let bold: Set<Font.Weight> = [.bold, .heavy, .black]
        return bold.contains(weight)
            ? .custom("Amiri", size: size).weight(.bold)
            : .custom("Amiri", size: size)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
    }
}

// MARK: - Glass surface modifiers

extension View {
    /// Standard glass tile — used for cards and chips.
    func editorialGlass(cornerRadius: CGFloat = 22) -> some View {
        modifier(EditorialGlass(cornerRadius: cornerRadius, deep: false))
    }

    /// Deep glass — used for hero modules with stronger blur.
    func editorialGlassDeep(cornerRadius: CGFloat = 28) -> some View {
        modifier(EditorialGlass(cornerRadius: cornerRadius, deep: true))
    }
}

private struct EditorialGlass: ViewModifier {
    let cornerRadius: CGFloat
    let deep: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(deep ? EditorialPalette.glassBgDeep : EditorialPalette.glassBg)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(deep ? 0.55 : 0.4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(EditorialPalette.glassBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.5), radius: deep ? 30 : 20, x: 0, y: deep ? 30 : 20)
    }
}

// MARK: - Shared captions / dots

struct EditorialEyebrow: View {
    /// Localization key — resolved via `Bundle.loc(_:)` so the eyebrow flips
    /// language immediately when the user changes their selection.
    /// Pass a `%@`/`%lld`-style format key here only if it has no arguments;
    /// for arg-bearing keys, call `Bundle.loc("key", arg)` at the callsite
    /// and pass the result via `EditorialEyebrow(literal:)` (below).
    let key: String
    /// Optional pre-resolved literal — used for runtime strings like
    /// "01 / 99" or names that must not pass through localization.
    let literal: String?
    var color: Color = EditorialPalette.goldSoft
    var tracking: CGFloat = 2.4
    var size: CGFloat = 10.5
    var weight: Font.Weight = .medium

    init(
        text key: String,
        color: Color = EditorialPalette.goldSoft,
        tracking: CGFloat = 2.4,
        size: CGFloat = 10.5,
        weight: Font.Weight = .medium
    ) {
        self.key = key
        self.literal = nil
        self.color = color
        self.tracking = tracking
        self.size = size
        self.weight = weight
    }

    init(
        literal: String,
        color: Color = EditorialPalette.goldSoft,
        tracking: CGFloat = 2.4,
        size: CGFloat = 10.5,
        weight: Font.Weight = .medium
    ) {
        self.key = ""
        self.literal = literal
        self.color = color
        self.tracking = tracking
        self.size = size
        self.weight = weight
    }

    var body: some View {
        Text(verbatim: literal ?? Bundle.loc(key))
            .font(EditorialFont.sans(size, weight: weight))
            .tracking(tracking)
            .foregroundStyle(color)
            .textCase(.uppercase)
    }
}

struct EditorialPageDots: View {
    let total: Int
    let current: Int

    var body: some View {
        // For 7+ pages, classic dot rows become unreadable — the design
        // switches to a thin gold rail flanked by a monospace fraction
        // (e.g. `03 ──── 08`). Threshold matches the React prototype.
        if total > 6 {
            HStack(spacing: 14) {
                Text(String(format: "%02d", current + 1))
                    .font(EditorialFont.mono(10.5))
                    .tracking(1.2)
                    .foregroundStyle(EditorialPalette.gold)
                    .frame(minWidth: 32, alignment: .leading)
                    .monospacedDigit()

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(EditorialPalette.textFaint)
                            .frame(height: 1)
                        Rectangle()
                            .fill(EditorialPalette.gold)
                            .frame(
                                width: geo.size.width * CGFloat(current + 1) / CGFloat(max(total, 1)),
                                height: 1
                            )
                            .shadow(color: EditorialPalette.gold.opacity(0.55), radius: 4)
                            .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.35), value: current)
                    }
                }
                .frame(height: 1)
                .frame(maxWidth: 200)

                Text(String(format: "%02d", total))
                    .font(EditorialFont.mono(10.5))
                    .tracking(1.2)
                    .foregroundStyle(EditorialPalette.textMute)
                    .frame(minWidth: 32, alignment: .trailing)
                    .monospacedDigit()
            }
            .padding(.horizontal, 30)
        } else {
            HStack(spacing: 8) {
                ForEach(0..<total, id: \.self) { i in
                    Capsule()
                        .fill(i == current ? EditorialPalette.gold : EditorialPalette.textFaint)
                        .frame(width: i == current ? 22 : 6, height: 6)
                        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: current)
                }
            }
        }
    }
}
