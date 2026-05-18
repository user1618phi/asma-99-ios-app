import Foundation

/// Persisted lifecycle of a single name. Stored as `NameProgress.reviewStateRaw`.
///
/// new → studying → confirmed → strengthening (box 1..4) → mastered
///
/// Flashcards push `new → studying`. The user's "3-correct-in-a-row" test rule
/// pushes `studying → confirmed`. After that, the spaced-repetition ladder
/// (driven by `ReviewSchedule.boxDays`) carries it through strengthening
/// to mastered. Lapses follow the inverse path with single-step penalties
/// for already-strengthened names and a 3-wrong-in-a-row reset for studying
/// or confirmed names.
enum ReviewState: Int, CaseIterable, Comparable {
    case new = 0
    case studying = 1
    case confirmed = 2
    case strengthening = 3
    case mastered = 4

    static func < (lhs: ReviewState, rhs: ReviewState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Side-effect description of a single test answer — used by the test
/// session/result UI to surface "you confirmed N today" / "you mastered N
/// today" feedback. The engine itself doesn't render anything.
struct AnswerOutcome: Equatable {
    let becameConfirmedToday: Bool
    let becameMastered: Bool
    let lapsed: Bool

    static let none = AnswerOutcome(becameConfirmedToday: false, becameMastered: false, lapsed: false)
}

/// The single mutator of `NameProgress`. Every code path that wants to
/// transition a name's state must go through here — that keeps the state
/// machine in one file and prevents call sites from drifting (which was the
/// problem with the previous "every view does +1/-1 to masteryLevel" model).
enum ProgressEngine {
    /// Mark a name as touched-by-flashcards today. Flashcards are preparation
    /// only — no mastery change, no consecutive-counter change. Their only
    /// job is to (a) bump `.new → .studying` and (b) record that the user has
    /// studied this name today, which is what makes it eligible for the
    /// today's-pool test queue.
    static func markStudied(_ p: NameProgress, on date: Date = .now) {
        let state = ReviewState(rawValue: p.reviewStateRaw) ?? .new
        let cal = Calendar.current
        let today = cal.startOfDay(for: date)

        if state == .new {
            p.reviewStateRaw = ReviewState.studying.rawValue
        }
        if p.firstStudiedAt == nil {
            p.firstStudiedAt = today
        }
        let lastStudiedDay = p.lastStudiedAt.map { cal.startOfDay(for: $0) }
        if lastStudiedDay != today {
            p.seenCount += 1
        }
        p.lastStudiedAt = date
        p.lastReviewedAt = date
        recomputeDisplayMastery(p)
    }

    /// Apply a single test answer. Returns what happened so the caller can
    /// roll up session-level totals (e.g. for the results screen).
    @discardableResult
    static func recordAnswer(_ p: NameProgress, correct: Bool, on date: Date = .now) -> AnswerOutcome {
        let cal = Calendar.current
        let today = cal.startOfDay(for: date)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? date

        p.lastReviewedAt = date
        p.lastQuizCorrect = correct

        let state = ReviewState(rawValue: p.reviewStateRaw) ?? .new
        // Names freshly transitioned mid-session won't have a nextDueAt yet
        // — treat that as "due now" so the very first review actually counts.
        let isDue = p.nextDueAt.map { $0 <= date } ?? true

        var outcome = AnswerOutcome.none

        if correct {
            p.consecutiveWrong = 0

            switch state {
            case .new, .studying:
                p.consecutiveCorrect += 1
                if p.consecutiveCorrect >= ReviewSchedule.confirmTarget {
                    p.reviewStateRaw = ReviewState.confirmed.rawValue
                    p.consecutiveCorrect = 0
                    p.box = 0
                    p.nextDueAt = cal.date(byAdding: .day, value: ReviewSchedule.boxDays[0], to: today)
                    outcome = AnswerOutcome(becameConfirmedToday: true, becameMastered: false, lapsed: false)
                }

            case .confirmed:
                // Only the first *due* review converts confirmed → strengthening.
                // Extra correct answers on the same day (e.g. user opened a
                // second test) leave the schedule alone — that's the point
                // of spacing.
                if isDue {
                    p.reviewStateRaw = ReviewState.strengthening.rawValue
                    p.box = 1
                    let days = ReviewSchedule.boxDays[1]
                    p.nextDueAt = cal.date(byAdding: .day, value: days, to: today)
                }

            case .strengthening:
                if isDue {
                    if p.box >= ReviewSchedule.maxBox {
                        // Passed the 30-day review → graduated.
                        p.reviewStateRaw = ReviewState.mastered.rawValue
                        p.nextDueAt = nil
                        outcome = AnswerOutcome(becameConfirmedToday: false, becameMastered: true, lapsed: false)
                    } else {
                        p.box += 1
                        let idx = min(p.box, ReviewSchedule.boxDays.count - 1)
                        let days = ReviewSchedule.boxDays[idx]
                        p.nextDueAt = cal.date(byAdding: .day, value: days, to: today)
                    }
                }
                // Non-due correct (e.g. mid-session re-test after a wrong answer
                // bounced the card to the back of the queue) doesn't shorten
                // intervals — that would undo the lapse penalty.

            case .mastered:
                // Mastered names don't appear in the today's-pool builder,
                // so getting here means the caller forced one in. Treat as
                // a no-op refresh.
                break
            }
        } else {
            p.consecutiveCorrect = 0

            switch state {
            case .new, .studying, .confirmed:
                p.consecutiveWrong += 1
                if p.consecutiveWrong >= ReviewSchedule.lapseTarget {
                    p.reviewStateRaw = ReviewState.new.rawValue
                    p.consecutiveCorrect = 0
                    p.consecutiveWrong = 0
                    p.firstStudiedAt = nil
                    p.lastStudiedAt = nil
                    p.box = 0
                    p.nextDueAt = nil
                    outcome = AnswerOutcome(becameConfirmedToday: false, becameMastered: false, lapsed: true)
                }

            case .strengthening:
                p.box = max(1, p.box - 1)
                p.nextDueAt = tomorrow
                outcome = AnswerOutcome(becameConfirmedToday: false, becameMastered: false, lapsed: true)

            case .mastered:
                // Lapse on a mastered name → drop back to strengthening box
                // 4 (one below mastery) instead of full reset. Mirrors the
                // Anki / FSRS relearning philosophy: don't nuke long-built
                // strength on one slip-up.
                p.reviewStateRaw = ReviewState.strengthening.rawValue
                p.box = ReviewSchedule.maxBox
                p.nextDueAt = tomorrow
                outcome = AnswerOutcome(becameConfirmedToday: false, becameMastered: false, lapsed: true)
            }
        }

        recomputeDisplayMastery(p)
        return outcome
    }

    /// Keep the legacy `masteryLevel` 0..5 stored field in sync with the new
    /// state machine. Existing UI (HomeView's "next-up" sort, FlashcardsLanding's
    /// "X / 99" learned counter, AchievementsView, ProfileView) all read this
    /// field; rather than touch every callsite we make it a derived mirror.
    static func recomputeDisplayMastery(_ p: NameProgress) {
        let state = ReviewState(rawValue: p.reviewStateRaw) ?? .new
        let level: Int
        switch state {
        case .new:           level = 0
        case .studying:      level = 1
        case .confirmed:     level = 3
        case .strengthening:
            switch p.box {
            case 1: level = 3
            case 2: level = 4
            default: level = 5
            }
        case .mastered:      level = 5
        }
        p.masteryLevel = level
    }
}
