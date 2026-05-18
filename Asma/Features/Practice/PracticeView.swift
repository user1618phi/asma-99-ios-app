import SwiftUI
import SwiftData

struct PracticeView: View {
    let name: AsmaName

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scorer = SpeechScorer()
    @State private var lastScore: PronunciationScore?
    @State private var isWorking = false
    @State private var errorMessage: String?
    /// Reward screen presented as a full-screen cover the moment a
    /// pronunciation attempt produces a valid score. `nil` while
    /// recording / before the first attempt.
    @State private var pendingReward: PendingReward?

    /// Captures everything the RewardView needs in one shot — the kind
    /// (passed vs low), the actual HP earned, and the three score stats.
    private struct PendingReward: Identifiable {
        let id = UUID()
        let kind: RewardKind
        let hp: Int
        let stats: [RewardStat]
    }

    /// Ring buffer of recent mic amplitudes (oldest left → newest right).
    /// Populated by a `.task` loop while `scorer.isRecording`.
    @State private var samples: [CGFloat] = Array(repeating: 0, count: 56)

    /// Wall-clock at which the current recording started; nil while idle.
    @State private var recordingStartedAt: Date?

    /// Hard cap on a single recording, matched against `SpeechScorer.record(maxSeconds:)`.
    private let maxRecordingSeconds: TimeInterval = 5

    var body: some View {
        ZStack {
            EditorialPalette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 22)
                    .padding(.top, 8)

                Spacer().frame(height: 50)

                eyebrowRow

                Spacer().frame(height: 60)

                heroName

                Spacer().frame(height: 36)

                statusPill

                Spacer().frame(height: 28)

                if let score = lastScore {
                    resultView(score: score)
                } else {
                    waveform
                        .padding(.horizontal, 30)

                    Spacer().frame(height: 18)

                    timeReadout
                        .padding(.horizontal, 30)

                    Spacer().frame(height: 20)

                    guidance
                        .padding(.horizontal, 40)
                }

                Spacer(minLength: 0)

                micButton
                    .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
        .hideTabBar()
        .preferredColorScheme(.dark)
        .onAppear { AmbientSoundPlayer.shared.pause(reason: .practice) }
        .onDisappear { AmbientSoundPlayer.shared.resume(reason: .practice) }
        .task(id: scorer.isRecording) {
            // Reset on every recording state change so the line starts clean.
            samples = Array(repeating: 0, count: samples.count)
            if scorer.isRecording {
                recordingStartedAt = Date()
            } else {
                recordingStartedAt = nil
            }
            guard scorer.isRecording else { return }
            // ~25 fps polling — appends current smoothed level, drops oldest.
            // Loop ends when the task is cancelled (recording stops or view exits).
            while !Task.isCancelled && scorer.isRecording {
                try? await Task.sleep(nanoseconds: 40_000_000)
                var next = samples
                next.removeFirst()
                next.append(CGFloat(scorer.audioLevel))
                samples = next
            }
        }
        .alert(
            Text(verbatim: Bundle.loc("practice.error.title")),
            isPresented: .init(get: { errorMessage != nil }, set: { _ in errorMessage = nil })
        ) {
            Button(role: .cancel) {} label: {
                Text(verbatim: Bundle.loc("common.ok"))
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .fullScreenCover(item: $pendingReward) { reward in
            RewardView(
                kind: reward.kind,
                hp: reward.hp,
                stats: reward.stats,
                onDismiss: { pendingReward = nil }
            )
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            EditorialEyebrow(text: "practice.eyebrow", tracking: 2.8)
            Spacer()
            CircleGlassButton(systemName: "xmark", iconSize: 14) { dismiss() }
        }
    }

    private var eyebrowRow: some View {
        EditorialEyebrow(
            literal: Bundle.loc("practice.eyebrow.position %lld", name.number),
            color: EditorialPalette.textMute,
            tracking: 2.8,
            size: 9.5
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hero

    private var heroName: some View {
        VStack(spacing: 22) {
            Text(name.arabic)
                .font(EditorialFont.arabic(44, weight: .regular))
                .foregroundStyle(EditorialPalette.gold)
                .environment(\.layoutDirection, .rightToLeft)
                .shadow(color: EditorialPalette.gold.opacity(0.28), radius: 30)
            Text(name.transliteration)
                .font(EditorialFont.display(28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(EditorialPalette.text)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Status pill

    private var statusPill: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(EditorialPalette.gold)
                .frame(width: 6, height: 6)
                .shadow(color: EditorialPalette.gold.opacity(0.8), radius: 6)
                .opacity(scorer.isRecording ? 1 : 0.3)
            EditorialEyebrow(
                text: scorer.isRecording ? "practice.status.listening" : "practice.status.tapMic",
                color: EditorialPalette.gold,
                tracking: 2.8,
                size: 9.5
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Capsule().fill(EditorialPalette.glassBg))
        .background(Capsule().fill(.ultraThinMaterial).opacity(0.4))
        .overlay(Capsule().strokeBorder(EditorialPalette.glassBorder, lineWidth: 1))
    }

    // MARK: - Waveform

    /// Live waveform:
    ///   • idle  → single 1pt faint line across the width (no bars)
    ///   • recording → scrolling gold bars, mirrored top-and-bottom around the
    ///     centre, height driven by the live RMS ring buffer (newest on the right)
    private var waveform: some View {
        ZStack {
            // Idle baseline — a quiet hairline. Fades out as bars take over.
            Rectangle()
                .fill(EditorialPalette.textFaint)
                .frame(height: 1)
                .opacity(scorer.isRecording ? 0 : 1)

            // Recording bars — mirrored around the centre (Voice-Memos style).
            // Height = sample · maxHeight, clamped to a 2pt minimum so the
            // waveform reads as a continuous strip even during silence.
            HStack(alignment: .center, spacing: 3) {
                ForEach(samples.indices, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(EditorialPalette.gold)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(2, samples[i] * 72))
                        .shadow(color: EditorialPalette.gold.opacity(0.35), radius: 3)
                        .animation(.easeOut(duration: 0.08), value: samples[i])
                }
            }
            .frame(height: 84)
            .opacity(scorer.isRecording ? 1 : 0)
        }
        .frame(height: 84)
        .mask(
            // Soft edges so the leftmost (oldest) sample fades out as it
            // scrolls off — gives the scroll the right sense of motion.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.08),
                    .init(color: .black, location: 0.92),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .animation(.easeInOut(duration: 0.2), value: scorer.isRecording)
    }

    // MARK: - Time + guidance

    private var timeReadout: some View {
        // Left = real elapsed since recording started (re-ticked every 100ms
        // via TimelineView); right = the recording cap. Idle shows 0:00.
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            HStack {
                Text(formatTime(elapsed(at: ctx.date)))
                    .font(EditorialFont.mono(11, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(scorer.isRecording ? EditorialPalette.gold : EditorialPalette.textMute)
                Spacer()
                Text(formatTime(maxRecordingSeconds))
                    .font(EditorialFont.mono(11, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(EditorialPalette.textMute)
            }
        }
    }

    private func elapsed(at now: Date) -> TimeInterval {
        guard let start = recordingStartedAt else { return 0 }
        return max(0, min(maxRecordingSeconds, now.timeIntervalSince(start)))
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var guidance: some View {
        VStack(spacing: 16) {
            Rectangle()
                .fill(EditorialPalette.goldFaint)
                .frame(width: 28, height: 1)
            if !scorer.partialTranscription.isEmpty {
                Text("\u{201C}\(scorer.partialTranscription)\u{201D}")
                    .font(EditorialFont.display(15, weight: .medium))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(EditorialPalette.textDim)
            } else {
                LocText("practice.guidance")
                    .font(EditorialFont.display(15, weight: .medium))
                    .tracking(-0.1)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(EditorialPalette.textDim)
            }
        }
    }

    // MARK: - Mic button

    private var micButton: some View {
        VStack(spacing: 14) {
            Button {
                Task { await beginRecording() }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(EditorialPalette.goldFaint, lineWidth: 1)
                        .frame(width: 128, height: 128)
                        .opacity(0.35)
                    Circle()
                        .strokeBorder(EditorialPalette.goldFaint, lineWidth: 1)
                        .frame(width: 106, height: 106)
                        .opacity(0.7)
                    Circle()
                        .strokeBorder(EditorialPalette.goldFaint, lineWidth: 1)
                        .background(Circle().fill(EditorialPalette.glassBgDeep))
                        .background(Circle().fill(.ultraThinMaterial).opacity(0.55))
                        .frame(width: 88, height: 88)
                        .shadow(color: EditorialPalette.gold.opacity(0.22), radius: 40)
                    Image(systemName: scorer.isRecording ? "stop.fill" : "mic")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(EditorialPalette.gold)
                }
            }
            .buttonStyle(.plain)
            .disabled(isWorking && !scorer.isRecording)

            EditorialEyebrow(
                text: scorer.isRecording ? "practice.mic.tapStop" : "practice.mic.tapStart",
                color: EditorialPalette.textMute,
                tracking: 2.4,
                size: 9.5
            )
        }
    }

    // MARK: - Result (after recording)

    private func resultView(score: PronunciationScore) -> some View {
        VStack(spacing: 16) {
            Text(percent(score.overall))
                .font(EditorialFont.display(64, weight: .heavy))
                .tracking(-2)
                .monospacedDigit()
                .foregroundStyle(EditorialPalette.gold)
                .shadow(color: EditorialPalette.gold.opacity(0.25), radius: 30)

            EditorialEyebrow(text: verdictKey(for: score.overall), tracking: 2.8)

            // Clarity column is hidden: SFSpeechRecognizer never reports
            // confidence for ar-SA, so it'd always read 0% and only
            // confuse users. Stays in PronunciationScore for future
            // engines (e.g. whisper) where it'd be meaningful again.
            HStack(spacing: 0) {
                statColumn(labelKey: "practice.stat.accuracy", value: percent(score.accuracy))
                Rectangle().fill(EditorialPalette.textFaint).frame(width: 1, height: 38)
                statColumn(labelKey: "practice.stat.complete", value: percent(score.completeness))
            }
            .padding(.top, 6)
            .padding(.horizontal, 18)

            if !score.transcription.isEmpty {
                VStack(spacing: 6) {
                    // What the recogniser heard, with per-letter colour:
                    // matched letters stay neutral, swaps/extras flash coral.
                    Text(spokenAttributed(score.diff))
                        .font(EditorialFont.arabic(18, weight: .regular))
                        .environment(\.layoutDirection, .rightToLeft)
                        .multilineTextAlignment(.center)
                    // Show the target line only when something actually
                    // differs — otherwise it's just visual noise.
                    if score.diff.contains(where: { $0.op != .match }) {
                        HStack(spacing: 8) {
                            EditorialEyebrow(
                                text: "practice.diff.target",
                                color: EditorialPalette.textMute,
                                tracking: 1.8, size: 9
                            )
                            Text(targetAttributed(score.diff))
                                .font(EditorialFont.arabic(14, weight: .regular))
                                .environment(\.layoutDirection, .rightToLeft)
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 24)
            }

            Button {
                lastScore = nil
            } label: {
                LocText("practice.tryAgain")
                    .font(EditorialFont.sans(10.5, weight: .semibold))
                    .tracking(2.4)
                    .textCase(.uppercase)
                    .foregroundStyle(EditorialPalette.gold)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(EditorialPalette.glassBg))
                    .overlay(Capsule().strokeBorder(EditorialPalette.goldFaint, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    private func statColumn(labelKey: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(EditorialFont.display(18, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(EditorialPalette.text)
            EditorialEyebrow(text: labelKey, color: EditorialPalette.textMute, tracking: 1.6, size: 9)
        }
        .frame(maxWidth: .infinity)
    }

    private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    /// What the user actually said. Matched letters in normal text colour,
    /// substituted letters in warn coral, extra letters (recognizer heard
    /// something not in the name) in a fainter warn so they read as "spill".
    private func spokenAttributed(_ steps: [DiffStep]) -> AttributedString {
        var out = AttributedString("\u{201C}")
        out.foregroundColor = EditorialPalette.textDim
        for step in steps {
            switch step.op {
            case .match:
                if let s = step.actual { out += colored(String(s), EditorialPalette.text) }
            case .sub:
                if let s = step.actual { out += colored(String(s), EditorialPalette.warn) }
            case .insert:
                if let s = step.actual { out += colored(String(s), EditorialPalette.warnSoft) }
            case .delete:
                continue  // missing letters belong on the target line, not here
            }
        }
        var close = AttributedString("\u{201D}")
        close.foregroundColor = EditorialPalette.textDim
        out += close
        return out
    }

    /// The target name, with the letters the user *should* have said in
    /// coral wherever they missed or substituted. Matched letters stay
    /// muted so the eye lands on the corrections, not the whole word.
    private func targetAttributed(_ steps: [DiffStep]) -> AttributedString {
        var out = AttributedString()
        for step in steps {
            switch step.op {
            case .match:
                if let s = step.expected { out += colored(String(s), EditorialPalette.textMute) }
            case .sub, .delete:
                if let s = step.expected { out += colored(String(s), EditorialPalette.warn) }
            case .insert:
                continue  // nothing in the target to point at
            }
        }
        return out
    }

    private func colored(_ s: String, _ color: Color) -> AttributedString {
        var a = AttributedString(s)
        a.foregroundColor = color
        return a
    }

    private func verdictKey(for overall: Double) -> String {
        switch overall {
        case ..<0.35:    return "practice.verdict.tryAgain"
        case 0.35..<0.55: return "practice.verdict.getting"
        case 0.55..<0.8:  return "practice.verdict.good"
        default:          return "practice.verdict.excellent"
        }
    }

    private func beginRecording() async {
        if scorer.isRecording {
            scorer.cancel()
            return
        }
        isWorking = true
        defer { isWorking = false }
        if scorer.authorization != .granted {
            let granted = await scorer.requestAuthorization()
            if !granted {
                errorMessage = String(localized: "practice.error.permissionDenied")
                return
            }
        }
        do {
            let score = try await scorer.record(expectedArabic: name.arabic)
            // Recognizer returned nothing — treat it as "didn't catch that"
            // rather than a 0% result. Don't burn mastery/XP and don't show
            // a misleading score; just prompt the user to try again.
            // Split the two failure modes so the advice is actionable:
            //  • voice detected but no text → recognizer couldn't parse the
            //    Arabic (model gap, accent, speed)
            //  • no voice at all → user was silent or too far from the mic
            if !score.didHearSpeech {
                errorMessage = score.didDetectVoice
                    ? String(localized: "practice.error.notRecognized")
                    : String(localized: "practice.error.notHeard")
                Haptics.warning()
                return
            }
            lastScore = score
            let p = context.progress(for: name.number)
            if score.overall > p.pronunciationBestScore {
                p.pronunciationBestScore = score.overall
            }
            p.lastReviewedAt = Date()
            // A solid recitation bumps mastery the same way a correct
            // flashcard / test answer does. Threshold matches the "good"
            // verdict band so the visible feedback and the progress signal stay in sync.
            if score.overall >= 0.55 {
                p.masteryLevel = min(5, p.masteryLevel + 1)
            }
            try? context.save()
            let awarded = XPCalculator.pronunciationXP(score: score.overall)
            if awarded > 0 {
                XPService.award(amount: awarded, source: .pronunciation, in: context)
                Haptics.success()
            } else {
                Haptics.warning()
            }
            // Reveal the reward card after a beat so the user catches the
            // score number animating in first; then the cover takes over.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                pendingReward = buildPracticeReward(score: score, hp: awarded)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Builds the reward payload for a finished pronunciation attempt.
    /// 0.7 split mirrors the existing `pronunciationBestScore >= 0.7`
    /// achievement threshold — passing it shows the gold variant, below
    /// it the silver "getting there" variant. Stats use the three
    /// sub-scores the recogniser already produces.
    private func buildPracticeReward(score: PronunciationScore, hp: Int) -> PendingReward {
        let pct = { (v: Double) in "\(Int((v * 100).rounded()))%" }
        let kind: RewardKind = score.overall >= 0.7 ? .practicePassed : .practiceLow
        return PendingReward(
            kind: kind,
            hp: hp,
            stats: [
                RewardStat(labelKey: "reward.stat.accuracy", value: pct(score.accuracy)),
                RewardStat(labelKey: "reward.stat.score", value: pct(score.overall), highlight: true),
                RewardStat(labelKey: "reward.stat.complete", value: pct(score.completeness)),
            ]
        )
    }
}
