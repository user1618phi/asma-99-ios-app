import Foundation
import SwiftData

@Model
final class NameProgress {
    @Attribute(.unique) var number: Int
    var seenCount: Int
    var pronunciationBestScore: Double
    var lastQuizCorrect: Bool

    /// Derived display field kept in sync by `ProgressEngine.recomputeDisplayMastery`.
    /// Range 0..5. Existing UI (HomeView next-up sort, FlashcardsLanding
    /// "X / 99" learned counter) reads this; the engine writes it as a mirror
    /// of `reviewStateRaw` + `box`.
    var masteryLevel: Int
    var isFavorite: Bool
    var lastReviewedAt: Date?

    // MARK: - Learning engine (see ProgressEngine / ReviewSchedule)

    /// `ReviewState` raw — new / studying / confirmed / strengthening / mastered.
    var reviewStateRaw: Int
    /// Consecutive correct test answers since last failure. Caps at
    /// `ReviewSchedule.confirmTarget`, then resets when the state transitions.
    var consecutiveCorrect: Int
    /// Consecutive wrong test answers since last success. Caps at
    /// `ReviewSchedule.lapseTarget`, then resets at the transition.
    var consecutiveWrong: Int
    /// Strengthening ladder position 1..4. Zero outside of `.strengthening`.
    var box: Int
    /// When this name should next appear in a test. Nil for `.new` /
    /// `.studying` (those are pulled in by `lastStudiedAt == today` instead)
    /// and for `.mastered` (graduates out of the review pool).
    var nextDueAt: Date?
    /// First flashcard touch ever (resets to nil on a lapse back to `.new`).
    var firstStudiedAt: Date?
    /// Last flashcard touch — drives the "studied today" eligibility check
    /// inside `TodayPoolFactory`.
    var lastStudiedAt: Date?

    init(
        number: Int,
        seenCount: Int = 0,
        pronunciationBestScore: Double = 0,
        lastQuizCorrect: Bool = false,
        masteryLevel: Int = 0,
        isFavorite: Bool = false,
        lastReviewedAt: Date? = nil,
        reviewStateRaw: Int = 0,
        consecutiveCorrect: Int = 0,
        consecutiveWrong: Int = 0,
        box: Int = 0,
        nextDueAt: Date? = nil,
        firstStudiedAt: Date? = nil,
        lastStudiedAt: Date? = nil
    ) {
        self.number = number
        self.seenCount = seenCount
        self.pronunciationBestScore = pronunciationBestScore
        self.lastQuizCorrect = lastQuizCorrect
        self.masteryLevel = masteryLevel
        self.isFavorite = isFavorite
        self.lastReviewedAt = lastReviewedAt
        self.reviewStateRaw = reviewStateRaw
        self.consecutiveCorrect = consecutiveCorrect
        self.consecutiveWrong = consecutiveWrong
        self.box = box
        self.nextDueAt = nextDueAt
        self.firstStudiedAt = firstStudiedAt
        self.lastStudiedAt = lastStudiedAt
    }
}

@Model
final class UserStats {
    var totalXP: Int
    var preferredLanguageRaw: String
    var dailyReminderEnabled: Bool
    var displayName: String

    init(
        totalXP: Int = 0,
        preferredLanguage: AppLanguage = .detected(),
        dailyReminderEnabled: Bool = false,
        displayName: String = ""
    ) {
        self.totalXP = totalXP
        self.preferredLanguageRaw = preferredLanguage.rawValue
        self.dailyReminderEnabled = dailyReminderEnabled
        self.displayName = displayName
    }

    var preferredLanguage: AppLanguage {
        get { AppLanguage(rawValue: preferredLanguageRaw) ?? .en }
        set { preferredLanguageRaw = newValue.rawValue }
    }
}

@Model
final class TestAttempt {
    var date: Date
    var testTypeRaw: String
    var firstCycleCorrect: Int
    var totalQuestions: Int
    var totalCycles: Int
    var xpEarned: Int
    /// How many names crossed `.studying → .confirmed` in this session.
    var namesConfirmed: Int
    /// How many names graduated to `.mastered` in this session.
    var namesMastered: Int

    init(
        date: Date,
        testType: String,
        firstCycleCorrect: Int,
        totalQuestions: Int,
        totalCycles: Int,
        xpEarned: Int,
        namesConfirmed: Int = 0,
        namesMastered: Int = 0
    ) {
        self.date = date
        self.testTypeRaw = testType
        self.firstCycleCorrect = firstCycleCorrect
        self.totalQuestions = totalQuestions
        self.totalCycles = totalCycles
        self.xpEarned = xpEarned
        self.namesConfirmed = namesConfirmed
        self.namesMastered = namesMastered
    }
}

@Model
final class XPEvent {
    var date: Date
    var amount: Int
    var sourceRaw: String

    init(date: Date, amount: Int, source: String) {
        self.date = date
        self.amount = amount
        self.sourceRaw = source
    }
}
