import SwiftUI

// MARK: - Press tracking
//
// Bubbles the row's pressed state up to the enclosing `GlassSection`
// so the whole card can scale a touch in sympathy with the row —
// one gesture, two layers of feedback.

private struct GlassSectionPressedKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

// MARK: - Section container

struct GlassSection<Content: View>: View {
    let titleKey: String
    @ViewBuilder var content: () -> Content
    @State private var isAnyRowPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialEyebrow(text: titleKey, tracking: 2.4)
                .padding(.horizontal, 28)
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                content()
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .editorialGlass(cornerRadius: 20)
            .scaleEffect(isAnyRowPressed ? 0.985 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isAnyRowPressed)
            .onPreferenceChange(GlassSectionPressedKey.self) { isAnyRowPressed = $0 }
            .padding(.horizontal, 18)
        }
    }
}

/// Hairline divider used between rows in a `GlassSection`. Inset on
/// the left so it aligns with the label, not the icon — same look as
/// Apple's own Settings.app.
struct GlassRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(EditorialPalette.glassBorder)
            .frame(height: 1)
            .padding(.leading, 56)
    }
}

// MARK: - Row content (shared by Button + Toggle variants)

private struct GlassRowBody<Trailing: View>: View {
    let symbol: String
    let labelKey: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(EditorialPalette.gold)
                .frame(width: 24, alignment: .center)

            Text(verbatim: Bundle.loc(labelKey))
                .font(EditorialFont.display(17, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(EditorialPalette.text)

            Spacer(minLength: 8)

            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Tappable row

struct GlassRow: View {
    let symbol: String
    let labelKey: String
    var value: String = ""
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            GlassRowBody(symbol: symbol, labelKey: labelKey) {
                if !value.isEmpty {
                    Text(value)
                        .font(EditorialFont.sans(13, weight: .medium))
                        .foregroundStyle(EditorialPalette.gold)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EditorialPalette.textMute)
            }
        }
        .buttonStyle(GlassRowButtonStyle())
    }
}

// MARK: - Toggle row
//
// The whole row is tappable — pressing anywhere outside the toggle
// flips it (same bounce as the button rows). The toggle itself stays
// interactive for swipe gestures, just doesn't intercept taps so the
// row's button gets the press and the parent section scales with it.

struct GlassToggleRow: View {
    let symbol: String
    let labelKey: String
    @Binding var isOn: Bool
    /// Custom setter so the parent can intercept the change (e.g. to
    /// request iOS notification permission before flipping the bit).
    /// When nil, the binding is set directly.
    var onChange: ((Bool) -> Void)? = nil

    var body: some View {
        Button {
            flip()
        } label: {
            GlassRowBody(symbol: symbol, labelKey: labelKey) {
                Toggle("", isOn: Binding(
                    get: { isOn },
                    set: { newValue in
                        if let onChange { onChange(newValue) } else { isOn = newValue }
                    }
                ))
                .labelsHidden()
                .tint(EditorialPalette.gold)
            }
        }
        .buttonStyle(GlassRowButtonStyle())
    }

    private func flip() {
        let newValue = !isOn
        if let onChange { onChange(newValue) } else { isOn = newValue }
    }
}

// MARK: - Button style (bounce + bubble pressed state)

struct GlassRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: configuration.isPressed)
            .preference(key: GlassSectionPressedKey.self, value: configuration.isPressed)
    }
}
