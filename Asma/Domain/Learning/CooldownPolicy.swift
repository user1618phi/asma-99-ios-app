import Foundation

/// Forced spacing between consecutive test sessions in the same day.
///
/// The original mental model was "3 rounds per day" — but back-to-back
/// rounds on hot memory don't build durable retention (Cepeda et al.,
/// 2006). This policy enforces a progressive cooldown so each round
/// happens after a real lag, turning "3 quick rounds" into "3 spaced
/// rounds" within the same day.
///
/// Progressive intervals (30m / 1h / 2h) mirror the same expanding-ratio
/// idea as the multi-day box ladder, just compressed into hours instead
/// of days. After round 3 there's no further block — extra rounds are
/// the user's choice.
enum CooldownPolicy {
    /// Required wait *after* completing this round before the next one
    /// becomes available. `0` means "no cooldown, take the next round
    /// whenever".
    static func cooldown(after roundsCompleted: Int) -> TimeInterval {
        switch roundsCompleted {
        case 1: return 30 * 60          // 30 minutes after round 1
        case 2: return 60 * 60          // 1 hour after round 2
        case 3: return 2 * 60 * 60      // 2 hours after round 3
        default: return 0                // round 4+: free
        }
    }

    /// Seconds left on the cooldown timer, or 0 if cooldown is not
    /// currently in effect (no tests today, or it has already expired).
    static func remaining(testAttempts: [TestAttempt], now: Date = .now) -> TimeInterval {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let todaysTests = testAttempts
            .filter { cal.startOfDay(for: $0.date) == today }
            .sorted { $0.date > $1.date }
        guard let lastTest = todaysTests.first else { return 0 }
        let block = cooldown(after: todaysTests.count)
        guard block > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(lastTest.date)
        return max(0, block - elapsed)
    }
}
