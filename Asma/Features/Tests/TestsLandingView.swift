import SwiftUI
import SwiftData

struct TestsLandingView: View {
    @State private var path = NavigationPath()
    @AppStorage(AppSettingsKey.testQuestionCount) private var testQuestionCount = AppSettingsKey.testDefault
    @Query private var progresses: [NameProgress]
    @Query private var testAttempts: [TestAttempt]

    /// Counts that drive the "Сегодня: N новых · M повторов" eyebrow and
    /// the bottom footer. Recomputed every render via `TodayPoolFactory` —
    /// cheap (linear over 99 rows) and keeps the UI honest about what the
    /// session will actually contain.
    private var todayCounts: (newToday: Int, dueReviews: Int) {
        TodayPoolFactory.todayCounts(progresses: progresses)
    }

    private var poolIsEmpty: Bool {
        let c = todayCounts
        return c.newToday == 0 && c.dueReviews == 0
    }

    private func cooldownRemaining(now: Date) -> TimeInterval {
        CooldownPolicy.remaining(testAttempts: testAttempts, now: now)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                EditorialPalette.bg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 30)

                    EditorialEyebrow(text: "tests.eyebrow")
                        .padding(.horizontal, 30)

                    Spacer().frame(height: 38)

                    LocText("tests.title")
                        .font(EditorialFont.display(76, weight: .heavy))
                        .tracking(-3)
                        .lineSpacing(-10)
                        .foregroundStyle(EditorialPalette.text)
                        .padding(.horizontal, 30)

                    LocText("tests.subtitle")
                        .font(EditorialFont.sans(15, weight: .medium))
                        .tracking(-0.1)
                        .lineSpacing(2)
                        .foregroundStyle(EditorialPalette.textDim)
                        .frame(maxWidth: 280, alignment: .leading)
                        .padding(.top, 12)
                        .padding(.horizontal, 30)

                    todaySummary
                        .padding(.horizontal, 30)
                        .padding(.top, 20)

                    Spacer().frame(height: 22)

                    // Cooldown gate + mode list share a TimelineView so the
                    // countdown text refreshes every 30s and the modes
                    // re-enable themselves automatically the moment the
                    // wait expires.
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        let wait = cooldownRemaining(now: context.date)
                        if wait > 0 {
                            VStack(spacing: 12) {
                                cooldownBanner(remaining: wait)
                                // Side-effect-free quiz over all 99 names.
                                // Only surfaced during the cooldown — the
                                // user explicitly asked for a way to
                                // practise while waiting, with no impact
                                // on HP or the spaced-repetition queue.
                                freeQuizCTA
                            }
                            .padding(.horizontal, 18)
                        } else {
                            modeList
                        }
                    }

                    Spacer(minLength: 0)

                    footerNote
                        .padding(.horizontal, 30)
                        .padding(.bottom, 32)
                }
            }
            .overlay(alignment: .topTrailing) {
                AmbientSoundButton()
                    .padding(.top, 8)
                    .padding(.trailing, 18)
            }
            .navigationBarHidden(true)
            .navigationDestination(for: TestRoute.self) { route in
                switch route {
                case .session(let mode, let count):
                    TestSessionView(mode: mode, questionCount: count)
                case .freeQuizPicker:
                    FreeQuizPickerView { mode in
                        path.append(TestRoute.freeQuiz(mode: mode))
                    }
                case .freeQuiz(let mode):
                    FreeQuizView(mode: mode)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// The four-mode picker shown when the user is free to start a test.
    private var modeList: some View {
        VStack(spacing: 10) {
            ForEach(TestMode.allCases) { mode in
                Button {
                    path.append(TestRoute.session(mode: mode, count: testQuestionCount))
                } label: {
                    modeRow(mode)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
    }

    /// Card that replaces the mode list while the spacing window is open.
    /// Hourglass + countdown + a short explanation of *why* — distributed
    /// practice is the whole point of the wait.
    private func cooldownBanner(remaining: TimeInterval) -> some View {
        let totalMinutes = max(1, Int(ceil(remaining / 60)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        // Three-way pick keeps the copy clean across locales:
        //   "27 min", "1 h", or "1 h 27 min" — never "1 h 0 min".
        let countdown: String = {
            if hours > 0 && minutes > 0 {
                return Bundle.loc("tests.cooldown.countdown.hoursAndMinutes %lld %lld", hours, minutes)
            }
            if hours > 0 {
                return Bundle.loc("tests.cooldown.countdown.hours %lld", hours)
            }
            return Bundle.loc("tests.cooldown.countdown.minutes %lld", minutes)
        }()

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(EditorialPalette.goldFaint, lineWidth: 1)
                        .background(Circle().fill(EditorialPalette.gold.opacity(0.04)))
                        .frame(width: 48, height: 48)
                    Image(systemName: "hourglass")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(EditorialPalette.gold)
                }

                VStack(alignment: .leading, spacing: 3) {
                    EditorialEyebrow(text: "tests.cooldown.eyebrow", size: 9.5, weight: .medium)
                    Text(verbatim: countdown)
                        .font(EditorialFont.display(21, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(EditorialPalette.text)
                }
                Spacer(minLength: 0)
            }

            Rectangle()
                .fill(EditorialPalette.textFaint)
                .frame(height: 1)

            LocText("tests.cooldown.explanation")
                .font(EditorialFont.sans(12.5, weight: .medium))
                .lineSpacing(3)
                .foregroundStyle(EditorialPalette.textDim)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .editorialGlassDeep(cornerRadius: 28)
    }

    /// "While you wait" card under the cooldown banner. Tapping it pushes
    /// `FreeQuizPickerView` — the user then chooses which direction
    /// they want to practise. The whole flow doesn't touch HP, mastery,
    /// or the spaced-repetition schedule. Only shown during cooldown so
    /// it never competes with a real test session.
    private var freeQuizCTA: some View {
        Button {
            path.append(TestRoute.freeQuizPicker)
        } label: {
            HStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(EditorialPalette.goldFaint, lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(EditorialPalette.gold.opacity(0.04))
                        )
                        .frame(width: 48, height: 48)
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(EditorialPalette.gold)
                }

                VStack(alignment: .leading, spacing: 3) {
                    LocText("tests.freeQuiz.cta.title")
                        .font(EditorialFont.display(19, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(EditorialPalette.text)
                    LocText("tests.freeQuiz.cta.subtitle")
                        .font(EditorialFont.sans(12, weight: .medium))
                        .foregroundStyle(EditorialPalette.textDim)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(EditorialPalette.textMute)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .editorialGlass(cornerRadius: 20)
        }
        .buttonStyle(.plain)
    }

    private func modeRow(_ mode: TestMode) -> some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(EditorialPalette.goldFaint, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(EditorialPalette.gold.opacity(0.04))
                    )
                    .frame(width: 48, height: 48)
                Image(systemName: mode.editorialIcon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(EditorialPalette.gold)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: Bundle.loc(mode.titleKey))
                    .font(EditorialFont.display(21, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(EditorialPalette.text)
                Text(verbatim: Bundle.loc(mode.subtitleKey))
                    .font(EditorialFont.sans(12.5, weight: .medium))
                    .foregroundStyle(EditorialPalette.textDim)
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(EditorialPalette.textMute)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .editorialGlass(cornerRadius: 20)
    }

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(EditorialPalette.goldFaint)
                .frame(width: 32, height: 1)
            Text(verbatim: Bundle.loc("tests.footer %lld", testQuestionCount))
                .font(EditorialFont.sans(12, weight: .medium))
                .lineSpacing(3)
                .foregroundStyle(EditorialPalette.textMute)
        }
    }

    /// Editorial eyebrow strip above the mode list. Tells the user, before
    /// they pick a mode, what today's session will actually be drawn from —
    /// makes the "today's pool" concept visible instead of magic.
    @ViewBuilder
    private var todaySummary: some View {
        let c = todayCounts
        HStack(spacing: 10) {
            Rectangle()
                .fill(EditorialPalette.goldFaint)
                .frame(width: 18, height: 1)
            if poolIsEmpty {
                Text(verbatim: Bundle.loc("tests.today.empty"))
                    .font(EditorialFont.sans(11, weight: .semibold))
                    .tracking(2.2)
                    .textCase(.uppercase)
                    .foregroundStyle(EditorialPalette.textMute)
            } else {
                Text(verbatim: Bundle.loc("tests.today.summary %lld %lld", c.newToday, c.dueReviews))
                    .font(EditorialFont.sans(11, weight: .semibold))
                    .tracking(2.2)
                    .textCase(.uppercase)
                    .foregroundStyle(EditorialPalette.gold)
            }
            Spacer(minLength: 0)
        }
    }
}

enum TestRoute: Hashable {
    case session(mode: TestMode, count: Int)
    /// Direction-picker screen for the cooldown free-practice quiz.
    case freeQuizPicker
    /// Actual quiz session for one specific direction.
    case freeQuiz(mode: TestMode)
}

private extension TestMode {
    /// Editorial-style SF Symbols matching the mockup's line-only icon set.
    var editorialIcon: String {
        switch self {
        case .nameToMeaning: return "text.bubble"
        case .meaningToName: return "doc.text"
        case .audioToArabic: return "waveform"
        case .mix:           return "sparkles"
        }
    }
}
