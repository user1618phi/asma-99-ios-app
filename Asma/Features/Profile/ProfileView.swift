import SwiftUI
import SwiftData
import StoreKit

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @Environment(LocalizationManager.self) private var localization
    @Query private var statsAll: [UserStats]
    @Query private var progressAll: [NameProgress]
    @AppStorage("asma.userName") private var storedName = ""
    @AppStorage(AppSettingsKey.flashcardCount) private var flashcardCount = AppSettingsKey.flashcardDefault
    @AppStorage(AppSettingsKey.notificationsEnabled) private var notificationsEnabled = false

    @State private var languageSheetPresented = false
    @State private var cardsPerDaySheetPresented = false
    @State private var permissionDeniedAlert = false

    /// Telegram handle used by every Support row. One place to update
    /// if it ever moves.
    private let supportHandle = "kassym0vv"

    /// Three kinds of Support taps. Each carries a localized prefill
    /// that lands in the Telegram input ready to send.
    private enum SupportReason {
        case contact, feature, bug

        var messageKey: String {
            switch self {
            case .contact: return "support.message.contact"
            case .feature: return "support.message.feature"
            case .bug:     return "support.message.bug"
            }
        }
    }

    private var stats: UserStats { statsAll.first ?? context.userStats() }

    private var displayName: String {
        let onboarding = storedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !onboarding.isEmpty { return onboarding }
        return stats.displayName.isEmpty ? String(localized: "profile.guestName") : stats.displayName
    }

    private var firstInitial: String {
        displayName.first.map { String($0).uppercased() } ?? "•"
    }

    /// Names the user has confirmed (state ≥ .confirmed). Same definition
    /// as Home / Learn / Stats so the "X / 99" stat reads the same number
    /// everywhere in the app.
    private var learnedCount: Int {
        progressAll.filter { $0.reviewStateRaw >= ReviewState.confirmed.rawValue }.count
    }

    private var beganDate: Date {
        progressAll
            .compactMap(\.lastReviewedAt)
            .min() ?? Date()
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            EditorialPalette.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 30)

                    topRow
                        .padding(.horizontal, 30)

                    identityRow
                        .padding(.top, 38)
                        .padding(.horizontal, 30)

                    heroStatsCard
                        .padding(.top, 28)
                        .padding(.horizontal, 18)

                    generalSection
                        .padding(.top, 36)

                    supportSection
                        .padding(.top, 28)

                    aboutSection
                        .padding(.top, 28)

                    legalSection
                        .padding(.top, 28)
                        .padding(.bottom, 40)
                }
            }

            // Sibling of the ScrollView inside the same ZStack — pinned
            // to top-right and never scrolls with content. Same anchor
            // pattern and padding values used on Home, Tests, and Learn
            // so the button sits at the identical position across tabs.
            AmbientSoundButton()
                .padding(.top, 8)
                .padding(.trailing, 18)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $languageSheetPresented) {
            LanguagePicker()
                .presentationDetents([.medium])
                .presentationBackground(EditorialPalette.bg)
        }
        .sheet(isPresented: $cardsPerDaySheetPresented) {
            CardsPerDayPicker()
                .presentationDetents([.medium])
                .presentationBackground(EditorialPalette.bg)
        }
        .alert(
            Text(verbatim: Bundle.loc("notif.permission.denied.title")),
            isPresented: $permissionDeniedAlert
        ) {
            Button("common.ok", role: .cancel, action: {})
        } message: {
            Text(verbatim: Bundle.loc("notif.permission.denied.body"))
        }
    }

    // MARK: - Top row

    private var topRow: some View {
        HStack {
            EditorialEyebrow(text: "profile.eyebrow")
            Spacer()
        }
    }

    // MARK: - Identity

    private var identityRow: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .strokeBorder(EditorialPalette.goldFaint, lineWidth: 1)
                    .background(
                        Circle().fill(EditorialPalette.gold.opacity(0.10))
                    )
                    .frame(width: 68, height: 68)
                Text(firstInitial)
                    .font(EditorialFont.display(26, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(EditorialPalette.gold)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(EditorialFont.display(38, weight: .heavy))
                    .tracking(-1.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(EditorialPalette.text)
                Text(verbatim: Bundle.loc("profile.began %@", beganMonthYear))
                    .font(EditorialFont.sans(13, weight: .medium))
                    .foregroundStyle(EditorialPalette.textDim)
            }
        }
    }

    /// Locale-aware "Month Year" string derived from the user's earliest
    /// recorded activity. Read inside body via `localization.current`, so it
    /// re-renders when the user switches language.
    private var beganMonthYear: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: localization.current.rawValue)
        fmt.dateFormat = "LLLL yyyy"
        return fmt.string(from: beganDate)
    }

    // MARK: - Hero stat

    private var heroStatsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                EditorialEyebrow(text: "profile.hero.eyebrow")
                Spacer()
                EditorialEyebrow(text: "profile.hero.suffix", color: EditorialPalette.textMute, tracking: 1, size: 11, weight: .medium)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(String(format: "%02d", learnedCount))
                    .font(EditorialFont.display(96, weight: .heavy))
                    .tracking(-5)
                    .monospacedDigit()
                    .foregroundStyle(EditorialPalette.gold)
                    .shadow(color: EditorialPalette.gold.opacity(0.25), radius: 30)
                Text("/ 99")
                    .font(EditorialFont.display(28, weight: .semibold))
                    .tracking(-1)
                    .monospacedDigit()
                    .foregroundStyle(EditorialPalette.textMute)
            }
            .padding(.top, 12)

            ticks
                .padding(.top, 22)

            poeticCaption
                .font(EditorialFont.sans(12.5, weight: .medium))
                .lineSpacing(3)
                .foregroundStyle(EditorialPalette.textDim)
                .padding(.top, 16)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .editorialGlassDeep(cornerRadius: 32)
    }

    /// 99-tick progress visualiser drawn in a single Canvas pass — one
    /// GPU draw call instead of 99 individual Rectangles + 99 shadows
    /// (which was the cause of the visible lag on this screen).
    private var ticks: some View {
        Canvas { ctx, size in
            let total = 99
            let spacing: CGFloat = 2
            let tickWidth = (size.width - spacing * CGFloat(total - 1)) / CGFloat(total)
            let learnedHeight: CGFloat = 22
            let idleHeight: CGFloat = 8
            let goldColor = Color(red: 201/255, green: 168/255, blue: 106/255)
            let faintColor = Color(red: 244/255, green: 239/255, blue: 227/255).opacity(0.16)
            for i in 0..<total {
                let isLearned = i < learnedCount
                let h = isLearned ? learnedHeight : idleHeight
                let x = CGFloat(i) * (tickWidth + spacing)
                let rect = CGRect(
                    x: x,
                    y: size.height - h,
                    width: tickWidth,
                    height: h
                )
                ctx.fill(
                    Path(rect),
                    with: .color(isLearned ? goldColor : faintColor)
                )
            }
        }
        .frame(height: 22)
    }

    private var poeticCaption: Text {
        if learnedCount == 0 {
            return Text(verbatim: Bundle.loc("profile.poetic.start"))
        }
        let remaining = max(0, 99 - learnedCount)
        return Text(verbatim: Bundle.loc("profile.poetic %lld", remaining))
    }

    // MARK: - General

    private var generalSection: some View {
        GlassSection(titleKey: "profile.general") {
            GlassRow(
                symbol: "target",
                labelKey: "profile.cards_per_day",
                value: "\(flashcardCount)"
            ) {
                cardsPerDaySheetPresented = true
            }
            GlassRowDivider()
            GlassRow(
                symbol: "globe",
                labelKey: "profile.languages",
                value: localization.current.displayName
            ) {
                languageSheetPresented = true
            }
            GlassRowDivider()
            GlassToggleRow(
                symbol: "bell",
                labelKey: "profile.notifications",
                isOn: $notificationsEnabled,
                onChange: handleNotificationsToggle(on:)
            )
        }
    }

    // MARK: - Support

    private var supportSection: some View {
        GlassSection(titleKey: "profile.section.support") {
            GlassRow(symbol: "bubble.left.and.bubble.right", labelKey: "profile.contact_us") {
                openSupport(.contact)
            }
            GlassRowDivider()
            GlassRow(symbol: "lightbulb", labelKey: "profile.request_feature") {
                openSupport(.feature)
            }
            GlassRowDivider()
            GlassRow(symbol: "exclamationmark.bubble", labelKey: "profile.report_bug") {
                openSupport(.bug)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        GlassSection(titleKey: "profile.section.about") {
            GlassRow(symbol: "person.2", labelKey: "profile.follow_us") {
                // TODO: replace with the real social URL once published.
            }
            GlassRowDivider()
            GlassRow(symbol: "star", labelKey: "profile.rate_us") {
                // Goes straight to Apple's native rating prompt — no
                // pre-prompt overlay here because the user is already
                // in Profile explicitly asking to rate.
                //
                // Apple throttles to ≤3 prompts/year/device, and the
                // call no-ops past that, so we can call freely. Marks
                // the user as "rated" so the post-onboarding overlay +
                // Home banner never auto-appear again.
                RateUsService.triggerSystemPrompt(requestReview: requestReview)
                Haptics.tap()
            }
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        GlassSection(titleKey: "profile.section.legal") {
            GlassRow(symbol: "doc.text", labelKey: "profile.terms_of_service") {
                // TODO: replace with hosted Terms of Service URL.
            }
            GlassRowDivider()
            GlassRow(symbol: "hand.raised", labelKey: "profile.privacy_policy") {
                // TODO: replace with hosted Privacy Policy URL.
            }
        }
    }

    // MARK: - Actions

    /// Open the Support chat with a localized message already typed into
    /// the Telegram input. Prefers the `tg://resolve` URL scheme (which
    /// the Telegram iOS client honors with the `text` parameter); if
    /// Telegram isn't installed, falls back to the universal https link.
    private func openSupport(_ reason: SupportReason) {
        let text = Bundle.loc(reason.messageKey)
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        let appURL = URL(string: "tg://resolve?domain=\(supportHandle)&text=\(encoded)")!
        let webURL = URL(string: "https://t.me/\(supportHandle)?text=\(encoded)")!

        openURL(appURL) { accepted in
            if !accepted {
                openURL(webURL)
            }
        }
    }

    /// Master toggle handler. Turning ON requests system authorisation
    /// in response to the user's gesture (HIG-correct). If they deny,
    /// the toggle snaps back to OFF and we explain what to do.
    private func handleNotificationsToggle(on: Bool) {
        if on {
            Task {
                let granted = await NotificationsService.requestAuthorization()
                await MainActor.run {
                    if granted {
                        notificationsEnabled = true
                    } else {
                        notificationsEnabled = false
                        permissionDeniedAlert = true
                    }
                }
            }
        } else {
            notificationsEnabled = false
            NotificationsService.cancelAll()
        }
        Haptics.selection()
    }
}
