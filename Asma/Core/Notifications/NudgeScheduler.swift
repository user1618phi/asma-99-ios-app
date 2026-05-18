import Foundation

/// Decides what daily nudges to fire over the next few days based on the
/// current state of the user's progress, then hands them to
/// `NotificationsService` for scheduling.
///
/// One nudge type now: a 09:00 morning push when the user has reviews
/// due (`"N names ready for review"`). The evening reminder was retired
/// — round-based cooldown notifications already nudge users into the
/// next session, and a second daily push felt noisy for an app meant
/// to be quiet.
///
/// The scheduler runs on every app background — when the user closes
/// Asma, we recompute "what's still pending" and queue up to 5 days'
/// worth of factual reminders. When they next foreground the app,
/// today's pending nudge is cancelled (no point pinging an already-
/// engaged user) and a fresh batch is queued on the next background.
///
/// The 5-day depth is the natural idle-pause: a user who never opens
/// the app for 5+ days stops getting reminders entirely, because no
/// background event runs to re-extend the batch. We never spam someone
/// who's clearly disengaged.
enum NudgeScheduler {
    /// How many days to schedule ahead in one batch. After this many
    /// days of inactivity the nudge stream naturally pauses.
    private static let scheduleDepthDays = 5

    /// Local time for the morning review push. Hard-coded; the user
    /// controls only the master on/off toggle.
    private static let morningHour = 9

    /// Recompute the pending nudges for the next `scheduleDepthDays`
    /// based on the current state. Wipes any previous nudges first so
    /// stale content never lingers — also cleans up leftover evening
    /// pushes scheduled by older builds. Cooldown push is on a different
    /// identifier prefix and isn't touched.
    static func refresh(progresses: [NameProgress], now: Date = .now) {
        NotificationsService.cancelAllNudges()

        guard UserDefaults.standard.bool(forKey: AppSettingsKey.notificationsEnabled) else { return }

        let counts = TodayPoolFactory.todayCounts(progresses: progresses, on: now)
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)

        for dayOffset in 0..<scheduleDepthDays {
            guard let dayStart = cal.date(byAdding: .day, value: dayOffset, to: todayStart) else { continue }

            // Morning review nudge — only meaningful when due reviews exist.
            // Heuristic: today's due count is a baseline; the actual queue
            // tomorrow may be larger as more names mature. We schedule
            // optimistically and the next background will refresh the
            // content with the real number.
            if counts.dueReviews > 0,
               let fireMorning = cal.date(bySettingHour: morningHour, minute: 0, second: 0, of: dayStart),
               fireMorning > now {
                NotificationsService.scheduleMorningNudge(at: fireMorning, dueCount: counts.dueReviews)
            }
        }
    }
}
