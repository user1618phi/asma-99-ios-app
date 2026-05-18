import Foundation

enum XPSource: String, Sendable {
    case pronunciation
    case flashcardKnown
    case test
    /// Fired exactly once per day, the moment `studiedToday` crosses the
    /// user's chosen `flashcardCount` goal. Idempotent via XPEvent lookup.
    case dailyGoal
    /// Awarded the instant a name graduates `.studying → .confirmed`
    /// (the "3 correct in a row" milestone). One bonus per name per
    /// confirmation event — if a name lapses and reconfirms later, it
    /// pays out again, which is intentional: it celebrates the user
    /// rebuilding the streak.
    case nameConfirmed
    /// Awarded the instant a name reaches `.mastered` (passed the final
    /// 30-day box review). Career-tier milestone — one per name per
    /// mastery event, same lapse logic as above.
    case nameMastered
}

enum XPCalculator {
    static let pronunciationBase = 5
    static let flashcardBase = 2
    /// One-time daily reward for hitting the flashcard goal. Picked to
    /// feel meaningful next to the per-card 2 XP without overshadowing
    /// test rewards (25–100).
    static let dailyGoalBonus = 10
    /// Per-name bonus when it reaches `.confirmed`. 99 × 15 = 1 485 XP
    /// over the full path, which paces nicely against the 100 / 1 000
    /// achievement thresholds.
    static let nameConfirmedBonus = 15
    /// Per-name bonus when it reaches `.mastered`. Larger because the
    /// path is longer (55+ days of spaced reviews per name).
    static let nameMasteredBonus = 30

    /// Base XP for a test depends on its size.
    static func testBaseXP(totalQuestions: Int) -> Int {
        switch totalQuestions {
        case ..<5: return 25
        case 5..<10: return 50
        default: return 100
        }
    }

    /// Test XP formula (per plan): proportion of correct answers in the first cycle.
    /// 5/5 first try → 100% of base. 3/5 first try, then cleanup cycles → 60% of base.
    static func testXP(firstCycleCorrect: Int, totalQuestions: Int) -> Int {
        guard totalQuestions > 0 else { return 0 }
        let base = testBaseXP(totalQuestions: totalQuestions)
        let ratio = Double(firstCycleCorrect) / Double(totalQuestions)
        return Int((Double(base) * ratio).rounded())
    }

    static func pronunciationXP(score: Double) -> Int {
        // Graduated reward so beginners get encouragement for honest attempts
        // instead of the all-or-nothing 0/5 split. Top tier still pays the
        // same `pronunciationBase` as before.
        switch score {
        case ..<0.35: return 0
        case ..<0.55: return 1
        case ..<0.75: return 3
        default:       return pronunciationBase
        }
    }
}
