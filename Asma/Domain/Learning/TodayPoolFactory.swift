import Foundation

/// Builds the set of names eligible for *today's* test session.
///
/// Two buckets are merged:
///   1. **Due reviews** — names in `.confirmed` or `.strengthening` whose
///      `nextDueAt` has arrived. These are the spaced-repetition checks the
///      user must answer to advance their long-term memory.
///   2. **In-progress** — names in `.studying` (regardless of when last
///      touched). Also `.new` names *only if* studied today via flashcards
///      — a name never seen has no business being asked in a test.
///
/// **Carryover**: a `.studying` name from a previous day stays in the pool
/// until it either confirms (3-in-row) or lapses back to `.new` (3-wrong
/// in a row). The user is never punished for taking a break — their
/// `consecutiveCorrect` is preserved across days. See ProgressEngine for
/// the lapse path.
///
/// Mastered names are deliberately excluded: they have no `nextDueAt` until
/// (and unless) the user lapses on them elsewhere.
enum TodayPoolFactory {
    /// Names eligible for today's test, in priority order: oldest due reviews
    /// first, then the names studied today. Caller decides how many to take
    /// (the test session size cap lives in `AppSettingsKey.testQuestionCount`).
    static func eligibleToday(
        progresses: [NameProgress],
        names: [AsmaName],
        on date: Date = .now
    ) -> [AsmaName] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: date)
        let nameByNumber = Dictionary(uniqueKeysWithValues: names.map { ($0.number, $0) })

        var dueReviews: [(NameProgress, AsmaName)] = []
        var studiedToday: [(NameProgress, AsmaName)] = []

        for p in progresses {
            guard let name = nameByNumber[p.number] else { continue }
            let state = ReviewState(rawValue: p.reviewStateRaw) ?? .new

            switch state {
            case .confirmed, .strengthening:
                if let due = p.nextDueAt, due <= date {
                    dueReviews.append((p, name))
                }
            case .new:
                // `.new` requires an actual flashcard touch today — a name
                // the user has never seen has no business in a test.
                if let last = p.lastStudiedAt, cal.startOfDay(for: last) == today {
                    studiedToday.append((p, name))
                }
            case .studying:
                // Always present — once introduced, a name stays in the
                // pool until it either confirms or lapses. consecutiveCorrect
                // is preserved across days, so a Day 1 attempt at cc=1 can
                // finish on Day 2 with two more correct answers.
                studiedToday.append((p, name))
            case .mastered:
                break
            }
        }

        // Oldest due first — review-burden should feel chronological, not
        // random, so the user can build intuition for "what was I shaky on
        // last week."
        dueReviews.sort { (a, b) in
            (a.0.nextDueAt ?? .distantPast) < (b.0.nextDueAt ?? .distantPast)
        }
        // Studied-today order: lowest mastery first (i.e. .new before
        // .studying with progress), then by name number for stability.
        studiedToday.sort { (a, b) in
            if a.0.masteryLevel != b.0.masteryLevel {
                return a.0.masteryLevel < b.0.masteryLevel
            }
            return a.0.number < b.0.number
        }

        return dueReviews.map(\.1) + studiedToday.map(\.1)
    }

    /// Just the counts — used by TestsLandingView to render
    /// "Сегодня: N новых · M повторов" without building the full pool.
    static func todayCounts(
        progresses: [NameProgress],
        on date: Date = .now
    ) -> (newToday: Int, dueReviews: Int) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: date)
        var newToday = 0
        var dueReviews = 0

        for p in progresses {
            let state = ReviewState(rawValue: p.reviewStateRaw) ?? .new
            switch state {
            case .confirmed, .strengthening:
                if let due = p.nextDueAt, due <= date {
                    dueReviews += 1
                }
            case .new:
                if let last = p.lastStudiedAt, cal.startOfDay(for: last) == today {
                    newToday += 1
                }
            case .studying:
                // Same carryover rule as eligibleToday — `.studying`
                // always counts toward "newToday", whether the user touched
                // it today via flashcards or it's a leftover from a prior
                // day. The eyebrow stays an honest reflection of the pool.
                newToday += 1
            case .mastered:
                break
            }
        }

        return (newToday, dueReviews)
    }
}
