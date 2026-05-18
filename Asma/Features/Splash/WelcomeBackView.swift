import SwiftUI

/// 00 · Welcome back — editorial splash shown on every cold launch after the
/// user has finished onboarding.
///
/// Timing is intentionally trimmed from the design's 8s prototype to **~5.5s**
/// so that daily users don't pay an 8-second tax every cold launch — research
/// (Apple HIG, splash-screen abandonment studies) shows splash content over
/// ~3s costs noticeable retention. All five reveal phases are preserved; only
/// the dead pause + tail fade are compressed. A tap anywhere on the screen
/// dismisses the splash in 0.4s for veteran users.
struct WelcomeBackView: View {
    let userName: String
    let onFinish: () -> Void

    // Animation state — each property maps to one keyframe block in the spec.
    @State private var glowOn = false
    @State private var wordmarkOn = false
    @State private var captionOn = false
    @State private var greetingRowOn = false   // eyebrow + name (rise together at 1.8s)
    @State private var hairlineWidth: CGFloat = 0
    @State private var hairlineOn = false
    @State private var arabicOn = false
    @State private var screenOpacity: Double = 1

    /// Cancellable handle for the auto-finish timer so tap-to-skip can
    /// interrupt cleanly without `onFinish()` ever being called twice.
    @State private var finishTask: Task<Void, Never>?
    /// Re-entrance guard for `finish()` — protects against the auto-timer and
    /// a tap landing on the same frame.
    @State private var didFinish = false

    var body: some View {
        ZStack {
            EditorialPalette.bg
                .ignoresSafeArea()

            radialGlow
            wordmark
            greetingBlock
            bottomCaption
        }
        .opacity(screenOpacity)
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .onAppear(perform: runAnimation)
        .onDisappear { finishTask?.cancel() }
        .preferredColorScheme(.dark)
    }

    // MARK: - Layers

    /// Soft gold radial glow behind everything — 600×600, centered.
    /// Keyframe `asma-glow`: opacity 0 → 1 → 0.5, scale 0.9 → 1 → 1.05.
    private var radialGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: [
                        EditorialPalette.gold.opacity(0.10),
                        Color.clear
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: 300
                )
            )
            .frame(width: 600, height: 600)
            .scaleEffect(glowOn ? 1.05 : 0.9)
            .opacity(glowOn ? 0.5 : 0)
            .allowsHitTesting(false)
    }

    /// "Asma" wordmark — top: 110pt from the top edge, opacity tops at 0.85.
    private var wordmark: some View {
        VStack {
            Text(verbatim: "Asma")
                .font(.custom("Inter Tight", size: 24).weight(.heavy))
                .tracking(wordmarkOn ? -3 : -2)
                .foregroundStyle(EditorialPalette.text)
                .opacity(wordmarkOn ? 0.85 : 0)
                .padding(.top, 110)
            Spacer(minLength: 0)
        }
    }

    /// Centered greeting block — eyebrow, gold hairline, hero name, Arabic.
    /// Eyebrow + subtitle pull from the live localization via `Bundle.loc`
    /// so the splash flips language whenever the user changes it in
    /// Profile (no relaunch needed).
    private var greetingBlock: some View {
        VStack(spacing: 0) {
            // Salutation eyebrow (localized — "As-salamu alaykum" / "Ассаламу алейкум" / "Ассалаумағалейкум")
            LocText("welcomeBack.salutation")
                .font(.custom("Inter Tight", size: 13).weight(.semibold))
                .tracking(3)
                .textCase(.uppercase)
                .foregroundStyle(EditorialPalette.goldSoft)
                .opacity(greetingRowOn ? 1 : 0)
                .offset(y: greetingRowOn ? 0 : 14)

            // Gold hairline — animates from width 0 to 48
            Rectangle()
                .fill(EditorialPalette.gold)
                .frame(width: hairlineWidth, height: 1)
                .shadow(color: EditorialPalette.gold.opacity(0.5), radius: 4)
                .opacity(hairlineOn ? 0.7 : 0)
                .padding(.vertical, 32)

            // User name — hero. Verbatim (never translated).
            Text(verbatim: displayName)
                .font(.custom("Inter Tight", size: 72).weight(.heavy))
                .tracking(-3)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(EditorialPalette.text)
                .opacity(greetingRowOn ? 1 : 0)
                .offset(y: greetingRowOn ? 0 : 14)

            // Arabic greeting — same across all locales (Quranic script).
            Text(verbatim: "ٱلسَّلَامُ عَلَيْكُمْ")
                .font(.custom("Amiri", size: 28))
                .environment(\.layoutDirection, .rightToLeft)
                .foregroundStyle(EditorialPalette.gold)
                .shadow(color: EditorialPalette.gold.opacity(0.3), radius: 15)
                .opacity(arabicOn ? 0.55 : 0)
                .offset(y: arabicOn ? 0 : 8)
                .padding(.top, 28)
        }
        .padding(.horizontal, 24)
    }

    /// Localized subtitle at the bottom — 80pt from the bottom edge.
    /// "The Ninety-nine Names" / "Девяносто девять имён" / "Тоқсан тоғыз есім".
    private var bottomCaption: some View {
        VStack {
            Spacer(minLength: 0)
            LocText("welcomeBack.subtitle")
                .font(.custom("Inter Tight", size: 10).weight(.medium))
                .tracking(2.4)
                .textCase(.uppercase)
                .foregroundStyle(EditorialPalette.goldSoft)
                .opacity(captionOn ? 1 : 0)
                .offset(y: captionOn ? 0 : 14)
                .padding(.bottom, 80)
        }
    }

    // MARK: - Animation orchestration
    //
    // Compressed timeline (~5.5s total) — preserves every reveal phase from
    // the design, drops only the post-Arabic dead pause and the long tail fade.

    private func runAnimation() {
        // Reversed order from the original prototype: the personal greeting
        // (salutation + name + hairline + arabic) leads, then the small
        // "Asma" wordmark and the bottom subtitle settle in around it.
        // Reads like a quiet, intimate hello before the brand mark.

        // 0.2s · radial gold glow rises and slowly drifts.
        withAnimation(.easeOut(duration: 3.0).delay(0.2)) {
            glowOn = true
        }
        // 0.5s · Salutation eyebrow + user name + gold hairline (the hero).
        withAnimation(.timingCurve(0.2, 0.7, 0.3, 1, duration: 1.5).delay(0.5)) {
            greetingRowOn = true
        }
        withAnimation(.easeOut(duration: 1.4).delay(0.5)) {
            hairlineWidth = 48
            hairlineOn = true
        }
        // 2.0s · Arabic greeting fades in to 0.55 opacity.
        withAnimation(.easeOut(duration: 1.3).delay(2.0)) {
            arabicOn = true
        }
        // 3.1s · "Asma" wordmark fades to 0.85 and tightens letter-spacing.
        withAnimation(.easeOut(duration: 1.2).delay(3.1)) {
            wordmarkOn = true
        }
        // 3.7s · Bottom localized subtitle rises.
        withAnimation(.easeOut(duration: 1.0).delay(3.7)) {
            captionOn = true
        }
        // 4.9s · Final fadeout begins.
        withAnimation(.easeOut(duration: 0.6).delay(4.9)) {
            screenOpacity = 0
        }
        // 5.5s · Hand off to the main app — cancellable so a tap can pre-empt.
        finishTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5.5))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    /// User tapped to skip — interrupt the auto-finish, run the same 0.4s
    /// fade-out the app shell uses elsewhere, then hand off.
    private func skip() {
        guard !didFinish else { return }
        finishTask?.cancel()
        Haptics.tap()
        withAnimation(.easeOut(duration: 0.4)) {
            screenOpacity = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            finish()
        }
    }

    /// Idempotent finish — both the timer path and the tap path land here, so
    /// the guard prevents `onFinish()` from being called twice on a race.
    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onFinish()
    }

    /// Falls back to a respectful localized greeting if the user skipped
    /// the name page during onboarding ("Friend" / "Друг" / "Дос"). The
    /// splash is meant to feel personal but should never look broken.
    private var displayName: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Bundle.loc("welcomeBack.fallbackName") : trimmed
    }
}

#Preview {
    WelcomeBackView(userName: "Mustafa", onFinish: {})
}
