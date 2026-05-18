import Foundation
import UserNotifications

/// All local notification scheduling for Asma.
///
/// Two independent channels, each with its own identifier prefix so
/// cancel logic stays clean:
///
///   • `asma.cooldown.nextRound` — fires when the inter-round cooldown
///     (`CooldownPolicy`) expires. Scheduled inside an active test
///     session, lives ≤ 2 hours.
///   • `asma.nudge.morning.<yyyy-MM-dd>` — 09:00 each day if due-reviews
///     are pending. Day-stamped so a 5-day batch never collides.
///
/// Evening nudge (`asma.nudge.evening.*`) was retired — `cancelAllNudges`
/// still sweeps that prefix so leftover requests from older builds get
/// silently dropped on the next background refresh.
///
/// Everything is gated on the master toggle
/// `AppSettingsKey.notificationsEnabled`. Flipping it off in Settings
/// wipes every pending request via `cancelAll()`.
enum NotificationsService {
    private static let cooldownId = "asma.cooldown.nextRound"
    private static let morningNudgePrefix = "asma.nudge.morning."
    /// Legacy prefix kept solely so `cancelAllNudges` can mop up any
    /// pending evening pushes scheduled by older builds. Nothing new
    /// is scheduled with it.
    private static let legacyEveningNudgePrefix = "asma.nudge.evening."

    // MARK: - Authorization

    /// Ask the system for `.alert + .sound + .badge` authorisation.
    /// Returns whether the user granted (or had already granted) it.
    /// Called only from the Settings toggle so the prompt is always tied
    /// to an explicit user gesture — the iOS HIG-correct flow.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - Cooldown push (per-session)

    /// Schedule (or replace) the "next round ready" push at `fireDate`.
    /// `nextRoundNumber` is baked into the localized title NOW, using
    /// whichever language `Bundle.loc(...)` currently resolves — that's
    /// the language the user picked in-app, not the system locale.
    static func scheduleCooldownEnd(at fireDate: Date, nextRoundNumber: Int) {
        let enabled = UserDefaults.standard.bool(forKey: AppSettingsKey.notificationsEnabled)
        guard enabled else { return }

        let delay = max(1, fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)

        let content = UNMutableNotificationContent()
        content.title = Bundle.loc("notif.cooldown.title %lld", nextRoundNumber)
        content.body = Bundle.loc("notif.cooldown.body")
        content.sound = .default

        let request = UNNotificationRequest(identifier: cooldownId, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        // Stable identifier ensures every fresh test attempt replaces
        // the previous pending request (no duplicates piling up).
        center.removePendingNotificationRequests(withIdentifiers: [cooldownId])
        center.add(request)
    }

    // MARK: - Daily nudges

    /// Morning 09:00 push: "X names ready for review". Day-stamped so a
    /// batch covering several days never collides on the same identifier.
    static func scheduleMorningNudge(at fireDate: Date, dueCount: Int) {
        guard UserDefaults.standard.bool(forKey: AppSettingsKey.notificationsEnabled) else { return }
        guard dueCount > 0 else { return }
        guard fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = Bundle.loc("nudge.title")
        content.body = Bundle.loc("nudge.morning.dueReviews %lld", dueCount)
        content.sound = .default

        let identifier = morningNudgePrefix + Self.dayKey(for: fireDate)
        scheduleAt(date: fireDate, identifier: identifier, content: content)
    }

    /// Wipe every pending nudge (current morning batch + any leftover
    /// evening pushes scheduled by older builds). Cooldown push is on
    /// a different prefix and survives.
    static func cancelAllNudges() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(morningNudgePrefix) || $0.hasPrefix(legacyEveningNudgePrefix) }
            guard !ids.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Cancel just today's nudge — call from app foreground so a user
    /// who's actively in the session doesn't get pinged later.
    static func cancelTodaysNudges() {
        let center = UNUserNotificationCenter.current()
        let key = Self.dayKey(for: .now)
        // Also clear the legacy evening identifier so any leftover from
        // an older build doesn't escape today's cleanup.
        let todayIds = [morningNudgePrefix + key, legacyEveningNudgePrefix + key]
        center.removePendingNotificationRequests(withIdentifiers: todayIds)
    }

    /// Drop everything pending (cooldown + all nudges). Used when the
    /// master toggle goes off.
    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Helpers

    private static func scheduleAt(date: Date, identifier: String, content: UNNotificationContent) {
        // Use a calendar trigger so iOS schedules at the precise local
        // time the user expects, regardless of when the app was last
        // foregrounded.
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.add(request)
    }

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dayKey(for date: Date) -> String {
        dayKeyFormatter.string(from: date)
    }
}
