import SwiftUI

/// Bottom sheet for picking the daily flashcard goal. Same visual rhythm
/// as `LanguagePicker` — eyebrow, description, then a list of options
/// with a gold checkmark on the selected row. Writes through to
/// `AppSettingsKey.flashcardCount` so the rest of the app (Home CTA,
/// Learn session cap, evening nudge) picks the change up immediately.
struct CardsPerDayPicker: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettingsKey.flashcardCount) private var flashcardCount = AppSettingsKey.flashcardDefault

    /// Fixed pace ladder used in onboarding. Stepping outside these four
    /// values (via an older Settings stepper, say) is preserved — the
    /// checkmark just hides until the user lands back on a known value.
    private struct PaceOption: Identifiable {
        let value: Int
        let labelKey: String
        var id: Int { value }
    }

    private let options: [PaceOption] = [
        .init(value: 1, labelKey: "onboarding.pace.chip.easy"),
        .init(value: 3, labelKey: "onboarding.pace.chip.gentle"),
        .init(value: 5, labelKey: "onboarding.pace.chip.steady"),
        .init(value: 10, labelKey: "onboarding.pace.chip.focused")
    ]

    var body: some View {
        ZStack {
            EditorialPalette.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 24)

                EditorialEyebrow(text: "cards_per_day.eyebrow")
                    .padding(.horizontal, 30)

                Spacer().frame(height: 16)

                LocText("cards_per_day.description")
                    .font(EditorialFont.sans(14, weight: .medium))
                    .lineSpacing(3)
                    .foregroundStyle(EditorialPalette.textDim)
                    .padding(.horizontal, 30)

                Spacer().frame(height: 28)

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(EditorialPalette.textFaint)
                        .frame(height: 1)
                    ForEach(Array(options.enumerated()), id: \.element.id) { idx, option in
                        Button {
                            flashcardCount = option.value
                            Haptics.selection()
                            dismiss()
                        } label: {
                            HStack {
                                HStack(spacing: 10) {
                                    Text("\(option.value)")
                                        .font(EditorialFont.display(17, weight: .semibold))
                                        .tracking(-0.2)
                                        .monospacedDigit()
                                        .foregroundStyle(EditorialPalette.text)
                                    Text(verbatim: "·")
                                        .font(EditorialFont.display(17, weight: .semibold))
                                        .foregroundStyle(EditorialPalette.textMute)
                                    Text(verbatim: Bundle.loc(option.labelKey))
                                        .font(EditorialFont.display(17, weight: .semibold))
                                        .tracking(-0.2)
                                        .foregroundStyle(EditorialPalette.text)
                                }
                                Spacer()
                                if flashcardCount == option.value {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(EditorialPalette.gold)
                                }
                            }
                            .padding(.horizontal, 30)
                            .padding(.vertical, 18)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if idx < options.count - 1 {
                            Rectangle()
                                .fill(EditorialPalette.textFaint)
                                .frame(height: 1)
                                .padding(.leading, 30)
                        }
                    }
                    Rectangle()
                        .fill(EditorialPalette.textFaint)
                        .frame(height: 1)
                }

                Spacer(minLength: 0)
            }
        }
        .preferredColorScheme(.dark)
    }
}
