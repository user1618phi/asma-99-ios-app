import Foundation

/// "Free quiz" session — the practice mode shown during the inter-round
/// cooldown on the Tests tab. Covers **all 99 names** in a single
/// shuffled pass in a single, user-picked direction:
///
///   - `.nameToMeaning` — show the Arabic name, choose the right meaning
///   - `.meaningToName` — show the meaning, choose the right Arabic name
///
/// Audio and mix modes are intentionally NOT available here — the user
/// picks one direction up front for a quiet, focused practice run.
///
/// Crucially, this session is **side-effect free**: no `NameProgress`
/// mutation, no XP awards, no `TestAttempt` persisted, no cooldown push
/// scheduled. The whole point is "kill time while you wait without
/// affecting your real review schedule."
///
/// Counter contract (used by `FreeQuizView`'s top bar):
///   - Initial: `0 / 0`
///   - After each *advance* (i.e. user tapped Continue): `correct / asked`
///     where `asked` is the total questions completed so far and
///     `correct` is how many of those were answered correctly. Max
///     state: `99 / 99` (perfect run).
struct FreeQuizSession {
    let mode: TestMode
    let language: String
    private(set) var queue: [TestQuestion]
    private(set) var asked: Int = 0
    private(set) var correctCount: Int = 0

    init(mode: TestMode, language: String) {
        self.mode = mode
        self.language = language
        let allNames = NamesRepository.shared.names
        // Reuse `TestSessionFactory.makeQueue` with the user-picked mode
        // (no .mix here — caller is restricted to the two directional
        // modes). Full 99-name pool, both as eligible and as distractors.
        self.queue = TestSessionFactory.makeQueue(
            mode: mode,
            total: allNames.count,
            language: language,
            eligible: allNames,
            pool: allNames
        )
    }

    var currentQuestion: TestQuestion? { queue.first }
    var isComplete: Bool { queue.isEmpty }
    /// Constant 99 — the size of the name pool. Useful for the top-bar
    /// "X / 99 final" display in the completion screen.
    var total: Int { NamesRepository.shared.names.count }

    /// Apply the user's answer and advance the queue. Returns whether
    /// the answer was correct so the caller can drive haptics. Counter
    /// fields tick AFTER this call (the view holds them at `0/0` until
    /// the user taps Continue, matching `TestSession`'s flow).
    mutating func answer(optionIndex: Int) -> Bool {
        guard let q = queue.first else { return false }
        let correct = optionIndex == q.correctIndex
        if correct { correctCount += 1 }
        asked += 1
        queue.removeFirst()
        return correct
    }
}
