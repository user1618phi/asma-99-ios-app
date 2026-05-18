import SwiftUI
import SwiftData
import UserNotifications
import DotLottie

/// Onboarding — 8-screen editorial flow from the design bundle
/// (`U9_TWr-r8wPPugJnTxprFg`).
///
/// Order: 01 Welcome → 02 Method → 03 Cards & Tests → 04 Memory →
/// 05 HP → 06 Notifications permission → 07 Pace → 08 Your name.
///
/// All text routes through `Bundle.loc(...)` so the same flow renders
/// correctly in English, Russian and Kazakh — the keys exist in every
/// `Localizable.strings` we ship.
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(LocalizationManager.self) private var localization
    @Environment(\.openURL) private var openURL

    @AppStorage("asma.userName") private var userName = ""
    @AppStorage(AppSettingsKey.flashcardCount) private var flashcardCount = AppSettingsKey.flashcardDefault
    @AppStorage(AppSettingsKey.notificationsEnabled) private var notificationsEnabled = false

    @State private var page = 0
    @State private var paceChoice: Int = 3
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    /// Latches once the user taps Allow notifications OR Not now on the
    /// Notify slide (page 5). Until then, `scrollDisabled` below kills
    /// the TabView swipe gesture entirely on that page — the only way
    /// off is the two CTAs.
    @State private var notifyAnswered = false

    private let totalPages = 8

    var body: some View {
        ZStack(alignment: .bottom) {
            ObPalette.bg.ignoresSafeArea()

            TabView(selection: $page) {
                Onb1Welcome(onSkip: skipToName)
                    .tag(0)
                Onb2Method(onSkip: skipToName)
                    .tag(1)
                Onb3Cards(onSkip: skipToName)
                    .tag(2)
                Onb4Memory(onSkip: skipToName)
                    .tag(3)
                Onb5HP(onSkip: skipToName)
                    .tag(4)
                Onb6Notify(
                    onSkip: skipToName,
                    onAllow: handleAllowNotifications,
                    onSecondary: handleNotNow
                )
                .tag(5)
                Onb7Pace(paceChoice: $paceChoice)
                    .tag(6)
                Onb8Name(name: $nameDraft, focus: $nameFocused, onBegin: finish)
                    .tag(7)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Hard-disable the page swipe on the Notify slide (page 5)
            // until the user actually answers Allow / Not now. The two
            // CTAs are still tappable because `scrollDisabled` only
            // kills the scroll gesture, not hit-testing.
            .scrollDisabled(page == 5 && !notifyAnswered)
            .ignoresSafeArea()

            // PageDots + per-screen footer overlay.
            // Bottom padding kept tight (28pt above the safe-area inset) so
            // the indicator sits low on the phone — leaves the maximum amount
            // of vertical breathing room above it for the headline + body.
            //
            // `ignoresSafeArea(.keyboard)` is essential: without it, when the
            // user taps the name field on screen 08, the keyboard pushes the
            // overlay up and the "08 ─── 08" rail ends up floating in the
            // middle of the screen, on top of the text field.
            footerOverlay
                .padding(.bottom, 28)
        }
        // Pin the whole onboarding shell against the keyboard so the
        // page-dots rail at the bottom doesn't ride up when the Name
        // field on slide 08 puts the system keyboard on screen. The
        // TextField stays focusable — only the *layout* ignores the
        // keyboard inset.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            paceChoice = flashcardCount
        }
        .onChange(of: page) { _, newPage in
            if newPage == 7 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    nameFocused = true
                }
            } else {
                nameFocused = false
            }
        }
        .preferredColorScheme(.dark)
        // Force a re-render when the user picks a different language so the
        // whole onboarding flow flips strings without a relaunch.
        .id(localization.current)
    }

    // MARK: - Footer (PageDots + per-page hint)

    @ViewBuilder private var footerOverlay: some View {
        VStack(spacing: 18) {
            EditorialPageDots(total: totalPages, current: page)

            // Bottom hint depends on which page is showing.
            switch page {
            case 0, 1, 2, 3, 4:
                LocText("onboarding.swipeContinue")
                    .font(ObFont.sans(10, weight: .medium))
                    .tracking(2.8)
                    .textCase(.uppercase)
                    .foregroundStyle(ObPalette.textMute)
            case 6:
                LocText("onboarding.swipeContinue")
                    .font(ObFont.sans(10, weight: .medium))
                    .tracking(2.8)
                    .textCase(.uppercase)
                    .foregroundStyle(ObPalette.textMute)
            default:
                // Notify (5) and Name (7) have their own CTAs above —
                // no swipe hint needed.
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Flow

    private func advance() {
        Haptics.tap()
        withAnimation(.easeOut(duration: 0.3)) {
            page = min(page + 1, totalPages - 1)
        }
    }

    /// "Skip" never finishes onboarding outright — it only jumps the user
    /// to the final Name screen so they still consciously land on
    /// `Begin`. We refuse to skip a mandatory step (name + pace) because
    /// both `home.greeting` and the daily flashcard goal depend on them.
    private func skipToName() {
        Haptics.tap()
        withAnimation(.easeOut(duration: 0.3)) {
            page = totalPages - 1   // page 7 = "Your name"
        }
    }

    private func finish() {
        Haptics.tap()
        userName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        flashcardCount = paceChoice
        try? context.save()
        onFinish()
    }

    // MARK: - Notification permission (screen 06)
    //
    // Three real-world states need handling, not just "ask once":
    //   1. `.notDetermined` — first encounter, show the system prompt.
    //   2. `.authorized`/`.provisional`/`.ephemeral` — user already said
    //      yes (e.g. from a prior install). Just flip the in-app toggle ON
    //      and move on — no need to bother them again.
    //   3. `.denied` — iOS refuses to show the prompt a second time. The
    //      only way to flip it back is the iOS Settings app, so we deep-
    //      link there. The in-app toggle stays OFF until the user
    //      actually enables it in Settings (resync happens on app
    //      foreground via `syncNotificationsWithSystem`).
    //
    // Either way the user advances to the next screen — no dead-end.

    private func handleAllowNotifications() {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()

            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = await NotificationsService.requestAuthorization()
                notificationsEnabled = granted
            case .authorized, .provisional, .ephemeral:
                notificationsEnabled = true
            case .denied:
                notificationsEnabled = false
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            @unknown default:
                notificationsEnabled = false
            }

            notifyAnswered = true
            advance()
        }
    }

    private func handleNotNow() {
        notificationsEnabled = false
        notifyAnswered = true
        advance()
    }

    /// Reconcile `notificationsEnabled` with what iOS actually thinks.
    /// Called from `.onAppear` so the in-app master toggle never lies
    /// after the user revokes permission in iOS Settings.
    private func syncNotificationsWithSystem() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let systemEnabled =
            settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
        await MainActor.run {
            if notificationsEnabled && !systemEnabled {
                notificationsEnabled = false
            }
        }
    }
}

// MARK: - Onboarding-specific aliases

private typealias ObPalette = EditorialPalette
private enum ObFont {
    static func display(_ s: CGFloat, weight: Font.Weight = .regular) -> Font { EditorialFont.display(s, weight: weight) }
    static func sans(_ s: CGFloat, weight: Font.Weight = .regular) -> Font    { EditorialFont.sans(s, weight: weight) }
    static func arabic(_ s: CGFloat, weight: Font.Weight = .regular) -> Font  { EditorialFont.amiri(s, weight: weight) }
    static func mono(_ s: CGFloat, weight: Font.Weight = .medium) -> Font     { EditorialFont.mono(s, weight: weight) }
}

private struct Eyebrow: View {
    let key: String
    var color: Color = ObPalette.goldSoft
    var tracking: CGFloat = 2.4
    var size: CGFloat = 10.5
    var weight: Font.Weight = .medium
    var body: some View {
        EditorialEyebrow(text: key, color: color, tracking: tracking, size: size, weight: weight)
    }
}

private struct SkipLink: View {
    let action: () -> Void
    var body: some View {
        HStack {
            Spacer()
            Button(action: action) {
                EditorialEyebrow(text: "onboarding.skip", color: ObPalette.textMute, tracking: 2.4)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 70)
        .padding(.horizontal, 24)
    }
}

// MARK: - Shared scaffold for screens 03–06
//
// eyebrow (top-left) · illustration · headline · body · optional CTAs.
// Matches the React `OnbScaffold` from the design bundle.

private struct OnbScaffold<Illo: View, CTAs: View>: View {
    let eyebrowKey: String
    let headline: AnyView
    let bodyKey: String
    let illo: Illo?
    let ctas: CTAs?
    let onSkip: () -> Void

    init(
        eyebrowKey: String,
        @ViewBuilder headline: () -> some View,
        bodyKey: String,
        @ViewBuilder illo: () -> Illo,
        @ViewBuilder ctas: () -> CTAs,
        onSkip: @escaping () -> Void
    ) {
        self.eyebrowKey = eyebrowKey
        self.headline = AnyView(headline())
        self.bodyKey = bodyKey
        self.illo = illo()
        self.ctas = ctas()
        self.onSkip = onSkip
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 56)
                Eyebrow(key: eyebrowKey).padding(.leading, 30)

                // Illustration plate — 200pt tall (matches the React
                // design's absolute-positioned illo slot at height: 200).
                // Wide enough to fit the Lottie coin + its "+ 15 HP" badge
                // on the HP screen without clipping.
                Spacer().frame(height: 8)
                illo
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                Spacer().frame(height: 14)

                headline
                    .font(ObFont.display(44, weight: .heavy))
                    .tracking(-2)
                    .foregroundStyle(ObPalette.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 30)
                    .lineSpacing(-2)

                Spacer().frame(height: 16)

                LocText(bodyKey)
                    .font(ObFont.sans(14.5, weight: .medium))
                    .foregroundStyle(ObPalette.textDim)
                    .lineSpacing(3)
                    .frame(maxWidth: 320, alignment: .leading)
                    .padding(.horizontal, 30)

                // Force a minimum gap above whatever sits below (CTAs or
                // the parent PageDots overlay) so body never crowds them.
                Spacer(minLength: 96)

                ctas
                    .padding(.horizontal, 18)
                    .padding(.bottom, 130)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SkipLink(action: onSkip)
        }
    }
}

// CTA-less convenience init for screens that just rely on swipe-to-continue.
private extension OnbScaffold where CTAs == EmptyView {
    init(
        eyebrowKey: String,
        @ViewBuilder headline: () -> some View,
        bodyKey: String,
        @ViewBuilder illo: () -> Illo,
        onSkip: @escaping () -> Void
    ) {
        self.init(
            eyebrowKey: eyebrowKey,
            headline: headline,
            bodyKey: bodyKey,
            illo: illo,
            ctas: { EmptyView() },
            onSkip: onSkip
        )
    }
}

// MARK: - 01 · Welcome

private struct Onb1Welcome: View {
    let onSkip: () -> Void
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Top breathing room sits below the status bar but tighter
                // than the original 130pt so subtitle + body sit well clear
                // of the PageDots indicator at the bottom.
                Spacer().frame(height: 88)

                Text("أَسْمَاءُ اللَّه")
                    .font(ObFont.arabic(38))
                    .foregroundStyle(ObPalette.goldSoft)
                    .environment(\.layoutDirection, .rightToLeft)

                Spacer().frame(height: 36)

                Text(verbatim: "Asma")
                    .font(ObFont.display(120, weight: .heavy))
                    .tracking(-6)
                    .foregroundStyle(ObPalette.text)
                    .shadow(color: ObPalette.text.opacity(0.06), radius: 30)

                Spacer().frame(height: 44)

                Rectangle()
                    .fill(ObPalette.goldFaint)
                    .frame(width: 24, height: 1)

                Spacer().frame(height: 20)

                Eyebrow(key: "onboarding.welcome.eyebrow", tracking: 2.8)

                Spacer().frame(height: 20)

                Text(verbatim: Bundle.loc("onboarding.welcome.headline.line1") + "\n" + Bundle.loc("onboarding.welcome.headline.line2"))
                    .font(ObFont.display(32, weight: .bold))
                    .tracking(-1)
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ObPalette.text)

                Spacer().frame(height: 16)

                LocText("onboarding.welcome.body")
                    .font(ObFont.sans(14, weight: .medium))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ObPalette.textDim)
                    .frame(maxWidth: 320)
                    .padding(.horizontal, 28)

                // Guaranteed gap to the PageDots indicator. Beats
                // `Spacer(minLength: 0)` because it enforces a minimum on
                // shorter phones where content would otherwise crowd the
                // indicator.
                Spacer(minLength: 120)
            }
            .frame(maxWidth: .infinity)

            SkipLink(action: onSkip)
        }
    }
}

// MARK: - 02 · Method

private struct Onb2Method: View {
    let onSkip: () -> Void

    private struct Step: Identifiable {
        let id: String
        let titleKey: String
        let bodyKey: String
    }

    private let steps: [Step] = [
        .init(id: "01", titleKey: "onboarding.method.step1.title", bodyKey: "onboarding.method.step1.body"),
        .init(id: "02", titleKey: "onboarding.method.step2.title", bodyKey: "onboarding.method.step2.body"),
        .init(id: "03", titleKey: "onboarding.method.step3.title", bodyKey: "onboarding.method.step3.body"),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 56)
                Eyebrow(key: "onboarding.method.eyebrow").padding(.leading, 30)

                Spacer().frame(height: 40)

                (
                    Text(verbatim: Bundle.loc("onboarding.method.headline.line1")).foregroundStyle(ObPalette.text)
                    + Text(verbatim: "\n")
                    + Text(verbatim: Bundle.loc("onboarding.method.headline.line2")).foregroundStyle(ObPalette.text)
                    + Text(verbatim: "\n")
                    + Text(verbatim: Bundle.loc("onboarding.method.headline.gold")).foregroundStyle(ObPalette.gold)
                )
                .font(ObFont.display(64, weight: .heavy))
                .tracking(-2.4)
                .lineSpacing(-6)
                .padding(.leading, 30)

                Spacer().frame(height: 36)

                VStack(spacing: 0) {
                    ForEach(steps) { s in
                        HStack(alignment: .firstTextBaseline, spacing: 18) {
                            Text(s.id)
                                .font(ObFont.mono(11, weight: .medium))
                                .tracking(1.2)
                                .foregroundStyle(ObPalette.gold)
                                .frame(width: 24, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: Bundle.loc(s.titleKey))
                                    .font(ObFont.display(19, weight: .bold))
                                    .tracking(-0.3)
                                    .foregroundStyle(ObPalette.text)
                                Text(verbatim: Bundle.loc(s.bodyKey))
                                    .font(ObFont.sans(12.5, weight: .medium))
                                    .foregroundStyle(ObPalette.textDim)
                                    .lineSpacing(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(ObPalette.textFaint).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 30)

                // Guaranteed clearance above the indicator on every device.
                Spacer(minLength: 110)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SkipLink(action: onSkip)
        }
    }
}

// MARK: - 03 · Cards & Tests

private struct Onb3Cards: View {
    let onSkip: () -> Void

    var body: some View {
        OnbScaffold(
            eyebrowKey: "onboarding.cards.eyebrow",
            headline: {
                (
                    Text(verbatim: Bundle.loc("onboarding.cards.headline.line1")).foregroundStyle(ObPalette.text)
                    + Text(verbatim: "\n")
                    + Text(verbatim: Bundle.loc("onboarding.cards.headline.line2")).foregroundStyle(ObPalette.text)
                    + Text(verbatim: " ")
                    + Text(verbatim: Bundle.loc("onboarding.cards.headline.gold")).foregroundStyle(ObPalette.gold)
                )
            },
            bodyKey: "onboarding.cards.body",
            illo: { CardsTestsIllo() },
            onSkip: onSkip
        )
    }
}

private struct CardsTestsIllo: View {
    var body: some View {
        HStack(spacing: 22) {
            // Stack of two cards: a faint glass card behind, a deeper
            // glass card in front with the sample name (الرَّحِيم · The Merciful).
            // Both use `editorialGlass*` so they pick up the real
            // `.ultraThinMaterial` blur the design relies on — without it
            // the cards collapse into near-invisible dark rectangles.
            ZStack {
                Color.clear
                    .frame(width: 90, height: 84)
                    .editorialGlass(cornerRadius: 14)
                    .rotationEffect(.degrees(-6))
                    .offset(x: -10, y: 6)

                Color.clear
                    .frame(width: 90, height: 84)
                    .editorialGlassDeep(cornerRadius: 14)
                    .overlay(
                        VStack(spacing: 6) {
                            Text("الرَّحِيم")
                                .font(EditorialFont.arabic(18, weight: .bold))
                                .foregroundStyle(ObPalette.gold)
                                .environment(\.layoutDirection, .rightToLeft)
                                .shadow(color: ObPalette.gold.opacity(0.3), radius: 12)
                            Rectangle().fill(ObPalette.goldFaint).frame(width: 16, height: 1)
                            LocText("onboarding.cards.meaning")
                                .font(ObFont.display(9, weight: .bold))
                                .foregroundStyle(ObPalette.gold)
                        }
                    )
                    .rotationEffect(.degrees(2))
                    .offset(x: 6, y: 0)
            }
            .frame(width: 120, height: 110)

            // Arrow + "then"
            VStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ObPalette.gold.opacity(0.7))
                LocText("onboarding.cards.then")
                    .font(ObFont.sans(8.5, weight: .medium))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(ObPalette.textMute)
            }

            // Three check circles — third one glows (the "three in a row
            // and the name is confirmed" beat from the body copy).
            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    ZStack {
                        Color.clear
                            .frame(width: 32, height: 32)
                            .editorialGlass(cornerRadius: 16)
                            .overlay(
                                Circle().strokeBorder(ObPalette.goldFaint, lineWidth: 1)
                            )
                            .clipShape(Circle())
                            .shadow(
                                color: i == 2 ? ObPalette.gold.opacity(0.3) : .clear,
                                radius: i == 2 ? 14 : 0
                            )
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(ObPalette.gold.opacity(i == 2 ? 1 : 0.55))
                    }
                }
            }
        }
    }
}

// MARK: - 04 · Memory

private struct Onb4Memory: View {
    let onSkip: () -> Void

    var body: some View {
        OnbScaffold(
            eyebrowKey: "onboarding.memory.eyebrow",
            headline: {
                (
                    Text(verbatim: Bundle.loc("onboarding.memory.headline.line1")).foregroundStyle(ObPalette.text)
                    + Text(verbatim: "\n")
                    + Text(verbatim: Bundle.loc("onboarding.memory.headline.line2")).foregroundStyle(ObPalette.text)
                    + Text(verbatim: "\n")
                    + Text(verbatim: Bundle.loc("onboarding.memory.headline.gold")).foregroundStyle(ObPalette.gold)
                )
            },
            bodyKey: "onboarding.memory.body",
            illo: { MemoryIllo() },
            onSkip: onSkip
        )
    }
}

private struct MemoryIllo: View {
    // Day stops + their relative vertical offsets — copied from the design.
    private let stops: [Int] = [1, 3, 7, 14, 30]
    private let ys: [CGFloat] = [70, 28, 56, 56, 38]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dashed horizon line
                Path { p in
                    p.move(to: CGPoint(x: 14, y: 130))
                    p.addLine(to: CGPoint(x: geo.size.width - 14, y: 130))
                }
                .stroke(ObPalette.textFaint, style: StrokeStyle(lineWidth: 1, dash: [2, 4]))

                // Curve through the points (approximated from the design)
                Path { p in
                    let w = geo.size.width
                    p.move(to: CGPoint(x: 24, y: 100))
                    p.addQuadCurve(to: CGPoint(x: w * 0.37, y: 70), control: CGPoint(x: w * 0.24, y: 30))
                    p.addQuadCurve(to: CGPoint(x: w * 0.63, y: 70), control: CGPoint(x: w * 0.5, y: 110))
                    p.addQuadCurve(to: CGPoint(x: w - 24, y: 50), control: CGPoint(x: w * 0.82, y: 30))
                }
                .stroke(ObPalette.goldFaint, lineWidth: 1.3)

                // Dots + labels
                HStack {
                    ForEach(Array(stops.enumerated()), id: \.offset) { idx, d in
                        VStack(spacing: 8) {
                            Circle()
                                .fill(ObPalette.gold)
                                .frame(width: 10, height: 10)
                                .shadow(color: ObPalette.gold.opacity(0.55), radius: 6)
                            Text(String(format: "D%02d", d))
                                .font(ObFont.mono(10, weight: .medium))
                                .tracking(0.8)
                                .foregroundStyle(ObPalette.goldSoft)
                                .monospacedDigit()
                        }
                        .offset(y: ys[idx] - 50)
                        if idx < stops.count - 1 { Spacer() }
                    }
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 300, height: 160)
    }
}

// MARK: - 05 · HP

private struct Onb5HP: View {
    let onSkip: () -> Void

    var body: some View {
        OnbScaffold(
            eyebrowKey: "onboarding.hp.eyebrow",
            headline: {
                (
                    Text(verbatim: Bundle.loc("onboarding.hp.headline.line1")).foregroundStyle(ObPalette.text)
                    + Text(verbatim: "\n")
                    + Text(verbatim: Bundle.loc("onboarding.hp.headline.line2.plain")).foregroundStyle(ObPalette.text)
                    + Text(verbatim: Bundle.loc("onboarding.hp.headline.line2.gold")).foregroundStyle(ObPalette.gold)
                )
            },
            bodyKey: "onboarding.hp.body",
            illo: { HPIllo() },
            onSkip: onSkip
        )
    }
}

private struct HPIllo: View {
    // Same `coin.lottie` asset Reward uses — autoplay + loop. Pulled in via
    // its own `DotLottieAnimation` so multiple HP screens (preview, etc.)
    // don't share state.
    @StateObject private var coin = DotLottieAnimation(
        fileName: "coin",
        config: AnimationConfig(autoplay: true, loop: true)
    )

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // Soft ground glow under the coin — gold radial ellipse,
                // 160×20 with a 6pt blur, sits 14pt above the container's
                // bottom. Numbers taken verbatim from the design.
                Ellipse()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                ObPalette.gold.opacity(0.4),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 20)
                    .offset(y: 76)
                    .blur(radius: 6)

                DotLottieView(dotLottie: coin)
                    .frame(width: 180, height: 180)
            }
            .frame(width: 200, height: 180)

            LocText("onboarding.hp.badge")
                .font(ObFont.mono(13, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(ObPalette.gold)
                .shadow(color: ObPalette.gold.opacity(0.6), radius: 6)
                .monospacedDigit()
        }
    }
}

// MARK: - 06 · Notifications permission

private struct Onb6Notify: View {
    let onSkip: () -> Void
    let onAllow: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        OnbScaffold(
            eyebrowKey: "onboarding.notify.eyebrow",
            headline: {
                (
                    Text(verbatim: Bundle.loc("onboarding.notify.headline.line1")).foregroundStyle(ObPalette.text)
                    + Text(verbatim: "\n")
                    + Text(verbatim: Bundle.loc("onboarding.notify.headline.gold")).foregroundStyle(ObPalette.gold)
                )
            },
            bodyKey: "onboarding.notify.body",
            illo: { NotifyIllo() },
            ctas: { NotifyCTAs(onAllow: onAllow, onSecondary: onSecondary) },
            onSkip: onSkip
        )
    }
}

private struct NotifyIllo: View {
    var body: some View {
        VStack(spacing: 8) {
            toast(timeKey: "09:00", textKey: "onboarding.notify.toast1", opacity: 0.65)
            toast(timeKey: "20:00", textKey: "onboarding.notify.toast2", opacity: 1.0)
        }
        .frame(width: 280)
        .padding(.top, 10)
    }

    private func toast(timeKey: String, textKey: String, opacity: Double) -> some View {
        HStack(spacing: 14) {
            // App-icon badge — the real Asma icon (rendered through
            // `AsmaIcon` so it isn't tied to iOS's restricted AppIcon
            // asset). The 36×36 outer frame is kept verbatim from the
            // design; the icon itself fills the frame with the 8pt
            // rounded corners iOS uses for app-icon glyphs.
            Image("AsmaIcon")
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(ObPalette.goldFaint, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Asma")
                    .font(ObFont.display(12.5, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(ObPalette.text)
                LocText(textKey)
                    .font(ObFont.sans(11.5, weight: .medium))
                    .foregroundStyle(ObPalette.textDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(verbatim: timeKey)
                .font(ObFont.mono(10, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(ObPalette.textMute)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(ObPalette.glassBgDeep)
        )
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
                .opacity(0.55)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(ObPalette.glassBorder, lineWidth: 1)
        )
        .opacity(opacity)
    }
}

private struct NotifyCTAs: View {
    let onAllow: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Button(action: onAllow) {
                LocText("onboarding.notify.primary")
                    .font(ObFont.display(16, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 16)
                    .background(
                        Capsule().fill(ObPalette.gold)
                    )
                    .overlay(
                        Capsule().strokeBorder(ObPalette.gold, lineWidth: 1)
                    )
                    .shadow(color: ObPalette.gold.opacity(0.35), radius: 24)
            }
            .buttonStyle(.plain)

            Button(action: onSecondary) {
                EditorialEyebrow(text: "onboarding.notify.secondary", color: ObPalette.textMute, tracking: 2.4)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 07 · Pace

private struct PaceChipData { let value: Int; let labelKey: String }

private struct Onb7Pace: View {
    @Binding var paceChoice: Int

    private let chips: [PaceChipData] = [
        .init(value: 1,  labelKey: "onboarding.pace.chip.easy"),
        .init(value: 3,  labelKey: "onboarding.pace.chip.gentle"),
        .init(value: 5,  labelKey: "onboarding.pace.chip.steady"),
        .init(value: 10, labelKey: "onboarding.pace.chip.focused"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 56)

            HStack {
                Eyebrow(key: "onboarding.pace.eyebrow")
                Spacer()
                // Counter — page index is fixed to 7th screen here (index 6).
                Text(verbatim: Bundle.loc("onboarding.counter %lld %lld", 7, 8))
                    .font(ObFont.sans(10.5, weight: .medium))
                    .tracking(2.4)
                    .textCase(.uppercase)
                    .foregroundStyle(ObPalette.textMute)
            }
            .padding(.horizontal, 30)

            Spacer().frame(height: 44)

            VStack(alignment: .leading, spacing: -4) {
                ForEach(headlineLines, id: \.self) { line in
                    if !line.isEmpty {
                        Text(verbatim: line)
                    }
                }
            }
            .font(ObFont.display(54, weight: .heavy))
            .tracking(-2.2)
            .foregroundStyle(ObPalette.text)
            .padding(.horizontal, 30)

            Spacer().frame(height: 16)

            LocText("onboarding.pace.body")
                .font(ObFont.sans(14, weight: .medium))
                .lineSpacing(2)
                .foregroundStyle(ObPalette.textDim)
                .frame(maxWidth: 320, alignment: .leading)
                .padding(.horizontal, 30)

            Spacer().frame(height: 36)

            HStack(spacing: 8) {
                ForEach(chips, id: \.value) { chip in
                    PaceChip(chip: chip, isSelected: paceChoice == chip.value) {
                        paceChoice = chip.value
                        Haptics.selection()
                    }
                }
            }
            .padding(.horizontal, 18)

            // Guaranteed clearance above PageDots indicator.
            Spacer(minLength: 120)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headlineLines: [String] {
        [
            Bundle.loc("onboarding.pace.headline.line1"),
            Bundle.loc("onboarding.pace.headline.line2"),
            Bundle.loc("onboarding.pace.headline.line3"),
        ]
    }
}

private struct PaceChip: View {
    let chip: PaceChipData
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text("\(chip.value)")
                    .font(ObFont.display(38, weight: .heavy))
                    .tracking(-1.5)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? ObPalette.gold : ObPalette.text)
                Text(verbatim: Bundle.loc(chip.labelKey))
                    .font(ObFont.sans(10, weight: .semibold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(isSelected ? ObPalette.goldSoft : ObPalette.textMute)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
            .padding(.bottom, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(ObPalette.glassBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isSelected ? ObPalette.gold : ObPalette.glassBorder,
                        lineWidth: isSelected ? 1.2 : 1
                    )
            )
            .shadow(
                color: isSelected ? ObPalette.gold.opacity(0.18) : .clear,
                radius: 30
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 08 · Your name

private struct Onb8Name: View {
    @Binding var name: String
    var focus: FocusState<Bool>.Binding
    let onBegin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 50)
            Eyebrow(key: "onboarding.name.eyebrow").padding(.leading, 30)

            Spacer().frame(height: 14)

            // Decorative top hairline
            Rectangle()
                .fill(ObPalette.goldFaint)
                .frame(width: 28, height: 1)
                .frame(maxWidth: .infinity)

            Spacer().frame(height: 22)

            // Bismillah-style arabic above the heading
            LocText("onboarding.name.arabic")
                .font(EditorialFont.amiri(26))
                .foregroundStyle(ObPalette.goldSoft)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity)

            Spacer().frame(height: 22)

            // Editorial heading
            VStack(spacing: -2) {
                LocText("onboarding.name.headline.line1")
                    .foregroundStyle(ObPalette.text)
                LocText("onboarding.name.headline.gold")
                    .foregroundStyle(ObPalette.gold)
            }
            .font(ObFont.display(50, weight: .heavy))
            .tracking(-2.2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 30)

            Spacer().frame(height: 18)

            LocText("onboarding.name.body")
                .font(ObFont.sans(14.5, weight: .medium))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(ObPalette.textDim)
                .frame(maxWidth: 300, alignment: .center)
                .frame(maxWidth: .infinity)

            Spacer().frame(height: 28)

            // Editorial text input — underline + gold focus colour
            VStack(alignment: .leading, spacing: 12) {
                EditorialEyebrow(
                    text: "onboarding.name.fieldLabel",
                    color: ObPalette.goldSoft,
                    tracking: 2.8,
                    size: 9.5
                )

                TextField(
                    "",
                    text: $name,
                    prompt: Text(verbatim: Bundle.loc("onboarding.name.placeholder"))
                        .font(ObFont.display(32, weight: .bold))
                        .foregroundColor(ObPalette.textMute)
                )
                .font(ObFont.display(32, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(ObPalette.text)
                .tint(ObPalette.gold)
                .focused(focus)
                .submitLabel(.done)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
                .padding(.bottom, 14)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(focus.wrappedValue ? ObPalette.gold : ObPalette.textFaint)
                        .frame(height: 1)
                }

                LocText("onboarding.name.privacy")
                    .font(ObFont.sans(12, weight: .medium))
                    .foregroundStyle(ObPalette.textMute)
            }
            .padding(.horizontal, 30)

            Spacer(minLength: 0)

            // Primary CTA — Begin
            Button(action: onBegin) {
                HStack {
                    LocText("onboarding.name.cta")
                        .font(ObFont.display(18, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.black)
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 44, height: 44)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ObPalette.gold)
                    }
                }
                .padding(.leading, 30)
                .padding(.trailing, 14)
                .padding(.vertical, 14)
                .background(
                    Capsule().fill(ObPalette.gold)
                )
                .overlay(
                    Capsule().strokeBorder(ObPalette.gold, lineWidth: 1)
                )
                .shadow(color: ObPalette.gold.opacity(0.35), radius: 24)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.bottom, 130)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
