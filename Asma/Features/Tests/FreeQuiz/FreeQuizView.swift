import SwiftUI

/// Free quiz screen — quiet practice during the inter-round cooldown.
/// Visually identical to `TestSessionView` (same option rows, prompt
/// styles, action button) but persists nothing. The user picks a
/// direction (`nameToMeaning` or `meaningToName`) on the previous
/// `FreeQuizPickerView` screen, and the entire session runs in that
/// single mode — no .mix.
struct FreeQuizView: View {
    let mode: TestMode

    @Environment(\.dismiss) private var dismiss
    @Environment(LocalizationManager.self) private var localization

    @State private var session: FreeQuizSession?
    @State private var selectedIndex: Int?
    @State private var didSubmit = false
    @State private var finished = false

    private var language: String { localization.current.rawValue }

    var body: some View {
        ZStack {
            EditorialPalette.bg.ignoresSafeArea()

            if finished, let session {
                completeLayout(correct: session.correctCount, total: session.total)
            } else if let q = session?.currentQuestion {
                questionLayout(q)
            } else {
                ProgressView().tint(EditorialPalette.text)
            }
        }
        .navigationBarHidden(true)
        .hideTabBar()
        .preferredColorScheme(.dark)
        .onAppear(perform: startIfNeeded)
    }

    private func startIfNeeded() {
        guard session == nil else { return }
        session = FreeQuizSession(mode: mode, language: language)
    }

    // MARK: - Question layout

    @ViewBuilder
    private func questionLayout(_ q: TestQuestion) -> some View {
        VStack(spacing: 0) {
            topBar
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

    private var topBar: some View {
        HStack {
            CircleGlassButton(systemName: "xmark", iconSize: 14) { dismiss() }

            Spacer()

            VStack(spacing: 4) {
                EditorialEyebrow(
                    literal: Bundle.loc("tests.freeQuiz.eyebrow"),
                    color: EditorialPalette.goldSoft,
                    tracking: 2.4,
                    size: 9.5
                )
                Text(counterText)
                    .font(EditorialFont.mono(12, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(EditorialPalette.text)
            }

            Spacer()

            // Invisible counterweight to keep the central VStack centred.
            Color.clear.frame(width: 38, height: 38)
        }
    }

    /// Counter text: `correct / asked`. Both zero-padded to 2 digits so
    /// the typography line stays a stable width across the 99-question
    /// run (e.g. "07 / 12" → "99 / 99").
    private var counterText: String {
        let correct = session?.correctCount ?? 0
        let asked = session?.asked ?? 0
        return String(format: "%02d / %02d", correct, asked)
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
        guard let session, session.total > 0 else { return 0 }
        return CGFloat(session.asked) / CGFloat(session.total)
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
                if q.mode == .nameToMeaning,
                   let name = NamesRepository.shared.names.first(where: { $0.number == q.nameNumber }) {
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
        let letter = String(UnicodeScalar(0x41 + idx)!)

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

    // MARK: - Lifecycle

    private func submit(optionIndex: Int, question: TestQuestion) {
        // Side-effect free: just show the result UI. The session's
        // counters tick on `advance()` to keep the "0/0 → 0/1 → 0/2"
        // ordering the user spec'd.
        let correct = optionIndex == question.correctIndex
        didSubmit = true
        if correct { Haptics.success() } else { Haptics.error() }
    }

    private func advance() {
        guard var s = session, let idx = selectedIndex else { return }
        _ = s.answer(optionIndex: idx)
        session = s
        if s.isComplete {
            finished = true
        } else {
            selectedIndex = nil
            didSubmit = false
        }
    }

    // MARK: - Completion

    private func completeLayout(correct: Int, total: Int) -> some View {
        VStack(spacing: 0) {
            HStack {
                CircleGlassButton(systemName: "xmark", iconSize: 14) { dismiss() }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 22) {
                EditorialEyebrow(
                    literal: Bundle.loc("tests.freeQuiz.complete.eyebrow"),
                    color: EditorialPalette.goldSoft,
                    tracking: 2.8,
                    size: 10
                )

                Text(verbatim: String(format: "%02d / %02d", correct, total))
                    .font(EditorialFont.display(84, weight: .heavy))
                    .tracking(-3)
                    .monospacedDigit()
                    .foregroundStyle(EditorialPalette.gold)
                    .shadow(color: EditorialPalette.gold.opacity(0.3), radius: 30)

                LocText("tests.freeQuiz.complete.subtitle")
                    .font(EditorialFont.sans(14, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(EditorialPalette.textDim)
                    .padding(.horizontal, 36)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                LocText("common.done")
                    .font(EditorialFont.sans(11, weight: .semibold))
                    .tracking(2.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Capsule().fill(EditorialPalette.gold))
                    .shadow(color: EditorialPalette.gold.opacity(0.35), radius: 24)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.bottom, 32)
        }
    }
}
