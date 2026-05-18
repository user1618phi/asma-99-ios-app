import AVFoundation
import Foundation
import Speech

/// One step of the per-letter alignment between the target name and what
/// the recognizer transcribed. Used to render colour-coded feedback.
enum AlignOp: Equatable, Sendable {
    case match            // expected == actual
    case sub              // expected != actual (substitution)
    case insert           // actual letter has no counterpart in expected
    case delete           // expected letter was not spoken
}

struct DiffStep: Equatable, Sendable {
    let op: AlignOp
    let expected: Unicode.Scalar?    // nil for .insert
    let actual: Unicode.Scalar?      // nil for .delete
}

struct PronunciationScore: Equatable, Sendable {
    var accuracy: Double      // 0..1 — how close the recognized text is to the target
    var clarity: Double       // 0..1 — avg recognizer confidence
    var completeness: Double  // 0..1 — recognized length relative to target
    var transcription: String
    // false when neither the final result nor any partial gave us text. The
    // user either stayed silent, the mic was too far away, or the recognizer
    // simply couldn't transcribe the Arabic speech it heard.
    var didHearSpeech: Bool
    // true when the mic picked up audio above the background-noise floor —
    // independent of whether the recognizer produced any text. Lets the UI
    // tell "silence" apart from "spoke but wasn't recognized".
    var didDetectVoice: Bool
    // Per-letter alignment between the normalised target and the normalised
    // transcription. Empty when there's no transcription. UI uses this to
    // highlight which letters matched, were swapped, missed, or added.
    var diff: [DiffStep]

    var overall: Double {
        // SFSpeechRecognizer doesn't report per-segment confidence for ar-SA
        // (always 0), so weighting clarity here would cap the best possible
        // score at 75%. Drive the score off accuracy + completeness only;
        // clarity stays in the struct for display but doesn't gate XP/mastery.
        0.7 * accuracy + 0.3 * completeness
    }

    static let zero = PronunciationScore(
        accuracy: 0, clarity: 0, completeness: 0,
        transcription: "", didHearSpeech: false, didDetectVoice: false, diff: []
    )
}

enum SpeechAuthorization {
    case unknown, granted, denied
}

@MainActor
final class SpeechScorer: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var partialTranscription = ""
    @Published private(set) var authorization: SpeechAuthorization = .unknown
    /// Smoothed mic amplitude in 0…1 — driven by the live input-tap RMS.
    /// Zero when no recording session is active.
    @Published private(set) var audioLevel: Float = 0

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // Per-session diagnostics. Reset at the start of every `record(...)`.
    // - bestPartial: the longest non-empty partial transcription seen during
    //   the session. Used as a fallback when SFSpeechRecognizer hands us a
    //   final result with an empty bestTranscription (happens on short
    //   utterances in ar-SA — the recognizer "changes its mind" at finalize).
    // - peakLevel: max smoothed mic level observed. Tells us whether the
    //   user actually spoke, independent of whether the recognizer produced
    //   any text.
    private var bestPartial: String = ""
    private var peakLevel: Float = 0

    func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        let micGranted = await AVAudioApplication.requestRecordPermission()
        let speechOK = speechStatus == .authorized
        authorization = (speechOK && micGranted) ? .granted : .denied
        return authorization == .granted
    }

    /// Records up to `maxSeconds` and returns a score against `expectedArabic`.
    func record(expectedArabic: String, maxSeconds: TimeInterval = 5) async throws -> PronunciationScore {
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "Asma.Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"])
        }
        try startSession()
        defer { stopSession() }

        // Fresh per-session diagnostics — see field docs above.
        bestPartial = ""
        peakLevel = 0

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Don't force on-device: for ar-SA the on-device model ships only on
        // some iPhones (and only after the user installs Arabic dictation),
        // and without it the recognizer silently returns an empty string.
        // Let iOS pick the best available path — on-device when present,
        // otherwise Apple's speech service.
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, weak request] buffer, _ in
            request?.append(buffer)
            let level = Self.rmsLevel(of: buffer)
            DispatchQueue.main.async {
                guard let self else { return }
                // Exponential smoothing — quick attack, gentle decay so
                // bars feel responsive but don't strobe on every buffer.
                let prev = self.audioLevel
                let next = level > prev ? (0.4 * prev + 0.6 * level)
                                        : (0.75 * prev + 0.25 * level)
                self.audioLevel = next
                if next > self.peakLevel { self.peakLevel = next }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        partialTranscription = ""

        let result: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                Task { @MainActor in
                    if let result {
                        let text = result.bestTranscription.formattedString
                        self.partialTranscription = text
                        // Remember the longest non-empty transcription we
                        // saw — the recognizer sometimes drops back to "" on
                        // finalize for short ar-SA utterances.
                        if text.count > self.bestPartial.count {
                            self.bestPartial = text
                        }
                        if result.isFinal, !resumed {
                            resumed = true
                            continuation.resume(returning: result)
                        }
                    }
                    if let error, !resumed {
                        resumed = true
                        continuation.resume(throwing: error)
                    }
                }
            }
            self.recognitionTask = task

            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(maxSeconds * 1_000_000_000))
                guard let self else { return }
                if self.isRecording, !resumed {
                    self.audioEngine.stop()
                    self.audioEngine.inputNode.removeTap(onBus: 0)
                    self.recognitionRequest?.endAudio()
                }
            }
        }

        return score(expected: expectedArabic, result: result)
    }

    func cancel() {
        stopSession()
    }

    // MARK: - private

    private func startSession() throws {
        // `.record` interrupts every other player on the session, so pause
        // the ambient loop with its own reason. PracticeView pauses with
        // `.practice` for the whole screen lifetime — distinct reasons so
        // each owner's resume only clears its own bit.
        AmbientSoundPlayer.shared.pause(reason: .recording)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func stopSession() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        audioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        AmbientSoundPlayer.shared.resume(reason: .recording)
    }

    /// Compute log-scaled RMS in 0…1 from a single audio buffer.
    /// −60 dBFS maps to 0, 0 dBFS maps to 1.
    private static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        if n == 0 { return 0 }
        var sum: Float = 0
        for i in 0..<n {
            let s = channel[i]
            sum += s * s
        }
        let rms = sqrtf(sum / Float(n))
        // Avoid log(0).
        let db = 20 * log10f(max(rms, 0.00001))
        // Treat anything below −60 dBFS as silence.
        let normalized = max(0, min(1, (db + 60) / 60))
        return normalized
    }

    private func score(expected: String, result: SFSpeechRecognitionResult) -> PronunciationScore {
        let bestTranscription = result.bestTranscription
        let finalText = bestTranscription.formattedString
        // Fallback: if the recognizer finalized with an empty string but we
        // captured a non-empty partial during the session, use that. Common
        // on short ar-SA utterances.
        let recognized = finalText.isEmpty ? bestPartial : finalText
        let expectedNorm = ArabicNormalizer.normalize(expected)
        let recognizedNorm = ArabicNormalizer.normalize(recognized)

        // Work on scalars (not Characters) so phonetic substitutions match
        // letter-by-letter and aren't confused by combining-mark clusters.
        let expectedScalars = Array(expectedNorm.unicodeScalars)
        let recognizedScalars = Array(recognizedNorm.unicodeScalars)

        let distance = ArabicNormalizer.weightedDistance(expectedScalars, recognizedScalars)
        let denom = max(expectedScalars.count, recognizedScalars.count, 1)
        let accuracy = max(0, 1.0 - distance / Double(denom))

        // Reported for display only — `overall` ignores it because ar-SA
        // segments come back with zero confidence on real devices.
        let confidences = bestTranscription.segments.map { Double($0.confidence) }
        let clarity = confidences.isEmpty
            ? 0
            : confidences.reduce(0, +) / Double(confidences.count)

        let diff = recognizedScalars.isEmpty
            ? []
            : ArabicNormalizer.align(expected: expectedScalars, recognized: recognizedScalars)

        // "How much of the target did the user actually nail?" — fraction
        // of expected letters that line up as an exact match in the diff.
        // Independent of accuracy: babbling random letters of the right
        // length used to give 100% here via a naive length-ratio; this
        // version stays honest because it ignores anything that isn't a
        // real match.
        let matches = diff.filter { $0.op == .match }.count
        let completeness = expectedScalars.isEmpty
            ? 0
            : Double(matches) / Double(expectedScalars.count)

        return PronunciationScore(
            accuracy: accuracy,
            clarity: clarity,
            completeness: completeness,
            transcription: recognized,
            didHearSpeech: !recognizedNorm.isEmpty,
            // ~−45 dBFS — comfortably above the −60 dBFS noise floor used
            // in `rmsLevel`. Anything quieter is realistically silence.
            didDetectVoice: peakLevel >= 0.15,
            diff: diff
        )
    }
}

// MARK: - Arabic normalization

enum ArabicNormalizer {
    /// Strips Arabic tashkeel (harakat) and tatweel and unifies common letter
    /// forms, so the recognizer's loose transcription can be compared to the
    /// canonical, fully-vocalised name.
    ///
    /// `String.folding(.diacriticInsensitive)` in Foundation does NOT remove
    /// Arabic combining marks (U+064B–U+065F etc.) — it's tuned for Latin
    /// diacritics. So we walk Unicode scalars ourselves and drop the
    /// harakat ranges by hand.
    static func normalize(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        out.reserveCapacity(s.unicodeScalars.count)
        for scalar in s.unicodeScalars {
            let v = scalar.value
            // Arabic combining marks / harakat / honorifics / Quranic annotation.
            if (0x064B...0x065F).contains(v) { continue }  // fatha, damma, kasra, shadda, sukun, …
            if v == 0x0670 { continue }                    // superscript alef
            if (0x0610...0x061A).contains(v) { continue }  // honorific signs
            if (0x06D6...0x06ED).contains(v) { continue }  // Quranic annotation signs
            if v == 0x0640 { continue }                    // tatweel (kashida) — pure elongation
            if Character(scalar).isWhitespace { continue }
            out.append(unify(scalar))
        }
        return String(out)
    }

    private static func unify(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        switch scalar.value {
        case 0x0623, 0x0625, 0x0622, 0x0671: return Unicode.Scalar(0x0627)! // أ إ آ ٱ → ا
        case 0x0649: return Unicode.Scalar(0x064A)!                          // ى → ي
        case 0x0629: return Unicode.Scalar(0x0647)!                          // ة → ه
        default: return scalar
        }
    }
}

// MARK: - Phonetic distance + alignment

extension ArabicNormalizer {
    /// Pairs of letters that sound close to a casual listener (and to
    /// SFSpeechRecognizer). Substitution within a pair costs a fraction of
    /// a full mistake — so swapping ح↔ه (close throat sounds) doesn't hurt
    /// nearly as much as swapping ا↔ع (genuinely different phonemes).
    static let phoneticGroups: [Set<Unicode.Scalar>] = [
        // Emphatic ↔ non-emphatic pairs
        [u(0x0633), u(0x0635)], // س ↔ ص  sin / sad
        [u(0x062A), u(0x0637)], // ت ↔ ط  ta / ṭa
        [u(0x062F), u(0x0636)], // د ↔ ض  dal / ḍad
        [u(0x0630), u(0x0638)], // ذ ↔ ظ  dhal / ẓa
        [u(0x0632), u(0x0638)], // ز ↔ ظ  zay / ẓa
        // Throat / palatal confusables
        [u(0x062D), u(0x0647)], // ح ↔ ه
        [u(0x062D), u(0x062E)], // ح ↔ خ
        [u(0x062E), u(0x063A)], // خ ↔ غ
        [u(0x0643), u(0x0642)], // ك ↔ ق
        // tā-marbūta normally unified to ه, kept here as belt-and-braces
        [u(0x0629), u(0x0647)], // ة ↔ ه
    ]

    /// Cost of replacing `a` with `b`:
    ///   • 0 if identical
    ///   • 0.3 if they're in a known phonetic group (sound close)
    ///   • 1 otherwise
    static func substitutionCost(_ a: Unicode.Scalar, _ b: Unicode.Scalar) -> Double {
        if a == b { return 0 }
        for group in phoneticGroups where group.contains(a) && group.contains(b) {
            return 0.3
        }
        return 1
    }

    /// Weighted Levenshtein on Unicode scalars. Insert/delete = 1,
    /// substitution = `substitutionCost(...)`.
    static func weightedDistance(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Double {
        if a.isEmpty { return Double(b.count) }
        if b.isEmpty { return Double(a.count) }

        var prev = (0...b.count).map { Double($0) }
        var curr = Array(repeating: 0.0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = Double(i)
            for j in 1...b.count {
                let sub = prev[j - 1] + substitutionCost(a[i - 1], b[j - 1])
                let del = prev[j] + 1
                let ins = curr[j - 1] + 1
                curr[j] = min(sub, del, ins)
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }

    /// Per-letter alignment between expected and recognized, derived from
    /// the same DP table as `weightedDistance` plus a backtrack pass.
    /// Walks the table from (n,m) back to (0,0) and emits `DiffStep`s in
    /// source order.
    static func align(expected: [Unicode.Scalar], recognized: [Unicode.Scalar]) -> [DiffStep] {
        let n = expected.count
        let m = recognized.count
        if n == 0 && m == 0 { return [] }

        // Full DP table so we can backtrack.
        var dp = Array(repeating: Array(repeating: 0.0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = Double(i) }
        for j in 0...m { dp[0][j] = Double(j) }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let sub = dp[i - 1][j - 1] + substitutionCost(expected[i - 1], recognized[j - 1])
                    let del = dp[i - 1][j] + 1
                    let ins = dp[i][j - 1] + 1
                    dp[i][j] = min(sub, del, ins)
                }
            }
        }

        var steps: [DiffStep] = []
        var i = n
        var j = m
        while i > 0 || j > 0 {
            if i > 0 && j > 0 {
                let cost = substitutionCost(expected[i - 1], recognized[j - 1])
                if dp[i][j] == dp[i - 1][j - 1] + cost {
                    let op: AlignOp = (cost == 0) ? .match : .sub
                    steps.append(DiffStep(op: op, expected: expected[i - 1], actual: recognized[j - 1]))
                    i -= 1; j -= 1
                    continue
                }
            }
            if i > 0 && dp[i][j] == dp[i - 1][j] + 1 {
                steps.append(DiffStep(op: .delete, expected: expected[i - 1], actual: nil))
                i -= 1
                continue
            }
            // remaining case: dp[i][j] == dp[i][j-1] + 1
            steps.append(DiffStep(op: .insert, expected: nil, actual: recognized[j - 1]))
            j -= 1
        }
        return steps.reversed()
    }

    private static func u(_ v: UInt32) -> Unicode.Scalar { Unicode.Scalar(v)! }
}
