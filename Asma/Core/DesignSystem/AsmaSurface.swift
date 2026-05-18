import SwiftUI

struct AsmaCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 32
    var fill: Color = AsmaColor.bgSand
    var stroke: Color = .clear
    var glow: Color = .clear

    func body(content: Content) -> some View {
        content
            .padding(24)
            .background(
                ZStack {
                    if glow != .clear {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(glow)
                            .blur(radius: 20)
                            .opacity(0.4)
                            .offset(y: 8)
                    }
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fill)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
    }
}

/// Glass / Liquid-Glass surface. Uses `.ultraThinMaterial` plus a soft top
/// highlight gradient and a subtle hairline border. Designed for the dark
/// dark MVP — looks like Liquid Glass on iOS 26, sensible blur on iOS 17/18.
struct GlassCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 28
    var strokeOpacity: Double = 0.10
    var topHighlightOpacity: Double = 0.06

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(topHighlightOpacity),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(strokeOpacity),
                                Color.white.opacity(strokeOpacity * 0.25)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    func asmaCard(
        cornerRadius: CGFloat = 32,
        fill: Color = AsmaColor.bgSand,
        stroke: Color = .clear,
        glow: Color = .clear
    ) -> some View {
        modifier(AsmaCardStyle(cornerRadius: cornerRadius, fill: fill, stroke: stroke, glow: glow))
    }

    func glassCard(
        cornerRadius: CGFloat = 28,
        strokeOpacity: Double = 0.10,
        topHighlightOpacity: Double = 0.06
    ) -> some View {
        modifier(GlassCardStyle(
            cornerRadius: cornerRadius,
            strokeOpacity: strokeOpacity,
            topHighlightOpacity: topHighlightOpacity
        ))
    }

    /// Legacy alias retained for any older call-sites.
    func asmaGlass(cornerRadius: CGFloat = 32) -> some View {
        modifier(GlassCardStyle(cornerRadius: cornerRadius))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(AsmaColor.brandGold)
                        .blur(radius: 14)
                        .opacity(configuration.isPressed ? 0.25 : 0.5)
                        .offset(y: 6)

                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(AsmaColor.brandGold)
                }
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AsmaColor.brandGold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(AsmaColor.brandGold.opacity(0.35), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: configuration.isPressed)
    }
}
