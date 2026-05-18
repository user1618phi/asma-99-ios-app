import SwiftUI
import DotLottie

// MARK: - RewardKind

/// Five flavours of the post-action reward screen. The visual layout is
/// shared (close button, eyebrow, heading, coin, +HP, stats, CTA); only
/// the copy, accuracy stats, and whether the info sheet is available
/// differ between them.
enum RewardKind {
    /// Daily flashcard goal hit. No accuracy data (flashcards aren't tests).
    case flashcard
    /// Test session ended with first-cycle accuracy ≥ 60%.
    case testPassed
    /// Test session ended with first-cycle accuracy < 60%.
    case testLow
    /// Pronunciation score ≥ 0.7.
    case practicePassed
    /// Pronunciation score < 0.7.
    case practiceLow

    var isPractice: Bool {
        self == .practicePassed || self == .practiceLow
    }

    var isLowScore: Bool {
        self == .testLow || self == .practiceLow
    }

    /// Info sheet is only meaningful for test/flashcard rewards — they have
    /// real reasoning to explain. Practice is "you said it well/not yet"
    /// and the score table speaks for itself.
    var hasInfoSheet: Bool {
        !isPractice
    }

    var eyebrowKey: String {
        switch self {
        case .flashcard:       return "reward.eyebrow.session"
        case .testPassed, .testLow: return "reward.eyebrow.test"
        case .practicePassed, .practiceLow: return "reward.eyebrow.practice"
        }
    }

    var headingKey: String {
        switch self {
        case .flashcard, .testPassed, .practicePassed: return "reward.heading.mashallah"
        case .testLow:        return "reward.heading.alhamdulillah"
        case .practiceLow:    return "reward.heading.gettingThere"
        }
    }

    var subtitleKey: String {
        switch self {
        case .flashcard:      return "reward.subtitle.flashcard"
        case .testPassed:     return "reward.subtitle.testPassed"
        case .testLow:        return "reward.subtitle.testLow"
        case .practicePassed: return "reward.subtitle.practicePassed"
        case .practiceLow:    return "reward.subtitle.practiceLow"
        }
    }

    var infoTitleKey: String { "reward.info.title" }
}

// MARK: - RewardStat

/// One column in the stats row at the bottom of the reward screen.
/// `highlight` paints the value gold + bigger; reserved for the headline
/// stat (e.g. "Accuracy 90%" on the test reward).
struct RewardStat: Identifiable {
    let id = UUID()
    let labelKey: String
    let value: String
    let highlight: Bool

    init(labelKey: String, value: String, highlight: Bool = false) {
        self.labelKey = labelKey
        self.value = value
        self.highlight = highlight
    }
}

// MARK: - LottieCoinView

/// Wraps the `coin.lottie` animation. When `grayscale` is true (low
/// score paths) we desaturate it client-side — the asset itself is gold;
/// dropping saturation turns it into silver, matching the design's
/// "muted reward" feel without needing a second asset.
struct LottieCoinView: View {
    let grayscale: Bool

    @StateObject private var animation: DotLottieAnimation

    init(grayscale: Bool = false) {
        self.grayscale = grayscale
        self._animation = StateObject(wrappedValue: DotLottieAnimation(
            fileName: "coin",
            config: AnimationConfig(autoplay: true, loop: true)
        ))
    }

    var body: some View {
        DotLottieView(dotLottie: animation)
            .saturation(grayscale ? 0 : 1)
            .brightness(grayscale ? 0.08 : 0)
    }
}

// MARK: - RewardView

/// Full-screen reward presented after a flashcard session, a test, or a
/// pronunciation recording. Renders the same editorial layout as the
/// rest of the app (matches Tests/Home design language) and stays calm
/// — no confetti, no exclamation marks. The Lottie coin + the gold
/// number are the celebration.
struct RewardView: View {
    let kind: RewardKind
    let hp: Int
    let stats: [RewardStat]
    let onDismiss: () -> Void

    @State private var showInfo = false

    var body: some View {
        ZStack {
            EditorialPalette.bg.ignoresSafeArea()

            // Single vertical flow — eyebrow → heading → coin → +HP →
            // subtitle, then flexible Spacer that pushes stats + CTA to
            // the bottom. One stack means content never overlaps when
            // the heading wraps to two lines (Kazakh / long translations).
            VStack(spacing: 0) {
                Spacer().frame(height: 60)

                LocText(kind.eyebrowKey)
                    .font(EditorialFont.sans(10.5, weight: .medium))
                    .tracking(2.4)
                    .textCase(.uppercase)
                    .foregroundStyle(EditorialPalette.goldSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer().frame(height: 24)

                LocText(kind.headingKey)
                    .font(EditorialFont.display(56, weight: .heavy))
                    .tracking(-2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .foregroundStyle(EditorialPalette.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)

                Spacer().frame(height: 16)

                coin

                Spacer().frame(height: 8)

                hpBlock
                    .padding(.horizontal, 24)

                Spacer(minLength: 24)

                statsRow
                    .padding(.horizontal, 30)

                Spacer().frame(height: 28)

                doneButton
                    .padding(.horizontal, 18)
                    .opacity(showInfo ? 0 : 1)

                Spacer().frame(height: 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Close button overlay — pinned to top-right, doesn't push
            // the main flow.
            VStack {
                HStack {
                    Spacer()
                    closeButton
                }
                Spacer()
            }
            .padding(.top, 12)
            .padding(.trailing, 22)

            // Info sheet — slides up from the bottom on tap. Test/flashcard
            // only; practice rewards don't surface it.
            if showInfo && kind.hasInfoSheet {
                infoSheetOverlay
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarHidden(true)
        .hideTabBar()
    }

    // MARK: - Close button

    private var closeButton: some View {
        Button {
            Haptics.tap()
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(EditorialPalette.text)
                .frame(width: 38, height: 38)
                .background(Circle().fill(EditorialPalette.glassBg))
                .background(Circle().fill(.ultraThinMaterial).opacity(0.4))
                .overlay(Circle().strokeBorder(EditorialPalette.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Coin

    private var coin: some View {
        ZStack {
            // Soft ground glow under the coin — gold normally, silver-ish
            // when the score was low. Sits just below the coin so it looks
            // grounded, not floating.
            Ellipse()
                .fill(
                    kind.isLowScore
                        ? Color(white: 0.78).opacity(0.30)
                        : EditorialPalette.gold.opacity(0.35)
                )
                .frame(width: 200, height: 24)
                .blur(radius: 12)
                .offset(y: 96)

            LottieCoinView(grayscale: kind.isLowScore)
                .frame(width: 220, height: 220)
        }
        .frame(height: 220)
    }

    // MARK: - HP block

    private var hpBlock: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("+")
                    .font(EditorialFont.display(44, weight: .semibold))
                    .tracking(-1)
                    .foregroundStyle(EditorialPalette.gold)
                Text("\(hp)")
                    .font(EditorialFont.display(84, weight: .heavy))
                    .tracking(-3)
                    .foregroundStyle(EditorialPalette.gold)
                    .monospacedDigit()
                    .shadow(color: EditorialPalette.gold.opacity(0.35), radius: 50)
                LocText("reward.hp")
                    .font(EditorialFont.sans(18, weight: .semibold))
                    .tracking(2.4)
                    .textCase(.uppercase)
                    .foregroundStyle(EditorialPalette.goldSoft)
                    .padding(.leading, 6)
            }

            HStack(spacing: 8) {
                LocText(kind.subtitleKey)
                    .font(EditorialFont.sans(13, weight: .medium))
                    .foregroundStyle(EditorialPalette.textDim)
                    .multilineTextAlignment(.center)

                if kind.hasInfoSheet {
                    infoDot
                }
            }
            .padding(.horizontal, 24)
        }
    }

    /// Tiny "i" indicator next to the subtitle. Discoverable, not loud.
    /// Tap opens the info sheet that explains how the HP was calculated.
    private var infoDot: some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                showInfo = true
            }
        } label: {
            Text("i")
                .font(EditorialFont.display(11, weight: .bold))
                .foregroundStyle(EditorialPalette.textMute)
                .frame(width: 18, height: 18)
                .background(
                    Circle().strokeBorder(EditorialPalette.textFaint, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats row

    private var statsRow: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(EditorialPalette.textFaint)
                .frame(height: 1)
                .padding(.bottom, 22)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                ForEach(stats) { stat in
                    VStack(spacing: 8) {
                        Text(stat.value)
                            .font(EditorialFont.display(stat.highlight ? 34 : 26, weight: .heavy))
                            .tracking(-0.8)
                            .monospacedDigit()
                            .foregroundStyle(stat.highlight ? EditorialPalette.gold : EditorialPalette.text)
                            .shadow(
                                color: stat.highlight ? EditorialPalette.gold.opacity(0.35) : .clear,
                                radius: 24
                            )

                        LocText(stat.labelKey)
                            .font(EditorialFont.sans(10, weight: .semibold))
                            .tracking(1.6)
                            .textCase(.uppercase)
                            .foregroundStyle(stat.highlight ? EditorialPalette.goldSoft : EditorialPalette.textMute)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Done CTA

    private var doneButton: some View {
        Button {
            Haptics.tap()
            onDismiss()
        } label: {
            HStack {
                LocText("reward.cta.done")
                    .font(EditorialFont.display(18, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.black)

                Spacer()

                ZStack {
                    Circle().fill(Color.black)
                        .frame(width: 40, height: 40)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(EditorialPalette.gold)
                }
            }
            .padding(.leading, 30)
            .padding(.trailing, 14)
            .padding(.vertical, 16)
            .background(
                Capsule().fill(EditorialPalette.gold)
            )
            .overlay(
                Capsule().strokeBorder(EditorialPalette.gold, lineWidth: 1)
            )
            .shadow(color: EditorialPalette.gold.opacity(0.35), radius: 40)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Info sheet

    private var infoSheetOverlay: some View {
        ZStack {
            // Dim backdrop — tap to dismiss
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        showInfo = false
                    }
                }

            VStack {
                Spacer()
                RewardInfoSheet(kind: kind, hp: hp) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        showInfo = false
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .zIndex(100)
    }
}

// MARK: - RewardInfoSheet

/// Bottom-sheet card explaining how the HP was calculated. Numbered
/// reasoning lines (max 3) keep it scannable. Lives only for
/// test/flashcard kinds; practice doesn't surface this.
struct RewardInfoSheet: View {
    let kind: RewardKind
    let hp: Int
    let onDismiss: () -> Void

    private var bodyKeys: [String] {
        switch kind {
        case .flashcard:  return ["reward.info.flash.l1", "reward.info.flash.l2", "reward.info.flash.l3"]
        case .testPassed: return ["reward.info.testPassed.l1", "reward.info.testPassed.l2", "reward.info.testPassed.l3"]
        case .testLow:    return ["reward.info.testLow.l1",    "reward.info.testLow.l2",    "reward.info.testLow.l3"]
        default:          return []
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sheet handle
            Capsule()
                .fill(EditorialPalette.textFaint)
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 18)

            // Title row: eyebrow + +HP mono badge
            HStack(alignment: .firstTextBaseline) {
                LocText(kind.infoTitleKey)
                    .font(EditorialFont.sans(10.5, weight: .medium))
                    .tracking(2.4)
                    .textCase(.uppercase)
                    .foregroundStyle(EditorialPalette.goldSoft)

                Spacer()

                Text("+\(hp) HP")
                    .font(EditorialFont.mono(11, weight: .medium))
                    .tracking(1)
                    .monospacedDigit()
                    .foregroundStyle(EditorialPalette.textMute)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 16)

            // Numbered reasoning lines, hairline between
            VStack(spacing: 0) {
                ForEach(Array(bodyKeys.enumerated()), id: \.offset) { (idx, key) in
                    if idx > 0 {
                        Rectangle()
                            .fill(EditorialPalette.textFaint)
                            .frame(height: 1)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        Text(String(format: "%02d", idx + 1))
                            .font(EditorialFont.mono(10, weight: .medium))
                            .tracking(0.8)
                            .monospacedDigit()
                            .foregroundStyle(EditorialPalette.gold)
                            .frame(width: 18, alignment: .leading)
                            .padding(.top, 4)

                        LocText(key)
                            .font(EditorialFont.display(15, weight: .medium))
                            .tracking(-0.1)
                            .lineSpacing(4)
                            .foregroundStyle(EditorialPalette.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 14)
                }
            }
            .padding(.horizontal, 28)

            // Got it pill
            Button {
                Haptics.tap()
                onDismiss()
            } label: {
                LocText("reward.info.gotIt")
                    .font(EditorialFont.display(14, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(EditorialPalette.gold)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(EditorialPalette.glassBg))
                    .background(Capsule().fill(.ultraThinMaterial).opacity(0.4))
                    .overlay(Capsule().strokeBorder(EditorialPalette.glassBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(EditorialPalette.glassBgDeep)
        )
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(EditorialPalette.glassBorder, lineWidth: 1)
        )
    }
}
