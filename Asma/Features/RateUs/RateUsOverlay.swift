import SwiftUI
import StoreKit

/// Centered Rate-us modal — matches the design's "A small request /
/// Worth a moment?" overlay. Stars are interactive (the user can tap one
/// and the prefix lights up) for delight only — the actual rating is
/// submitted through Apple's system prompt that `triggerSystemPrompt`
/// fires when the user taps the gold "Rate Asma" pill.
struct RateUsOverlay: View {
    /// Called by both CTAs and the × so the host can dismiss the overlay
    /// regardless of which path the user took.
    let onClose: () -> Void

    @Environment(\.requestReview) private var requestReview

    @State private var rating: Int = 0

    var body: some View {
        ZStack {
            // Dim backdrop. Tappable but does NOT close — overlay can only
            // be dismissed via the explicit ×, Later, or Rate-Asma CTA so
            // the user has to make an actual choice.
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .background(.ultraThinMaterial.opacity(0.6))

            card
                .padding(.horizontal, 22)
        }
        .transition(.opacity)
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 0) {
            // Crescent decoration — matches the visual lexicon used
            // throughout the editorial system (gold line-art, no fills).
            Image(systemName: "moon")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(EditorialPalette.gold)
                .shadow(color: EditorialPalette.gold.opacity(0.4), radius: 6)
                .padding(.top, 4)

            EditorialEyebrow(
                text: "rateUs.eyebrow",
                color: EditorialPalette.goldSoft,
                tracking: 2.8,
                size: 9.5
            )
            .padding(.top, 14)

            // Headline — "Worth a / moment?" with gold on the bottom line.
            VStack(spacing: -2) {
                LocText("rateUs.headline.line1")
                    .foregroundStyle(EditorialPalette.text)
                LocText("rateUs.headline.gold")
                    .foregroundStyle(EditorialPalette.gold)
            }
            .font(.custom("Inter Tight", size: 32).weight(.heavy))
            .tracking(-1.2)
            .multilineTextAlignment(.center)
            .padding(.top, 14)

            LocText("rateUs.body")
                .font(EditorialFont.sans(13, weight: .medium))
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(EditorialPalette.textDim)
                .padding(.top, 14)
                .padding(.horizontal, 4)

            starsRow
                .padding(.top, 22)

            // Thin gold hairline divider
            Rectangle()
                .fill(EditorialPalette.goldFaint)
                .frame(width: 28, height: 1)
                .padding(.top, 22)

            // Primary CTA — gold pill triggers Apple's native prompt
            Button(action: tapRate) {
                LocText("rateUs.primary")
                    .font(.custom("Inter Tight", size: 15).weight(.bold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(EditorialPalette.gold))
                    .shadow(color: EditorialPalette.gold.opacity(0.32), radius: 16)
            }
            .buttonStyle(.plain)
            .padding(.top, 22)

            // Secondary — ghost link, marks Later (14-day postpone)
            Button(action: tapLater) {
                LocText("rateUs.secondary")
                    .font(EditorialFont.sans(11, weight: .medium))
                    .tracking(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(EditorialPalette.textMute)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(.top, 32)
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(EditorialPalette.glassBgDeep)
        )
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.55)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(EditorialPalette.glassBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.65), radius: 40, y: 30)
        .shadow(color: EditorialPalette.gold.opacity(0.08), radius: 80)
        .overlay(alignment: .topTrailing) {
            // × — same dismissal as "Later" so we never trap the user.
            Button(action: tapLater) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EditorialPalette.textMute)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
    }

    // MARK: - Stars

    private var starsRow: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        rating = i
                    }
                } label: {
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(i <= rating ? EditorialPalette.gold : EditorialPalette.goldFaint)
                        .shadow(
                            color: i <= rating ? EditorialPalette.gold.opacity(0.5) : .clear,
                            radius: 6
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func tapRate() {
        Haptics.tap()
        RateUsService.triggerSystemPrompt(requestReview: requestReview)
        // Mark overlay as shown too so the banner state machine treats
        // this as a complete journey.
        RateUsService.dismissOverlayAsLater()
        onClose()
    }

    private func tapLater() {
        Haptics.tap()
        RateUsService.dismissOverlayAsLater()
        onClose()
    }
}

#Preview {
    ZStack {
        EditorialPalette.bg.ignoresSafeArea()
        RateUsOverlay(onClose: {})
    }
}
