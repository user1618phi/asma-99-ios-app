import SwiftUI
import SwiftData

struct TestSessionView: View {
    let mode: TestMode
    let questionCount: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalizationManager.self) private var localization
    @Query private var progresses: [NameProgress]

    @State private var session: TestSession?
    @State private var selectedIndex: Int?
    @State private var didSubmit = false
    @State private var finished = false
    @State private var startupResolved = false
    @State private var namesConfirmedThisSession = 0
    @State private var namesMasteredThisSession = 0
    /// Sum of every XP award fired in this test session — drives the
    /// RewardView's +HP number. Includes test base XP plus the per-name
    /// confirmed/mastered milestone bonuses.
    @State private var xpEarnedInSession = 0

    private var language: String { localization.current.rawValue }

    var body: some View {
        ZStack {
            EditorialPalette.bg.ignoresSafeArea()

            if finished, let session {
                RewardView(
                    kind: testRewardKind(for: session),
                    hp: xpEarnedInSession,
                    stats: testRewardStats(for: session),
                    onDismiss: { dismiss() }
                )
            } else if let q = session?.currentQuestion {
                questionLayout(q)
            } else if startupResolved {
                emptyPoolLayout
            } else {
                ProgressView().tint(EditorialPalette.text)
            }
        }
        .navigationBarHidden(true)
        .hideTabBar()
        .preferredColorScheme(.dark)
        .onAppear(perform: startIfNeeded)
    }

    // MARK: - Empty pool

    /// Shown when today's eligible pool is empty — no flashcards studied
    /// today and nothing due for review. The CTA dismisses back to the
    /// landing screen so the user can choose to head into Learn.
    private var emptyPoolLayout: some View {
        VStack(spacing: 0) {
            HStack {
                CircleGlassButton(systemName: "xmark", iconSize: 14) { dismiss() }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 22) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 56, weight: .ultraLight))
                    .foregroundStyle(EditorialPalette.gold)
                LocText("tests.empty.title")
                    .font(EditorialFont.display(28, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(EditorialPalette.text)
                    .multilineTextAlignment(.center)
                LocText("tests.empty.subtitle")
                    .font(EditorialFont.sans(14, weight: .medium))
                    .foregroundStyle(EditorialPalette.textDim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            Spacer()

            Button { dismiss() } label: {
                LocText("tests.empty.cta")
                    .font(EditorialFont.sans(11, weight: .semibold))
                    .tracking(2.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Capsule().fill(EditorialPalette.gold))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private func questionLayout(_ q: TestQuestion) -> some View {
        VStack(spacing: 0) {
            topBar(for: q)
                .padding(.horizontal, 22)
                .padding(.top, 8)

            progressRail
                .padding(.horizontal, 30)
                .padding(.top, 26)

            EditorialEyebrow(text: promptLabelKey(for: q), tracking: 2.8, size: 10)
                .padding(.top, 28)

            promptView(for: q)
                .padding(.top, 28)

            Spacer(minLength: 16)

            optionsList(for: q)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)

            actionButton(for: q)
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            // Swipe-to-advance once the answer is checked. We only react to
            // mostly-horizontal drags above a comfortable threshold so the
            // gesture doesn't fire on incidental finger movement during a
            // tap. `didSubmit` is the gate that enforces "must answer + Check
            // first" — silent no-op otherwise. `simultaneousGesture` keeps
            // option-row and Check/Continue taps untouched.
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard didSubmit else { return }
                    let horizontal = abs(value.translation.width)
                    let vertical = abs(value.translation.height)
                    if horizontal > 60 && vertical < 80 {
                        Haptics.tap()
                        advance()
                    }
                }
        )
    }

    // MARK: - Top bar

    private func topBar(for q: TestQuestion) -> some View {
        HStack {
            CircleGlassButton(systemName: "xmark", iconSize: 14) { dismiss() }

            Spacer()

            VStack(spacing: 4) {
                EditorialEyebrow(
                    literal: eyebrowText,
                    color: (session?.cycle ?? 1) > 1 ? EditorialPalette.gold : EditorialPalette.goldSoft,
                    tracking: 2.4,
                    size: 9.5
                )
                Text(progressCounter)
                    .font(EditorialFont.mono(12, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(EditorialPalette.text)
            }

            Spacer()

            // Invisible counterweight matching the left X-button so the
            // central VStack stays centred. Cycle info now lives in the
            // eyebrow ("RETRY ×2 · MEANING"), so no badge is needed here.
            Color.clear.frame(width: 38, height: 38)
        }
    }

    /// Top eyebrow text. Swaps to "RETRY ×N · MODE" once the user
    /// crosses into cycle 2 — by far the most prominent way to signal
    /// "you're not on a fresh question, you're cleaning up mistakes."
    private var eyebrowText: String {
        let mode = modeShortLabel
        let c = session?.cycle ?? 1
        if c > 1 {
            return Bundle.loc("test.eyebrow.retry %lld %@", c, mode)
        }
        return Bundle.loc("test.eyebrow %@", mode)
    }

    private var modeShortLabel: String {
        switch mode {
        case .nameToMeaning: return String(localized: "test.mode.short.meaning")
        case .meaningToName: return String(localized: "test.mode.short.name")
        case .audioToArabic: return String(localized: "test.mode.short.listen")
        case .mix:           return String(localized: "test.mode.short.mix")
        }
    }

    private var progressCounter: String {
        guard let session else { return "" }
        // Cycle-local progress. Cycle 1: "01 / 06" of the full pool.
        // Cycle 2+: "01 / 02" of just the retried wrongs — keeps the
        // denominator honest about what's actually left to answer.
        let pos = min(session.currentCycleAnswered + 1, session.currentCycleSize)
        return String(format: "%02d / %02d", pos, session.currentCycleSize)
    }

    // MARK: - Progress rail

    private var progressRail: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(EditorialPalette.textFaint)
                    .frame(height: 1)
                Rectangle()
                    .fill(EditorialPalette.gold)
                    .frame(width: geo.size.width * progressFraction, height: 1)
                    .shadow(color: EditorialPalette.gold.opacity(0.5), radius: 4)
            }
        }
        .frame(height: 1)
    }

    private var progressFraction: CGFloat {
        guard let session, session.currentCycleSize > 0 else { return 0 }
        // Resets to 0 at every cycle bump so the gold rail re-fills from
        // scratch on each retry pass — matches the cycle-local counter.
        return CGFloat(session.currentCycleAnswered) / CGFloat(session.currentCycleSize)
    }

    // MARK: - Prompt

    private func promptLabelKey(for q: TestQuestion) -> String {
        switch q.mode {
        case .nameToMeaning: return "test.prompt.matchMeaning"
        case .meaningToName: return "test.prompt.matchName"
        case .audioToArabic: return "test.prompt.matchSpelling"
        case .mix:           return "test.prompt.match"
        }
    }

    @ViewBuilder
    private func promptView(for q: TestQuestion) -> some View {
        switch q.prompt {
        case .text(let s):
            VStack(spacing: 16) {
                if q.mode == .nameToMeaning, let name = NamesRepository.shared.names.first(where: { $0.number == q.nameNumber }) {
                    Text(name.arabic)
                        .font(EditorialFont.arabic(52, weight: .regular))
                        .foregroundStyle(EditorialPalette.gold)
                        .environment(\.layoutDirection, .rightToLeft)
                        .shadow(color: EditorialPalette.gold.opacity(0.2), radius: 30)
                }
                Text(s)
                    .font(EditorialFont.display(28, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(EditorialPalette.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        case .audio(let file):
            // Tap-to-play only — no autoplay on appear. Audio prompts that
            // play themselves while the user is reading options were
            // disruptive, especially on re-queue.
            Button {
                AudioPlayer.shared.play(file: file)
                Haptics.tap()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(EditorialPalette.gold))
                        .shadow(color: EditorialPalette.gold.opacity(0.4), radius: 24)
                    LocText("test.audio.play")
                        .font(EditorialFont.display(20, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(EditorialPalette.text)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .editorialGlass(cornerRadius: 26)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
        }
    }

    // MARK: - Options

    private func optionsList(for q: TestQuestion) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(q.options.enumerated()), id: \.offset) { idx, option in
                Button {
                    guard !didSubmit else { return }
                    selectedIndex = idx
                    Haptics.selection()
                } label: {
                    optionRow(option: option, idx: idx, correctIndex: q.correctIndex)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func optionRow(option: AnswerOption, idx: Int, correctIndex: Int) -> some View {
        let isSelected = selectedIndex == idx
        let isCorrect = idx == correctIndex
        let letter = String(UnicodeScalar(0x41 + idx)!) // A, B, C, D

        let strokeColor: Color = {
            if didSubmit {
                if isCorrect { return EditorialPalette.gold }
                if isSelected { return Color.red.opacity(0.8) }
            } else if isSelected {
                return EditorialPalette.gold
            }
            return EditorialPalette.glassBorder
        }()

        let textColor: Color = {
            if didSubmit {
                if isCorrect || isSelected { return EditorialPalette.text }
                return EditorialPalette.textDim
            }
            return isSelected ? EditorialPalette.text : EditorialPalette.textDim
        }()

        let letterColor: Color = {
            if didSubmit && isCorrect { return EditorialPalette.gold }
            if isSelected { return EditorialPalette.gold }
            return EditorialPalette.textMute
        }()

        return HStack(spacing: 16) {
            ZStack {
                Circle().strokeBorder(letterColor.opacity(0.8), lineWidth: 1)
                Text(letter)
                    .font(EditorialFont.mono(11, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(letterColor)
            }
            .frame(width: 28, height: 28)

            Group {
                switch option {
                case .text(let s):
                    Text(s)
                        .font(EditorialFont.display(20, weight: .bold))
                        .tracking(-0.3)
                        .lineSpacing(1)
                case .arabic(let s):
                    Text(s)
                        .font(EditorialFont.arabic(28, weight: .regular))
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)

            if didSubmit, isCorrect {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(EditorialPalette.gold)
            } else if didSubmit, isSelected {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.red.opacity(0.9))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .editorialGlass(cornerRadius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(strokeColor, lineWidth: isSelected || (didSubmit && isCorrect) ? 1.4 : 1)
        )
        .shadow(
            color: (didSubmit && isCorrect) || (!didSubmit && isSelected)
                ? EditorialPalette.gold.opacity(0.15) : .clear,
            radius: 30
        )
    }

    // MARK: - Action

    private func actionButton(for q: TestQuestion) -> some View {
        Button {
            if didSubmit {
                advance()
            } else if let idx = selectedIndex {
                submit(optionIndex: idx, question: q)
            }
        } label: {
            Text(didSubmit ? "test.continue" : "test.check", bundle: .localized)
                .font(EditorialFont.sans(11, weight: .semibold))
                .tracking(2.4)
                .textCase(.uppercase)
                .foregroundStyle(canAct ? Color.black : EditorialPalette.goldSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    Capsule().fill(canAct ? EditorialPalette.gold : EditorialPalette.gold.opacity(0.18))
                )
                .overlay(
                    Capsule().strokeBorder(canAct ? EditorialPalette.gold : EditorialPalette.goldFaint, lineWidth: 1)
                )
                .shadow(color: canAct ? EditorialPalette.gold.opacity(0.35) : .clear, radius: 30)
        }
        .buttonStyle(.plain)
        .disabled(!canAct)
        .opacity(canAct ? 1 : 0.6)
    }

    private var canAct: Bool { didSubmit || selectedIndex != nil }

    // MARK: - Session lifecycle

    private func startIfNeeded() {
        guard !startupResolved else { return }
        let allNames = NamesRepository.shared.names
        let eligible = TodayPoolFactory.eligibleToday(
            progresses: progresses,
            names: allNames
        )
        startupResolved = true
        guard !eligible.isEmpty else { return }
        session = TestSession(
            mode: mode,
            totalQuestions: questionCount,
            language: language,
            eligible: eligible,
            distractorPool: allNames
        )
    }

    private func submit(optionIndex: Int, question: TestQuestion) {
        // Mark the answer & persist mastery, but DON'T touch the session
        // queue — leaving `currentQuestion` pointed at the just-answered
        // question is what lets the result UI (checkmark / red X) overlay
        // on the right options. The queue advance happens in `advance()`,
        // i.e. when the user taps Continue.
        let correct = optionIndex == question.correctIndex
        didSubmit = true
        if correct { Haptics.success() } else { Haptics.error() }

        let progress = context.progress(for: question.nameNumber)
        let outcome = ProgressEngine.recordAnswer(progress, correct: correct)
        if outcome.becameConfirmedToday {
            namesConfirmedThisSession += 1
            // Milestone payout — celebrating the "3 in a row" graduation.
            // Per-name, fires every time a name re-confirms after lapses.
            XPService.award(amount: XPCalculator.nameConfirmedBonus, source: .nameConfirmed, in: context)
            xpEarnedInSession += XPCalculator.nameConfirmedBonus
        }
        if outcome.becameMastered {
            namesMasteredThisSession += 1
            // Career-tier payout — passed the 30-day final review.
            XPService.award(amount: XPCalculator.nameMasteredBonus, source: .nameMastered, in: context)
            xpEarnedInSession += XPCalculator.nameMasteredBonus
        }
        try? context.save()
    }

    private func advance() {
        // Reachable only via the Continue tap, which is only enabled when
        // `didSubmit == true` — and `didSubmit` can only flip true through
        // `submit(...)`, which requires `selectedIndex != nil`. So the
        // selectedIndex guard is just defensive book-keeping.
        guard var s = session, let idx = selectedIndex else { return }
        _ = s.answer(optionIndex: idx)
        session = s
        if s.isComplete {
            recordResult(s)
            finished = true
        } else {
            selectedIndex = nil
            didSubmit = false
        }
    }

    private func recordResult(_ s: TestSession) {
        let xp = XPCalculator.testXP(firstCycleCorrect: s.firstCycleCorrect, totalQuestions: s.totalQuestions)
        let attempt = TestAttempt(
            date: Date(),
            testType: mode.rawValue,
            firstCycleCorrect: s.firstCycleCorrect,
            totalQuestions: s.totalQuestions,
            totalCycles: s.cycle,
            xpEarned: xp,
            namesConfirmed: namesConfirmedThisSession,
            namesMastered: namesMasteredThisSession
        )
        context.insert(attempt)
        XPService.award(amount: xp, source: .test, in: context)
        xpEarnedInSession += xp

        // Mark that the user just finished a test round. Idempotent — only
        // the FIRST call actually flips the flag, so Home will present the
        // Rate-us overlay the next time it renders.
        RateUsService.markFirstRoundComplete()

        scheduleCooldownNotification()
    }

    /// Threshold for the "passed" vs "low" reward variant. 60% first-try
    /// accuracy mirrors the design's verdict cutoff and matches the
    /// "≥60% → full XP" payout rule the info sheet explains.
    private func testRewardKind(for s: TestSession) -> RewardKind {
        let ratio = Double(s.firstCycleCorrect) / Double(max(1, s.totalQuestions))
        return ratio >= 0.6 ? .testPassed : .testLow
    }

    /// Three stats on the test reward: how many landed on first try, the
    /// final tally after all retry cycles (always N/N — wrong answers
    /// re-queue until cleared), and the headline accuracy %.
    private func testRewardStats(for s: TestSession) -> [RewardStat] {
        let total = s.totalQuestions
        let firstTry = s.firstCycleCorrect
        let pct = Int((Double(firstTry) / Double(max(1, total)) * 100).rounded())
        return [
            RewardStat(labelKey: "reward.stat.firstTry", value: "\(firstTry) / \(total)"),
            RewardStat(labelKey: "reward.stat.final", value: "\(total) / \(total)"),
            RewardStat(labelKey: "reward.stat.accuracy", value: "\(pct)%", highlight: true),
        ]
    }

    /// After saving the new TestAttempt, queue a local push for the moment
    /// the inter-round cooldown expires. NotificationsService internally
    /// no-ops when the master toggle is off, so we always call — easier
    /// to reason about than gating here.
    private func scheduleCooldownNotification() {
        try? context.save()  // make sure the just-inserted attempt is counted

        // If this test cleared today's pool (everyone hit Confirmed), there
        // will be nothing waiting when the timer expires — don't lie to
        // the user with a "next round ready" push. Also wipe any pending
        // request from previous rounds so the slate is clean.
        let allNames = NamesRepository.shared.names
        let eligibleAfter = TodayPoolFactory.eligibleToday(progresses: progresses, names: allNames).count
        guard eligibleAfter > 0 else {
            NotificationsService.cancelAll()
            return
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let predicate = #Predicate<TestAttempt> { $0.date >= today }
        let descriptor = FetchDescriptor<TestAttempt>(predicate: predicate)
        let roundsDone = (try? context.fetchCount(descriptor)) ?? 1

        let cooldown = CooldownPolicy.cooldown(after: roundsDone)
        guard cooldown > 0 else { return }

        NotificationsService.scheduleCooldownEnd(
            at: Date.now.addingTimeInterval(cooldown),
            nextRoundNumber: roundsDone + 1
        )
    }
}
