import Foundation
import SwiftUI

enum TestMode: String, CaseIterable, Identifiable, Hashable {
    case nameToMeaning
    case meaningToName
    case audioToArabic
    case mix

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .nameToMeaning: return "tests.mode.nameToMeaning.title"
        case .meaningToName: return "tests.mode.meaningToName.title"
        case .audioToArabic: return "tests.mode.audioToArabic.title"
        case .mix: return "tests.mode.mix.title"
        }
    }

    var subtitleKey: String {
        switch self {
        case .nameToMeaning: return "tests.mode.nameToMeaning.subtitle"
        case .meaningToName: return "tests.mode.meaningToName.subtitle"
        case .audioToArabic: return "tests.mode.audioToArabic.subtitle"
        case .mix: return "tests.mode.mix.subtitle"
        }
    }

    var icon: String {
        switch self {
        case .nameToMeaning: return "rectangle.and.text.magnifyingglass"
        case .meaningToName: return "character.book.closed"
        case .audioToArabic: return "waveform"
        case .mix: return "sparkles"
        }
    }
}

enum QuestionPrompt: Hashable {
    case text(String)
    case audio(String)
}

enum AnswerOption: Hashable {
    case text(String)
    case arabic(String)
}

struct TestQuestion: Identifiable, Hashable {
    let id: UUID
    let nameNumber: Int
    let mode: TestMode
    let prompt: QuestionPrompt
    let options: [AnswerOption]
    let correctIndex: Int
}

struct TestSession {
    let mode: TestMode
    let language: String
    private(set) var queue: [TestQuestion]
    private(set) var firstCycleCorrect = 0
    private(set) var firstCycleSeen: Set<UUID> = []
    private(set) var totalQuestions: Int
    private(set) var cycle = 1
    /// Questions in the *current* cycle. Cycle 1 starts equal to
    /// `totalQuestions`. Cycle k>1 starts equal to the number of wrong
    /// answers that survived cycle k-1.
    private(set) var currentCycleSize: Int
    /// Answers submitted during the current cycle. Resets to 0 at every
    /// cycle bump. The session's top-bar counter renders as
    /// `(currentCycleAnswered + 1) / currentCycleSize`.
    private(set) var currentCycleAnswered: Int = 0
    private(set) var wrongIDs: Set<Int> = []
    private var totalAnswered: Int = 0

    /// `eligible` is today's pool (names studied today + due reviews —
    /// see `TodayPoolFactory`). `distractorPool` is the full 99 used to
    /// fill the three wrong options on each question. Splitting them is
    /// what makes the session ask about *today's* names while still
    /// drawing plausible distractors from the entire name set.
    init(mode: TestMode, totalQuestions: Int, language: String, eligible: [AsmaName], distractorPool: [AsmaName]) {
        self.mode = mode
        self.language = language
        self.queue = TestSessionFactory.makeQueue(
            mode: mode,
            total: totalQuestions,
            language: language,
            eligible: eligible,
            pool: distractorPool
        )
        // `totalQuestions` reflects the *actual* session length, not the
        // requested cap. On Day 1 the user has only ~3 studied names and
        // the "X / Y" counter should say "01 / 03", not "01 / 05".
        self.totalQuestions = self.queue.count
        self.currentCycleSize = self.queue.count
    }

    var isComplete: Bool { queue.isEmpty }

    var currentQuestion: TestQuestion? { queue.first }

    mutating func answer(optionIndex: Int) -> Bool {
        guard let q = queue.first else { return false }
        let correct = optionIndex == q.correctIndex
        let firstSeen = !firstCycleSeen.contains(q.id)
        if firstSeen {
            firstCycleSeen.insert(q.id)
            if correct { firstCycleCorrect += 1 }
        }
        if correct {
            queue.removeFirst()
        } else {
            wrongIDs.insert(q.nameNumber)
            // Put it to the back of the queue — user re-tries on a later cycle.
            queue.append(q)
            queue.removeFirst()
        }
        totalAnswered += 1
        currentCycleAnswered += 1

        // End-of-cycle: if we've answered everything queued for *this* pass
        // and there are still re-queued wrongs at the back, bump into the
        // next cycle. Done here (not in a separate `tickCycleIfNeeded`) so
        // the counter UI can rely on `cycle` / `currentCycleSize` /
        // `currentCycleAnswered` being self-consistent after every answer.
        if currentCycleAnswered >= currentCycleSize && !queue.isEmpty {
            cycle += 1
            currentCycleSize = queue.count
            currentCycleAnswered = 0
        }

        return correct
    }
}

enum TestSessionFactory {
    static func makeQueue(mode: TestMode, total: Int, language: String, eligible: [AsmaName], pool: [AsmaName]) -> [TestQuestion] {
        let sample = eligible.shuffled().prefix(total)
        return sample.map { name in
            let effective: TestMode = (mode == .mix)
                ? [TestMode.nameToMeaning, .meaningToName, .audioToArabic].randomElement()!
                : mode
            return makeQuestion(for: name, mode: effective, language: language, pool: pool)
        }
    }

    private static func makeQuestion(for name: AsmaName, mode: TestMode, language: String, pool: [AsmaName]) -> TestQuestion {
        let distractors = pool.filter { $0.number != name.number }.shuffled().prefix(3).map { $0 }
        let names4 = ([name] + distractors).shuffled()
        guard let correctIndex = names4.firstIndex(where: { $0.number == name.number }) else {
            preconditionFailure("Lost correct answer while shuffling")
        }
        let translation = name.translation(for: language)
        let prompt: QuestionPrompt
        let options: [AnswerOption]
        switch mode {
        case .nameToMeaning:
            prompt = .text(name.transliteration)
            options = names4.map { .text($0.translation(for: language).translation) }
        case .meaningToName:
            prompt = .text(translation.translation)
            options = names4.map { .text($0.transliteration) }
        case .audioToArabic:
            prompt = .audio(name.audio)
            options = names4.map { .arabic($0.arabic) }
        case .mix:
            prompt = .text(name.transliteration)
            options = names4.map { .text($0.translation(for: language).translation) }
        }
        return TestQuestion(
            id: UUID(),
            nameNumber: name.number,
            mode: mode,
            prompt: prompt,
            options: options,
            correctIndex: correctIndex
        )
    }
}
