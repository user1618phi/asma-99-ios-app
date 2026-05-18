import Foundation

/// User-tunable knobs persisted in UserDefaults. Values are the *displayed*
/// numbers — i.e. what the user sees on the Onboarding pace chips and
/// Profile/Settings goal rows is exactly what's stored.
enum AppSettingsKey {
    static let testQuestionCount = "settings.testQuestionCount"
    static let flashcardCount = "settings.flashcardCount"

    /// Cap on how many questions appear in a single test session. The
    /// actual session length is `min(testDefault, eligibleNames.count)`,
    /// so on Day 1 with a few studied names the user sees exactly what
    /// they studied. The default is high (20) on purpose — it should only
    /// bite for mature users with a backlog of due reviews; new users
    /// should never feel the cap chopping off names they just studied.
    static let testDefault = 20
    static let testMin = 5
    static let testMax = 20

    /// 3 names/day is the onboarding "Gentle" default — picked because it
    /// matches the implied promise of a 3-minute daily practice.
    static let flashcardDefault = 3
    static let flashcardMin = 1
    static let flashcardMax = 10

    /// Master switch for all local notifications. When false, every
    /// scheduled push is silently dropped and pending ones are wiped.
    /// Default is false — iOS pattern is explicit opt-in via the Settings
    /// toggle (which prompts system authorisation on its first ON).
    static let notificationsEnabled = "settings.notificationsEnabled"

    /// Selected background ambience. Stores `AmbientSound.rawValue`.
    /// Default on first launch after onboarding is `birds`.
    static let ambientSound = "settings.ambientSound"
}
