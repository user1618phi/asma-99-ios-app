import SwiftUI

/// Top-right glass circle on Home / Learn / Tests / Profile. Shows the
/// current ambience icon; tap opens a small glass popover with the five
/// sound choices.
struct AmbientSoundButton: View {
    @State private var ambient = AmbientSoundPlayer.shared
    @State private var popoverPresented = false
    @Environment(LocalizationManager.self) private var localization

    var body: some View {
        Button {
            Haptics.tap()
            popoverPresented = true
        } label: {
            Image(systemName: ambient.current.systemImage)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(iconTint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(EditorialPalette.glassBg))
                .background(Circle().fill(.ultraThinMaterial).opacity(0.4))
                .overlay(Circle().strokeBorder(EditorialPalette.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $popoverPresented, arrowEdge: .top) {
            popoverContent
                .presentationCompactAdaptation(.popover)
                .presentationBackground(.ultraThinMaterial)
        }
        // Re-render when language flips — labels need to refresh.
        .id(localization.current)
    }

    private var iconTint: Color {
        switch ambient.current {
        case .silent: return EditorialPalette.textDim
        default:      return EditorialPalette.gold
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(AmbientSound.allCases) { sound in
                row(for: sound)
                if sound != AmbientSound.allCases.last {
                    Divider()
                        .background(EditorialPalette.glassBorderSoft)
                        .padding(.leading, 52)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 220)
    }

    private func row(for sound: AmbientSound) -> some View {
        Button {
            Haptics.tap()
            ambient.setSound(sound)
            popoverPresented = false
        } label: {
            HStack(spacing: 14) {
                Image(systemName: sound.systemImage)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(sound == .silent ? EditorialPalette.textDim : EditorialPalette.gold)
                    .frame(width: 22, alignment: .center)

                Text(verbatim: Bundle.loc(sound.localizationKey))
                    .font(EditorialFont.sans(15, weight: .medium))
                    .foregroundStyle(EditorialPalette.text)

                Spacer(minLength: 12)

                if sound == ambient.current {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EditorialPalette.gold)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
