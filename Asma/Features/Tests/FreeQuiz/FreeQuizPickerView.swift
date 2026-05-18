import SwiftUI

/// Direction picker shown when the user taps "Practice Quiz" from the
/// Tests cooldown banner. Two modes only — name → meaning and meaning
/// → name — so the practice run is focused, not noisy.
///
/// Visual rhythm matches the rest of the editorial system (eyebrow →
/// title → subtitle → cards → footer hairline) but the two mode cards
/// here are richer than the regular `TestsLandingView` mode rows: each
/// shows a live sample of what its prompt will look like (a gold Arabic
/// name for nameToMeaning, a gold meaning string for meaningToName) so
/// the user understands the mode before tapping.
struct FreeQuizPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalizationManager.self) private var localization

    /// Caller-supplied navigator. We don't own the NavigationStack — the
    /// parent (TestsLandingView) does — so we hand it back the target
    /// route via this closure.
    let onPick: (TestMode) -> Void

    private let modes: [TestMode] = [.nameToMeaning, .meaningToName]

    var body: some View {
        ZStack {
            EditorialPalette.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.horizontal, 22)
                    .padding(.top, 8)

                Spacer().frame(height: 28)

                EditorialEyebrow(text: "tests.freeQuiz.eyebrow")
                    .padding(.horizontal, 30)

                Spacer().frame(height: 18)

                // Editorial title — same scale as the main "Tests" hero
                // so the user feels they've stepped into a focused
                // sub-screen, not a minor sheet.
                LocText("tests.freeQuiz.picker.title")
                    .font(EditorialFont.display(56, weight: .heavy))
                    .tracking(-2.4)
                    .lineSpacing(-6)
                    .foregroundStyle(EditorialPalette.text)
                    .padding(.horizontal, 30)

                Spacer().frame(height: 12)

                LocText("tests.freeQuiz.picker.subtitle")
                    .font(EditorialFont.sans(14, weight: .medium))
                    .tracking(-0.1)
                    .foregroundStyle(EditorialPalette.textDim)
                    .padding(.horizontal, 30)

                Spacer().frame(height: 34)

                VStack(spacing: 12) {
                    ForEach(modes) { mode in
                        modeCard(mode: mode)
                    }
                }
                .padding(.horizontal, 18)

                Spacer(minLength: 0)

                footerNote
                    .padding(.horizontal, 30)
                    .padding(.bottom, 32)
            }
        }
        .navigationBarHidden(true)
        .hideTabBar()
        .preferredColorScheme(.dark)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            CircleGlassButton(systemName: "xmark", iconSize: 14) { dismiss() }
            Spacer()
        }
    }

    // MARK: - Mode card

    /// Premium mode card — the two cards stack vertically. Each one shows
    /// a live preview of the prompt the user will see in that mode (Arabic
    /// for nameToMeaning, transliteration text for meaningToName), then a
    /// gold hairline, then the localized title + subtitle from the
    /// existing `tests.mode.*` keys.
    @ViewBuilder
    private func modeCard(mode: TestMode) -> some View {
        Button {
            Haptics.tap()
            onPick(mode)
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                samplePreview(for: mode)

                Rectangle()
                    .fill(EditorialPalette.goldFaint)
                    .frame(width: 28, height: 1)

                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: Bundle.loc(mode.titleKey))
                        .font(EditorialFont.display(22, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(EditorialPalette.text)
                    Text(verbatim: Bundle.loc(mode.subtitleKey))
                        .font(EditorialFont.sans(13, weight: .medium))
                        .foregroundStyle(EditorialPalette.textDim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(EditorialPalette.textMute)
                    .padding(22)
            }
            .editorialGlassDeep(cornerRadius: 26)
        }
        .buttonStyle(.plain)
    }

    /// Renders the "what you'll be looking at" preview at the top of each
    /// card. Uses a real sample name (الرَّحِيم / The Merciful) so the
    /// preview matches the visual language of the test screen itself.
    @ViewBuilder
    private func samplePreview(for mode: TestMode) -> some View {
        HStack(spacing: 10) {
            switch mode {
            case .nameToMeaning:
                Text("الرَّحِيم")
                    .font(EditorialFont.arabic(22, weight: .regular))
                    .foregroundStyle(EditorialPalette.gold)
                    .environment(\.layoutDirection, .rightToLeft)
                    .shadow(color: EditorialPalette.gold.opacity(0.25), radius: 12)
            case .meaningToName:
                LocText("onboarding.cards.meaning")
                    .font(EditorialFont.display(17, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(EditorialPalette.gold)
                    .shadow(color: EditorialPalette.gold.opacity(0.2), radius: 10)
            default:
                EmptyView()
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(EditorialPalette.goldSoft)

            // Three dim pills representing the "pick one of four" options
            // the user will see on the next screen.
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(EditorialPalette.textFaint)
                        .frame(width: 14, height: 4)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle()
                .fill(EditorialPalette.goldFaint)
                .frame(width: 32, height: 1)
            LocText("tests.freeQuiz.picker.note")
                .font(EditorialFont.sans(12, weight: .medium))
                .lineSpacing(3)
                .foregroundStyle(EditorialPalette.textMute)
        }
    }
}
