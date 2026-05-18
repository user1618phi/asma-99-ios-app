import Foundation

/// Single source of truth for spaced-repetition intervals and thresholds.
///
/// Five intervals (1/3/7/14/30 days) define the ladder a name climbs from
/// the moment it is first "Confirmed today" to the moment it is "Mastered".
/// The shape is a deliberately simple Leitner-style ladder rather than SM-2
/// or FSRS: with only 99 items the personalisation gain of an adaptive
/// algorithm doesn't pay for the implementation complexity, and equal-ratio
/// expanding intervals are well-supported by Cepeda et al. (2006).
enum ReviewSchedule {
    /// Day-offsets for each spaced review.
    ///
    /// Index 0 is the *first* review after a name reaches Confirmed; the
    /// remaining indices are the intervals between successive box reviews.
    /// Box k (k = 1..4) uses `boxDays[k]` to schedule its next review. After
    /// passing box 4's 30-day review the name graduates to `.mastered`.
    static let boxDays: [Int] = [1, 3, 7, 14, 30]

    /// Consecutive correct answers required in tests to move a `.studying`
    /// name to `.confirmed`. The user's MVP rule.
    static let confirmTarget = 3

    /// Consecutive wrong answers that drop a `.studying` / `.confirmed`
    /// name back to `.new` (forcing re-study via flashcards). Mirror image
    /// of `confirmTarget` for the lapse path.
    static let lapseTarget = 3

    static let maxBox = 4
}
