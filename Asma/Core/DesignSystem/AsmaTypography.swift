import SwiftUI

enum AsmaFont {
    static func arabic(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // iOS bundles high-quality Arabic faces; system font picks them automatically.
        .system(size: size, weight: weight, design: .serif)
    }

    static func display(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func numeric(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}
