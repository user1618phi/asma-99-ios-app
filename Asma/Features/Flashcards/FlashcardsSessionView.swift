import SwiftUI
import SwiftData

struct FlashcardsSessionView: View {
    /// Two ways the same flashcard UI can be reached:
    /// - `.todaysPool` (default) — the daily learning loop. Pulls the N
    ///   lowest-mastery names (capped by `flashcardCount`), and each
    ///   `Know`/`Don't know` advances the spaced-repetition state via
    ///   `ProgressEngine.markStudied`.
    /// - `.freePractice` — bonus "browse all 99" mode unlocked once the
    ///   daily goal is hit. Shuffles every name and writes nothing back
    ///   (no markStudied, no XP, no SwiftData save) so it can't pollute
    ///   the spaced schedule or be used to grind XP.
    enum Mode { case todaysPool, freePractice }
    var mode: Mode = .todaysPool

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalizationManager.self) private var localization
    @Query private var progress: [NameProgress]
    @AppStorage(AppSettingsKey.flashcardCount) private var flashcardCount = AppSettingsKey.flashcardDefault

    @State private var queue: [AsmaName] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var seenInSession = 0
    @State private var knownInSession = 0
    /// Cumulative HP earned in this session — drives the RewardView
    /// number at the end. Bumped on every XPService.award call below.
    @State private var xpEarnedInSession = 0
    /// Wall-clock start of this session — converted to mm:ss for the
    /// "Time" stat on the reward screen.
    @State private var sessionStartedAt = Date()

    private var language: String { localization.current.rawValue }
    private var total: Int { max(queue.count, 1) }
    private var currentName: AsmaName? { queue[safe: index] }

    var body: some View {
        ZStack {
            EditorialPalette.bg.ignoresSafeArea()

            if let card = currentName {
                sessionLayout(card)
            } else if queue.isEmpty {
                ProgressView().tint(EditorialPalette.text)
            } else if mode == .todaysPool {
                // Daily goal hit → editorial reward screen with the live
                // HP total earned during this session.
                RewardView(
                    kind: .flashcard,
                    hp: xpEarnedInSession,
                    stats: flashcardRewardStats,
                    onDismiss: { dismiss() }
                )
            } else {
                // Free Practice has no goal to reward — keep the calm
                // "session complete" finisher.
                finishedView
            }
        }
        .navigationBarHidden(true)
        .hideTabBar()
        .preferredColorScheme(.dark)
        .onAppear {
            sessionStartedAt = Date()
            buildQueue()
        }
    }

    /// Two stats on the flashcard reward: cards reviewed in this session,
    /// and elapsed wall-clock time as `mm:ss`.
    private var flashcardRewardStats: [RewardStat] {
        let elapsed = Int(Date().timeIntervalSince(sessionStartedAt))
        let mins = elapsed / 60
        let secs = elapsed % 60
        return [
            RewardStat(labelKey: "reward.stat.reviewed", value: "\(seenInSession)"),
            RewardStat(labelKey: "reward.stat.time", value: String(format: "%d:%02d", mins, secs))
        ]
    }

    // MARK: - Layout

    @ViewBuilder
    private func sessionLayout(_ card: AsmaName) -> some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 22)
                .padding(.top, 8)

            progressBar
                .padding(.horizontal, 28)
                .padding(.top, 28)

            cardView(for: card)
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 28)
                .frame(maxHeight: .infinity)

            actionRow(for: card)
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
        }
    }

    private var topBar: some View {
        HStack {
            CircleGlassButton(systemName: "arrow.left", action: { dismiss() })

            Spacer()

            LocText("flashcards.topTitle")
                .font(EditorialFont.display(17, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(EditorialPalette.text)

            Spacer()

            AmbientSoundButton()
        }
    }

    private var progressBar: some View {
        HStack(spacing: 14) {
            Text(String(format: "%02d / %02d", min(index + 1, total), total))
                .font(EditorialFont.mono(11, weight: .medium))
                .tracking(1)
                .foregroundStyle(EditorialPalette.text)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(EditorialPalette.textFaint)
                        .frame(height: 2)
                    Capsule()
                        .fill(EditorialPalette.gold)
                        .frame(width: geo.size.width * progressFraction, height: 2)
                        .shadow(color: EditorialPalette.gold.opacity(0.5), radius: 4)
                }
            }
            .frame(height: 2)
        }
    }

    private var progressFraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(index) / CGFloat(total)
    }

    private func cardView(for card: AsmaName) -> some View {
        VStack(spacing: 0) {
            EditorialEyebrow(literal: Bundle.loc("flashcards.eyebrow.position %lld", card.number), tracking: 2.8, size: 9.5, weight: .medium)
                .padding(.top, 60)

            Spacer().frame(height: 22)

            Text(card.arabic)
                .font(EditorialFont.arabic(44, weight: .regular))
                .foregroundStyle(EditorialPalette.gold)
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .rightToLeft)
                .shadow(color: EditorialPalette.gold.opacity(0.25), radius: 30)

            Spacer().frame(height: 22)

            Text(card.transliteration)
                .font(EditorialFont.display(28, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(EditorialPalette.text)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer().frame(height: 18)

            audioButton(for: card)

            Spacer(minLength: 16)

            if revealed {
                revealedContent(for: card)
                Spacer().frame(height: 40)
            } else {
                revealButton(for: card)
                Spacer().frame(height: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .editorialGlassDeep(cornerRadius: 32)
    }

    @ViewBuilder
    private func revealedContent(for card: AsmaName) -> some View {
        let t = card.translation(for: language)
        VStack(spacing: 0) {
            Rectangle()
                .fill(EditorialPalette.goldFaint)
                .frame(width: 32, height: 1)
                .padding(.top, 24)

            Text(t.translation)
                .font(EditorialFont.display(22, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(EditorialPalette.gold)
                .multilineTextAlignment(.center)
                .padding(.top, 22)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    /// Quiet pill that plays the name's audio on demand. Decoupled from
    /// the reveal action so the user can listen as many times as they
    /// want without flipping the card, or read the meaning silently —
    /// hearing the name is an opt-in gesture, not a side effect.
    private func audioButton(for card: AsmaName) -> some View {
        Button {
            AudioPlayer.shared.play(file: card.audio)
            Haptics.tap()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 13, weight: .regular))
                LocText("flashcards.tapToHear")
                    .font(EditorialFont.sans(13, weight: .medium))
            }
            .foregroundStyle(EditorialPalette.textDim)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func revealButton(for card: AsmaName) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) { revealed = true }
            Haptics.tap()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "eye")
                    .font(.system(size: 16, weight: .regular))
                LocText("flashcards.reveal")
                    .font(EditorialFont.display(16, weight: .bold))
                    .tracking(-0.2)
            }
            .foregroundStyle(EditorialPalette.gold)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(
                Capsule().fill(EditorialPalette.glassBg)
            )
            .background(
                Capsule().fill(.ultraThinMaterial).opacity(0.4)
            )
            .overlay(
                Capsule().strokeBorder(EditorialPalette.goldFaint, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func actionRow(for card: AsmaName) -> some View {
        HStack(spacing: 10) {
            Button {
                guard revealed else { return }
                advance(card: card, known: false)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .regular))
                    LocText("flashcards.dontKnow")
                        .font(EditorialFont.display(16, weight: .bold))
                        .tracking(-0.2)
                }
                .foregroundStyle(revealed ? EditorialPalette.gold : EditorialPalette.textMute)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Capsule().fill(EditorialPalette.glassBg))
                .background(Capsule().fill(.ultraThinMaterial).opacity(0.35))
                .overlay(Capsule().strokeBorder(EditorialPalette.glassBorder, lineWidth: 1))
                .opacity(revealed ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!revealed)

            Button {
                guard revealed else { return }
                advance(card: card, known: true)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .bold))
                    LocText("flashcards.know")
                        .font(EditorialFont.display(16, weight: .bold))
                        .tracking(-0.2)
                }
                .foregroundStyle(revealed ? Color.black : EditorialPalette.goldSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    Capsule()
                        .fill(revealed ? EditorialPalette.gold : EditorialPalette.gold.opacity(0.18))
                )
                .overlay(
                    Capsule().strokeBorder(revealed ? EditorialPalette.gold : EditorialPalette.goldFaint, lineWidth: 1)
                )
                .shadow(color: revealed ? EditorialPalette.gold.opacity(0.4) : .clear, radius: 30)
                .opacity(revealed ? 1 : 0.55)
            }
            .buttonStyle(.plain)
            .disabled(!revealed)
        }
    }

    // MARK: - Finished

    private var finishedView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(EditorialPalette.gold)
            LocText("flashcards.complete.title")
                .font(EditorialFont.display(28, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(EditorialPalette.text)
            Text(verbatim: Bundle.loc("flashcards.complete.subtitle %lld %lld", knownInSession, seenInSession))
                .font(EditorialFont.sans(14, weight: .medium))
                .foregroundStyle(EditorialPalette.textDim)
            Spacer()
            Button { dismiss() } label: {
                LocText("flashcards.complete.continue")
                    .font(EditorialFont.sans(11, weight: .semibold))
                    .tracking(2.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Capsule().fill(EditorialPalette.gold))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Logic

    private func buildQueue() {
        guard queue.isEmpty else { return }
        let all = NamesRepository.shared.names
        switch mode {
        case .freePractice:
            // Bonus browsing — random walk across the full ninety-nine,
            // no daily cap. Order shuffles each session for variety.
            queue = all.shuffled()
        case .todaysPool:
            let progressMap = Dictionary(uniqueKeysWithValues: progress.map { ($0.number, $0) })
            let scored: [(AsmaName, Int)] = all.map { name in
                let mastery = progressMap[name.number]?.masteryLevel ?? 0
                return (name, mastery)
            }
            let sorted = scored.sorted { $0.1 < $1.1 }.map(\.0)
            queue = Array(sorted.prefix(flashcardCount))
        }
    }

    private func advance(card: AsmaName, known: Bool) {
        if mode == .freePractice {
            // Pure browsing — no markStudied, no XP, no SwiftData write.
            // The whole point of Free Practice is that it cannot inflate
            // daily progress or pollute the spaced-repetition state.
            if known {
                knownInSession += 1
                Haptics.success()
            } else {
                Haptics.warning()
            }
            seenInSession += 1
            withAnimation(.easeOut(duration: 0.25)) {
                revealed = false
                index += 1
            }
            return
        }

        // Flashcards are *preparation*, not testing — they mark the name as
        // studied today (which makes it eligible for the test pool) but do
        // not move mastery. Mastery only changes through `ProgressEngine`
        // when the user actually answers a test question.
        let p = context.progress(for: card.number)
        ProgressEngine.markStudied(p)
        if known {
            knownInSession += 1
            XPService.award(amount: XPCalculator.flashcardBase, source: .flashcardKnown, in: context)
            xpEarnedInSession += XPCalculator.flashcardBase
            Haptics.success()
        } else {
            Haptics.warning()
        }
        seenInSession += 1
        try? context.save()
        awardDailyGoalIfHitNow()
        withAnimation(.easeOut(duration: 0.25)) {
            revealed = false
            index += 1
        }
    }

    /// Pays out the once-per-day "you hit your daily goal" XP bonus the
    /// instant `studiedToday` reaches `flashcardCount`. Idempotent — a
    /// quick XPEvent lookup makes sure we don't pay twice in the same
    /// day (re-entering the session, closing the app, etc.). Only the
    /// `.todaysPool` mode reaches here; `.freePractice` returns early.
    private func awardDailyGoalIfHitNow() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let studied = progress.filter {
            if let last = $0.lastStudiedAt {
                return cal.startOfDay(for: last) == today
            }
            return false
        }.count
        guard studied >= flashcardCount else { return }

        let goalSource = XPSource.dailyGoal.rawValue
        let predicate = #Predicate<XPEvent> {
            $0.date >= today && $0.sourceRaw == goalSource
        }
        let descriptor = FetchDescriptor<XPEvent>(predicate: predicate)
        let alreadyPaid = (try? context.fetchCount(descriptor)) ?? 0
        guard alreadyPaid == 0 else { return }

        XPService.award(amount: XPCalculator.dailyGoalBonus, source: .dailyGoal, in: context)
        xpEarnedInSession += XPCalculator.dailyGoalBonus
        Haptics.success()
    }
}

// MARK: - Reusable circular glass icon button

struct CircleGlassButton: View {
    let systemName: String
    var size: CGFloat = 38
    var iconSize: CGFloat = 15
    var tint: Color = EditorialPalette.text
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(EditorialPalette.glassBg))
                .background(Circle().fill(.ultraThinMaterial).opacity(0.4))
                .overlay(Circle().strokeBorder(EditorialPalette.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
