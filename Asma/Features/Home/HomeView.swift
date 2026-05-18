import SwiftUI
import SwiftData

/// Where the user is in their day-cycle. Drives copy + routing for the
/// big CTA cards on Home and Learn. Shared so both call sites use the
/// same derivation logic and stay in sync.
///
/// Priority on Home: `fresh > studyingToday > readyToTest > caughtUp`.
/// We intentionally put "studyingToday" above "readyToTest" — the user
/// wants today's flashcards finished first, then tested. Due-reviews
/// from earlier days are still picked up by `readyToTest` once today's
/// new pile is closed.
enum SessionStatus: Equatable {
    /// Nothing introduced yet — first-ever launch.
    case fresh
    /// Today's flashcard goal not yet hit. `remaining` = how many more
    /// cards to study before the goal flips to met.
    case studyingToday(remaining: Int)
    /// A test just happened and the policy-enforced spacing window is
    /// still open. `remaining` = seconds until the next round unlocks;
    /// `count` is the full eligible pool that's waiting for you.
    case cooldown(remaining: TimeInterval, count: Int)
    /// Today's cards done (or there's past due) and the test pool has
    /// names ready. `count` is the full eligible pool (newToday + dueReviews).
    case readyToTest(count: Int)
    /// Nothing left to do today — pool is empty, goal was met.
    case caughtUp
}

struct HomeView: View {
    let switchTab: (RootTab) -> Void

    @Environment(\.modelContext) private var context
    @Environment(LocalizationManager.self) private var localization
    @Query private var progressAll: [NameProgress]
    @Query(sort: \XPEvent.date, order: .forward) private var xpEvents: [XPEvent]
    /// Today's test attempts feed the Continue CTA's round counter:
    /// after each test we show "Round N+1" so the user gets visible
    /// movement between sessions (the pool count stays put until a name
    /// hits Confirmed, which often takes 3 rounds).
    @Query private var testAttempts: [TestAttempt]
    @AppStorage("asma.userName") private var storedName = ""
    @AppStorage(AppSettingsKey.flashcardCount) private var flashcardCount = AppSettingsKey.flashcardDefault

    @State private var path = NavigationPath()
    @State private var animateIn = false

    // Rate-us. Just the centered overlay now (Home banner was removed).
    // Read once on appear and whenever the app comes back to foreground
    // from `RateUsService`'s UserDefaults-backed state.
    @State private var showRateOverlay = false
    @Environment(\.scenePhase) private var scenePhase

    /// Names the user has confirmed through tests (3-correct-in-a-row,
    /// then graduating up the spaced ladder). Same definition lives in
    /// FlashcardsLanding / Profile / Stats — one principle everywhere,
    /// so the "X / 99" never lies in one place while telling the truth
    /// in another.
    private var learnedCount: Int {
        progressAll.filter { $0.reviewStateRaw >= ReviewState.confirmed.rawValue }.count
    }
    private var language: String { localization.current.rawValue }

    private var greetingName: String {
        let n = storedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? String(localized: "profile.guestName") : n
    }

    /// Next-up name. Priority:
    ///   1. an already-started `.studying` name (continue what you began)
    ///   2. an untouched `.new` name (start the next one in sequence)
    ///   3. fallback to lowest masteryLevel / lowest number for legacy data
    /// Mastered and strengthening names sink to the bottom — the user
    /// doesn't need a hero-card nudge to revisit a name the spaced-review
    /// queue will surface on its own schedule.
    private var currentName: AsmaName {
        let progressMap = Dictionary(uniqueKeysWithValues: progressAll.map { ($0.number, $0) })
        let names = NamesRepository.shared.names

        func priority(for name: AsmaName) -> Int {
            let state = progressMap[name.number]
                .flatMap { ReviewState(rawValue: $0.reviewStateRaw) } ?? .new
            switch state {
            case .studying:      return 0
            case .new:           return 1
            case .confirmed:     return 2
            case .strengthening: return 3
            case .mastered:      return 4
            }
        }

        let sorted = names.sorted { a, b in
            let pa = priority(for: a)
            let pb = priority(for: b)
            if pa != pb { return pa < pb }
            let ma = progressMap[a.number]?.masteryLevel ?? 0
            let mb = progressMap[b.number]?.masteryLevel ?? 0
            if ma != mb { return ma < mb }
            return a.number < b.number
        }
        return sorted.first ?? names.first!
    }

    /// Number of names whose spaced-review slot has come due (or passed).
    /// Surfaced as a small eyebrow on the progress rail so the user has a
    /// visible reason to head to Tests today even when they haven't done
    /// their daily new names yet.
    private var dueReviewCount: Int {
        TodayPoolFactory.todayCounts(progresses: progressAll).dueReviews
    }

    /// How many test sessions the user has already finished today.
    /// Drives the round-counter shown on the `readyToTest` CTA so the
    /// user sees progress between sessions (the names-in-pool number
    /// stays put until each one reaches Confirmed).
    private var testsCompletedToday: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return testAttempts.filter { cal.startOfDay(for: $0.date) == today }.count
    }

    /// How many flashcards the user has touched today. Used to detect
    /// whether the daily flashcard goal (`flashcardCount`) is hit, which
    /// is what flips `studyingToday` → `readyToTest`.
    private var studiedTodayCount: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return progressAll.filter {
            if let last = $0.lastStudiedAt {
                return cal.startOfDay(for: last) == today
            }
            return false
        }.count
    }

    /// State of the user's day, used to pick the right copy + destination
    /// for the Continue CTA. Priority: fresh > studyingToday > cooldown
    /// > readyToTest > caughtUp. Cooldown sits between studyingToday and
    /// readyToTest because it's a post-test wait; the user has already
    /// finished today's cards by the time it can ever trigger.
    private var sessionStatus: SessionStatus {
        let introduced = progressAll.filter {
            $0.reviewStateRaw >= ReviewState.studying.rawValue
        }.count
        if introduced == 0 { return .fresh }

        let goal = flashcardCount
        let studied = studiedTodayCount
        if studied < goal {
            return .studyingToday(remaining: goal - studied)
        }

        let counts = TodayPoolFactory.todayCounts(progresses: progressAll)
        let poolTotal = counts.newToday + counts.dueReviews
        if poolTotal > 0 {
            let wait = CooldownPolicy.remaining(testAttempts: testAttempts)
            if wait > 0 {
                return .cooldown(remaining: wait, count: poolTotal)
            }
            return .readyToTest(count: poolTotal)
        }

        return .caughtUp
    }

    private var continueEyebrowKey: String {
        switch sessionStatus {
        case .fresh:         return "home.cta.fresh.eyebrow"
        case .studyingToday: return "home.cta.studying.eyebrow"
        case .cooldown:      return "home.cta.cooldown.eyebrow"
        case .readyToTest:   return "home.cta.review.eyebrow"
        case .caughtUp:      return "home.cta.done.eyebrow"
        }
    }

    private var continueTitle: String {
        switch sessionStatus {
        case .fresh:                  return Bundle.loc("home.cta.fresh.title")
        case .studyingToday:          return Bundle.loc("home.cta.studying.title")
        case .cooldown(let remaining, _):
            return cooldownTitle(remaining: remaining)
        case .readyToTest:
            // Title shows the round counter (1, 2, 3, …) — it moves after
            // every completed test, which is the user-visible signal that
            // their last session was registered. Pool count lives in the
            // subtitle.
            return Bundle.loc("home.cta.review.title %lld", testsCompletedToday + 1)
        case .caughtUp:               return Bundle.loc("home.cta.done.title")
        }
    }

    private var continueSubtitle: String {
        switch sessionStatus {
        case .fresh:
            return Bundle.loc("home.cta.fresh.subtitle %lld %lld", flashcardCount, sessionMinutes)
        case .studyingToday(let remaining):
            let mins = max(1, Int(ceil(Double(remaining) * 20.0 / 60.0)))
            return Bundle.loc("home.cta.studying.subtitle %lld %lld", remaining, mins)
        case .cooldown:
            return Bundle.loc("home.cta.cooldown.subtitle")
        case .readyToTest(let count):
            return Bundle.loc("home.cta.review.subtitle %lld", count)
        case .caughtUp:
            return Bundle.loc("home.cta.done.subtitle")
        }
    }

    /// Formats the cooldown countdown into one of three shapes so the
    /// copy reads naturally in every language:
    ///   - "Next round in 27m" — minutes only
    ///   - "Next round in 1h"  — hours only (skips a trailing "0m")
    ///   - "Next round in 1h 27m" — both
    private func cooldownTitle(remaining: TimeInterval) -> String {
        let totalMinutes = max(1, Int(ceil(remaining / 60)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 {
            return Bundle.loc("home.cta.cooldown.title.hoursAndMinutes %lld %lld", hours, minutes)
        }
        if hours > 0 {
            return Bundle.loc("home.cta.cooldown.title.hours %lld", hours)
        }
        return Bundle.loc("home.cta.cooldown.title.minutes %lld", minutes)
    }

    /// Real calendar "Day N" — distinct days on which the user has any
    /// activity (an XP event, a name review, or simply opens Home today).
    /// First-ever launch = Day 01.
    private var dayNumber: Int {
        let cal = Calendar.current
        var days = Set<Date>()
        days.insert(cal.startOfDay(for: Date()))
        for event in xpEvents { days.insert(cal.startOfDay(for: event.date)) }
        for p in progressAll {
            if let d = p.lastReviewedAt { days.insert(cal.startOfDay(for: d)) }
        }
        return max(1, days.count)
    }

    /// Rough estimate: ~20s per card → ceil(count * 20 / 60) minutes.
    private var sessionMinutes: Int {
        max(1, Int(ceil(Double(flashcardCount) * 20.0 / 60.0)))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                EditorialPalette.bg.ignoresSafeArea()

                // Subtle gold radial glow centred on the hero — a quiet
                // luminescence rather than a stock backdrop.
                RadialGradient(
                    colors: [
                        EditorialPalette.gold.opacity(0.07),
                        EditorialPalette.gold.opacity(0.02),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 320
                )
                .ignoresSafeArea()
                .blendMode(.plusLighter)

                content
            }
            .overlay(alignment: .topTrailing) {
                AmbientSoundButton()
                    .padding(.top, 8)
                    .padding(.trailing, 18)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AsmaName.self) { NameDetailView(name: $0) }
            .navigationDestination(for: FlashcardsRoute.self) { route in
                switch route {
                case .session:      FlashcardsSessionView(mode: .todaysPool)
                case .freePractice: FlashcardsSessionView(mode: .freePractice)
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.55)) { animateIn = true }
                refreshRateUsState()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // User came back from background (maybe past 08:00 now,
                // or maybe just finished a test in another tab) — re-check.
                if newPhase == .active { refreshRateUsState() }
            }
            // Centered Rate-us modal — has its own backdrop, sits on top
            // of everything.
            .overlay {
                if showRateOverlay {
                    RateUsOverlay {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showRateOverlay = false
                        }
                        // After overlay closes, the banner state may now
                        // be eligible — re-evaluate.
                        refreshRateUsState()
                    }
                    .zIndex(100)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Re-read the rate-us state machine. Cheap, no-op when nothing
    /// changes (the @State setter only triggers a redraw on a real diff).
    /// Only the centered overlay is wired now — the Home banner was
    /// removed entirely.
    private func refreshRateUsState() {
        let overlay = RateUsService.shouldShowOverlay
        if showRateOverlay != overlay { showRateOverlay = overlay }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            greetingRow
                .padding(.top, 30)
                .padding(.horizontal, 30)
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 12)

            Spacer(minLength: 0)

            hero
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 16)

            Spacer(minLength: 0)

            if dueReviewCount > 0 {
                dueReviewPill
                    .padding(.bottom, 18)
                    .opacity(animateIn ? 1 : 0)
            }

            progressRail
                .padding(.horizontal, 30)
                .opacity(animateIn ? 1 : 0)

            Spacer().frame(height: 28)

            continueCTA
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Greeting eyebrow

    private var greetingRow: some View {
        HStack {
            EditorialEyebrow(
                literal: Bundle.loc("home.greeting %@", greetingName),
                color: EditorialPalette.goldSoft,
                tracking: 2.4
            )
            Spacer()
        }
    }

    // MARK: - Hero name of the day

    private var hero: some View {
        Button {
            path.append(currentName)
            Haptics.tap()
        } label: {
            VStack(spacing: 0) {
                Text(currentName.arabic)
                    .font(EditorialFont.arabic(60, weight: .regular))
                    .tracking(-1)
                    .foregroundStyle(EditorialPalette.gold)
                    .environment(\.layoutDirection, .rightToLeft)
                    .shadow(color: EditorialPalette.gold.opacity(0.18), radius: 60)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(currentName.transliteration)
                    .font(EditorialFont.display(64, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(EditorialPalette.text)
                    .padding(.top, 36)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(currentName.translation(for: language).translation)
                    .font(EditorialFont.display(19, weight: .light))
                    .foregroundStyle(EditorialPalette.textDim)
                    .padding(.top, 18)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Due review pill

    /// Soft gold pill nudging the user that the spaced-repetition queue
    /// has work for them today. Only renders when `dueReviewCount > 0` —
    /// silent UI when there's nothing to revisit.
    private var dueReviewPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(EditorialPalette.gold)
            Text(verbatim: Bundle.loc("home.dueReviews %lld", dueReviewCount))
                .font(EditorialFont.sans(11, weight: .semibold))
                .tracking(2.0)
                .textCase(.uppercase)
                .foregroundStyle(EditorialPalette.gold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(EditorialPalette.gold.opacity(0.08)))
        .overlay(Capsule().strokeBorder(EditorialPalette.goldFaint, lineWidth: 1))
    }

    // MARK: - Editorial progress rail

    private var progressRail: some View {
        HStack(spacing: 14) {
            EditorialEyebrow(
                literal: Bundle.loc("home.day %lld", dayNumber),
                color: EditorialPalette.textMute,
                tracking: 2.4,
                size: 9.5
            )

            GeometryReader { geo in
                let fraction = max(0.02, min(1, Double(learnedCount) / 99))
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(EditorialPalette.textFaint)
                        .frame(height: 1)
                    Rectangle()
                        .fill(EditorialPalette.gold)
                        .frame(width: geo.size.width * CGFloat(fraction), height: 1)
                        .shadow(color: EditorialPalette.gold.opacity(0.6), radius: 8)
                }
            }
            .frame(height: 1)

            EditorialEyebrow(
                literal: Bundle.loc("home.progress %lld", learnedCount),
                color: EditorialPalette.textMute,
                tracking: 2.4,
                size: 9.5
            )
        }
    }

    // MARK: - Continue CTA

    private var continueCTA: some View {
        // TimelineView wakes up every 30s so the cooldown countdown re-derives
        // a fresh `sessionStatus` (which reads `Date()`). Outside cooldown the
        // periodic redraw is cheap and idempotent.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            continueCardButton
        }
    }

    private var continueCardButton: some View {
        Button {
            handleContinueTap()
            Haptics.tap()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                EditorialEyebrow(text: continueEyebrowKey)

                Text(verbatim: continueTitle)
                    .font(EditorialFont.display(38, weight: .bold))
                    .tracking(-0.5)
                    .lineSpacing(2)
                    .foregroundStyle(EditorialPalette.text)
                    .padding(.top, 8)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 0) {
                    Text(verbatim: continueSubtitle)
                        .font(EditorialFont.sans(13, weight: .medium))
                        .foregroundStyle(EditorialPalette.textDim)

                    Spacer(minLength: 12)

                    ZStack {
                        Circle()
                            .strokeBorder(EditorialPalette.goldFaint, lineWidth: 1)
                            .background(Circle().fill(EditorialPalette.gold.opacity(0.04)))
                            .frame(width: 44, height: 44)
                        Image(systemName: continueArrowIcon)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(EditorialPalette.gold)
                    }
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .editorialGlassDeep(cornerRadius: 32)
            .contentShape(Rectangle())
            .opacity(continueDisabled ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(continueDisabled)
    }

    /// Subtle visual signal that pairs with the copy: cooldown shows an
    /// hourglass, caughtUp shows a checkmark, everything else shows the
    /// forward arrow. Reinforces "what is this card asking of me" at a
    /// glance.
    private var continueArrowIcon: String {
        switch sessionStatus {
        case .cooldown: return "hourglass"
        case .caughtUp: return "checkmark"
        default:        return "arrow.right"
        }
    }

    /// Whether the CTA should reject taps. Cooldown is the only
    /// non-actionable state — it's a passive countdown, no destination.
    private var continueDisabled: Bool {
        if case .cooldown = sessionStatus { return true }
        return false
    }

    /// Routing per state:
    ///  - fresh / studyingToday → push flashcard session directly into Home's
    ///    nav stack (one tap from Home to actually studying).
    ///  - readyToTest → Tests tab (the user picks a mode there).
    ///  - caughtUp → Learn tab to browse the ninety-nine for contemplation.
    ///  - cooldown → no-op (`.disabled` on the button takes precedence anyway).
    private func handleContinueTap() {
        switch sessionStatus {
        case .fresh, .studyingToday:
            path.append(FlashcardsRoute.session)
        case .readyToTest:
            switchTab(.tests)
        case .caughtUp:
            switchTab(.learn)
        case .cooldown:
            break
        }
    }
}
