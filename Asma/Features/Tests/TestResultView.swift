import SwiftUI

struct TestResultView: View {
    let session: TestSession
    /// Names that crossed `.studying → .confirmed` in this session — i.e.
    /// the user just hit "3 correct in a row" on them.
    let namesConfirmed: Int
    /// Names that graduated to `.mastered` (passed the 30-day box).
    let namesMastered: Int
    let onContinue: () -> Void

    private var accuracy: Int {
        let pct = Double(session.firstCycleCorrect) / Double(max(session.totalQuestions, 1)) * 100
        return Int(pct.rounded())
    }

    private var xp: Int {
        XPCalculator.testXP(firstCycleCorrect: session.firstCycleCorrect, totalQuestions: session.totalQuestions)
    }

    private var shouldShowMilestones: Bool {
        namesConfirmed > 0 || namesMastered > 0
    }

    var body: some View {
        ZStack {
            EditorialPalette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 30)

                EditorialEyebrow(text: "test.result.eyebrow")
                    .padding(.horizontal, 30)

                Spacer().frame(height: 36)

                LocText("test.result.titleLine1")
                    .font(EditorialFont.display(76, weight: .heavy))
                    .tracking(-3)
                    .foregroundStyle(EditorialPalette.text)
                LocText("test.result.titleLine2")
                    .font(EditorialFont.display(76, weight: .heavy))
                    .tracking(-3)
                    .foregroundStyle(EditorialPalette.gold)
                    .padding(.top, -10)

                Spacer().frame(height: 40)

                statsCard
                    .padding(.horizontal, 18)

                if shouldShowMilestones {
                    milestonesRow
                        .padding(.horizontal, 30)
                        .padding(.top, 22)
                }

                Spacer().frame(height: 28)

                xpRow
                    .padding(.horizontal, 30)

                Spacer(minLength: 0)

                Button(action: onContinue) {
                    LocText("common.continue")
                        .font(EditorialFont.sans(11, weight: .semibold))
                        .tracking(2.4)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Capsule().fill(EditorialPalette.gold))
                        .shadow(color: EditorialPalette.gold.opacity(0.35), radius: 30)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .preferredColorScheme(.dark)
        .navigationBarHidden(true)
    }

    private var statsCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(String(format: "%02d", session.firstCycleCorrect))
                    .font(EditorialFont.display(96, weight: .heavy))
                    .tracking(-5)
                    .monospacedDigit()
                    .foregroundStyle(EditorialPalette.gold)
                    .shadow(color: EditorialPalette.gold.opacity(0.25), radius: 20)
                Text("/ \(String(format: "%02d", session.totalQuestions))")
                    .font(EditorialFont.display(28, weight: .semibold))
                    .tracking(-1)
                    .monospacedDigit()
                    .foregroundStyle(EditorialPalette.textMute)
            }
            .padding(.top, 26)

            EditorialEyebrow(text: "test.result.firstTry")
                .padding(.top, 6)

            Rectangle()
                .fill(EditorialPalette.textFaint)
                .frame(height: 1)
                .padding(.top, 22)
                .padding(.horizontal, 28)

            HStack(spacing: 0) {
                statColumn(titleKey: "test.result.accuracy", value: "\(accuracy)%")
                Rectangle()
                    .fill(EditorialPalette.textFaint)
                    .frame(width: 1, height: 44)
                statColumn(titleKey: "test.result.cycles", value: "\(session.cycle)")
            }
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity)
        .editorialGlassDeep(cornerRadius: 32)
    }

    private func statColumn(titleKey: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(EditorialFont.display(24, weight: .bold))
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundStyle(EditorialPalette.text)
            EditorialEyebrow(text: titleKey, color: EditorialPalette.textMute, tracking: 2, size: 9.5)
        }
        .frame(maxWidth: .infinity)
    }

    /// Milestone summary — only shown when at least one name advanced its
    /// learning state during this session. Keeps the result screen calm
    /// when nothing notable happened (e.g. an early flailing session) and
    /// celebratory when the user is making real progress.
    private var milestonesRow: some View {
        HStack(spacing: 18) {
            if namesConfirmed > 0 {
                milestonePill(
                    icon: "checkmark.seal",
                    key: "test.result.confirmedToday %lld",
                    value: namesConfirmed
                )
            }
            if namesMastered > 0 {
                milestonePill(
                    icon: "sparkles",
                    key: "test.result.masteredToday %lld",
                    value: namesMastered
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func milestonePill(icon: String, key: String, value: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(EditorialPalette.gold)
            Text(verbatim: Bundle.loc(key, value))
                .font(EditorialFont.sans(11, weight: .semibold))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(EditorialPalette.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(EditorialPalette.gold.opacity(0.08))
        )
        .overlay(
            Capsule().strokeBorder(EditorialPalette.goldFaint, lineWidth: 1)
        )
    }

    private var xpRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(EditorialPalette.gold)
            EditorialEyebrow(text: "test.result.earned")
            Spacer()
            Text("+\(xp) XP")
                .font(EditorialFont.mono(16, weight: .medium))
                .tracking(1)
                .foregroundStyle(EditorialPalette.gold)
        }
    }
}
