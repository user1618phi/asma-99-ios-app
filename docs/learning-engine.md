# Asma — Learning Engine Reference

**Audience**: AI models / engineers reading the codebase cold.
**Scope**: Complete logic, purpose, and function of the four interlocking systems — **Flashcards**, **Tests**, **Rounds** (cooldowns + round counter), and **HP** (the reward currency).
**Source of truth**: the Swift source in `Asma/Domain/Learning/`, `Asma/Domain/Gamification/`, `Asma/Features/{Flashcards,Tests,Practice}/`. This document **describes** what the code does; the code is canonical.

---

## 0. Philosophy (read this first)

Three principles drive every design decision below:

1. **Calm, lifelong practice — not a game to win.** The user is learning the 99 Names of Allah. Tone is editorial, restrained. Never punish. Never guilt. Never urgency.
2. **Backed by cognitive science.** Specifically:
   - *Testing effect* (Roediger & Karpicke, 2006) — retrieval beats rereading
   - *Spacing effect* (Cepeda et al., 2006) — distributed reviews beat massed practice
   - *Behavior model* (BJ Fogg, 2009) — Behavior = Motivation × Ability × Trigger
3. **Flashcards prepare, tests prove.** A name is "learned" only when the user retrieves it correctly under test — never from passive flashcard viewing.

Every formula and threshold below traces back to one of these principles.

---

## 1. The state machine (foundation for everything)

Each of the 99 names has a `NameProgress` row in SwiftData (`Asma/Core/Persistence/PersistenceModels.swift`). Every name occupies exactly one state:

```
.new (0) → .studying (1) → .confirmed (2) → .strengthening (3) → .mastered (4)
```

Defined in `Asma/Domain/Learning/ProgressEngine.swift` as `ReviewState`.

### Per-state semantics

| State | Meaning | How it got here | Counts toward "X/99 learned"? |
|---|---|---|---|
| `.new` | Never seen. Or lapsed back here after 3 wrong test answers in a row. | Default. Or reset from `.studying`/`.confirmed`. | No |
| `.studying` | Touched in flashcards at least once. Still aiming for "3 correct in a row" in tests. | First `markStudied()` call. | No |
| `.confirmed` | Hit 3-in-a-row in tests. About to enter the spaced ladder. | `consecutiveCorrect ≥ 3` while `.studying`. | **Yes** |
| `.strengthening` (box 1..4) | On the spaced-repetition ladder. Reviews at 1 → 3 → 7 → 14 → 30 days. | Pass first spaced review while `.confirmed`. | **Yes** |
| `.mastered` | Passed the final 30-day review. No more scheduled reviews. | Pass review while at box 4. | **Yes** |

### Per-name fields on `NameProgress`

```
reviewStateRaw: Int          // ReviewState enum value
consecutiveCorrect: Int      // 0..3, used in .studying/.confirmed
consecutiveWrong: Int        // 0..3, used in .studying/.confirmed
box: Int                     // 0 outside .strengthening; 1..4 inside
nextDueAt: Date?             // nil for .new/.studying/.mastered; set for .confirmed/.strengthening
lastStudiedAt: Date?         // last flashcard touch
firstStudiedAt: Date?        // first flashcard touch ever
lastReviewedAt: Date?        // any test or flashcard interaction
seenCount: Int               // increments once per calendar day touched
masteryLevel: Int            // 0..5 derived display field, kept in sync by ProgressEngine
lastQuizCorrect: Bool        // last test answer correctness
isFavorite: Bool             // user-toggled bookmark
pronunciationBestScore: Double  // 0..1, best recording score ever
```

### Single mutator: `ProgressEngine`

All state transitions go through three static methods. No other code modifies `NameProgress` directly.

#### `ProgressEngine.markStudied(_ p: NameProgress, on date: Date = .now)`

Called by `FlashcardsSessionView.advance()` for every card the user moves past in the `todaysPool` mode.

Effects:
- `.new` → `.studying`
- `firstStudiedAt ??= startOfDay(date)`
- `lastStudiedAt = date`
- `lastReviewedAt = date`
- `seenCount += 1` once per calendar day (idempotent intra-day)
- Recomputes `masteryLevel`
- **Does NOT** touch `consecutiveCorrect`, `box`, `nextDueAt`. Flashcards never affect mastery.

#### `ProgressEngine.recordAnswer(_ p: NameProgress, correct: Bool, on date: Date = .now) -> AnswerOutcome`

Called by `TestSessionView.submit()` for every test answer. Returns `AnswerOutcome` with three booleans:

```
becameConfirmedToday: Bool  // .studying → .confirmed transition just happened
becameMastered: Bool        // passed box 4 → .mastered just now
lapsed: Bool                // a lapse path was taken (any direction)
```

Branch matrix:

| Current state | Correct? | What happens |
|---|---|---|
| `.new`/`.studying` | ✓ | `consecutiveCorrect += 1`. If `≥ 3`: → `.confirmed`, reset counters, `nextDueAt = today + 1d`. |
| `.new`/`.studying` | ✗ | `consecutiveWrong += 1`. If `≥ 3`: → `.new`, clear `firstStudiedAt` (user must re-flashcard). |
| `.confirmed` (due) | ✓ | → `.strengthening`, `box = 1`, `nextDueAt = today + 3d`. |
| `.confirmed` (not due) | ✓ | No-op (don't shorten intervals by extra answers). |
| `.confirmed` | ✗ | `consecutiveWrong += 1`. If `≥ 3`: → `.new` (same lapse path as studying). |
| `.strengthening` (due) | ✓ | If `box ≥ 4`: → `.mastered`, `nextDueAt = nil`. Else `box += 1`, `nextDueAt = today + boxDays[box]`. |
| `.strengthening` (not due) | ✓ | No-op. |
| `.strengthening` | ✗ | `box = max(1, box - 1)`, `nextDueAt = tomorrow`. Single lapse step, not a full reset. |
| `.mastered` | ✗ | → `.strengthening`, `box = 4`, `nextDueAt = tomorrow`. One-step demotion, never to `.new`. |

`box` indexes `ReviewSchedule.boxDays = [1, 3, 7, 14, 30]`. `box=1` next review in 3 days (boxDays[1]), box=4 next review in 30 days.

Key invariant: **the lapse path is asymmetric**. A correct answer can move a name up by exactly one step. A wrong answer in `.strengthening`/`.mastered` moves it down by exactly one step. Three wrong-in-a-row in `.studying`/`.confirmed` is the only path back to `.new` — anything earned in `.strengthening` is partially protected (matches Anki / FSRS lapse philosophy).

#### `ProgressEngine.recomputeDisplayMastery(_ p)`

Keeps the legacy `masteryLevel` field (0..5) in sync with state + box. Used by Home next-up sort, FlashcardsLandingView "X/99 learned" counter, achievement thresholds. Mapping:

```
.new          → 0
.studying     → 1
.confirmed    → 3
.strengthening box=1 → 3
.strengthening box=2 → 4
.strengthening box=3 → 5
.strengthening box=4 → 5
.mastered     → 5
```

---

## 2. Flashcards

### Purpose

Introduce names to the user. **Preparation only — no mastery effect.** Flashcards are how a name enters the system; tests are how it leaves.

### Two modes

`FlashcardsSessionView` (`Asma/Features/Flashcards/FlashcardsSessionView.swift`) takes a `Mode` parameter:

```swift
enum Mode { case todaysPool, freePractice }
```

#### `.todaysPool` (the daily learning loop)

- **Queue**: lowest-mastery `flashcardCount` names from all 99 (`buildQueue` sorts by `masteryLevel ascending`).
- **On each card advance**: calls `ProgressEngine.markStudied(p)`. Names transition `.new → .studying`.
- **HP**: each "Know" tap awards 2 HP (`XPCalculator.flashcardBase`). "Don't know" awards 0 (it's not a mistake — just a re-queue signal within the session).
- **Daily goal bonus**: when `studiedTodayCount` reaches `flashcardCount` for the first time today, fires a **+10 HP daily goal bonus** (`XPCalculator.dailyGoalBonus`). Idempotent via XPEvent query (one per day, source `dailyGoal`).
- **End of session**: presents `RewardView(kind: .flashcard, hp: xpEarnedInSession, stats: [Reviewed, Time])`.

#### `.freePractice` (zikr-style browsing, unlocked after daily goal)

- **Queue**: all 99 names, shuffled.
- **On each card advance**: **does nothing to state**. No `markStudied`, no XP, no SwiftData write. Pure read-through.
- **End of session**: shows the existing minimal "session complete" finisher, no Reward screen.
- **Why**: lets the user contemplate all 99 names (dhikr-style) without inflating daily progress or polluting the spaced-repetition state.

### Daily goal cap

The Learn tab's session card (`FlashcardsLandingView.sessionCard`) flips state-based:

| State | Eyebrow | Title | Tap → |
|---|---|---|---|
| Fresh (no progress) | "Start" | "Begin with the first name" | `.session` push (`.todaysPool` mode) |
| `studyingToday` (goal not met) | "Begin a session" | "Resume today's session" | `.session` push |
| Goal hit (`readyToTest` / `cooldown` / `caughtUp`) | "Free Practice" | "Browse all 99 names" + subtitle "No progress tracked" | `.freePractice` push |

This is the **hard cap on the daily pace promise**: once you've done your N cards, the only flashcard path open is Free Practice, which won't add to the day's tally.

### Carryover (no punishment for skipping)

`TodayPoolFactory.eligibleToday` includes `.studying` names **unconditionally** (regardless of when `lastStudiedAt` was). So if the user studies 3 names on Day 1 with `consecutiveCorrect = 1` and doesn't return for a week, those 3 names are still in the test pool on Day 8 with their progress intact. Two more correct answers and they confirm.

The only exception: 3-wrong-in-a-row sends the name back to `.new` and clears `firstStudiedAt`, forcing the user to re-flashcard. That's not a punishment — it's the engine acknowledging "you've lost this one, let's reintroduce it."

---

## 3. Tests

### Purpose

Prove that a name has actually been retained. A name only counts as "learned" (state ≥ `.confirmed`) after the user correctly recalls it in tests.

### Four modes (`Asma/Features/Tests/TestModel.swift`, `enum TestMode`)

- `.nameToMeaning` — see Arabic + transliteration, pick the right English meaning
- `.meaningToName` — see the meaning, pick the right name
- `.audioToArabic` — hear the audio, pick the right Arabic spelling
- `.mix` — random per question, one of the three above

### Test pool composition (`TodayPoolFactory.eligibleToday`)

Today's eligible names are the union of:

1. **Due reviews** — `.confirmed` or `.strengthening` names with `nextDueAt ≤ now`. Sorted by oldest due first (so the user clears the most-overdue first).
2. **In-progress** — `.studying` names (all of them, with carryover semantics).
3. **New today** — `.new` names with `lastStudiedAt` today (a name never touched via flashcards never appears in a test).

`.mastered` names are excluded entirely (they have no `nextDueAt`).

Pool is capped at `testQuestionCount` (default 20, range 5–20) per session.

### Session flow (`TestSessionView`)

State variables:
```
session: TestSession?            // model holding queue + counters
selectedIndex: Int?              // current selected option (or nil)
didSubmit: Bool                  // false before Check, true after
finished: Bool                   // true after last advance
namesConfirmedThisSession: Int   // for Reward screen + XP rollup
namesMasteredThisSession: Int    // same
xpEarnedInSession: Int           // cumulative HP for Reward display
```

The `submit / advance` split (critical for correctness):

- **`submit(optionIndex:question:)`** runs when user taps **Check**:
  - Computes `correct = optionIndex == question.correctIndex`
  - Sets `didSubmit = true`
  - Plays haptic (success/error)
  - Calls `ProgressEngine.recordAnswer(...)` — updates the name's state, may trigger confirmed/mastered
  - If `becameConfirmedToday`: awards +15 HP (`nameConfirmedBonus`), bumps `namesConfirmedThisSession`
  - If `becameMastered`: awards +30 HP (`nameMasteredBonus`), bumps `namesMasteredThisSession`
  - Saves SwiftData
  - **Does NOT** touch the session queue. UI stays on the current question with check/X marks visible.

- **`advance()`** runs when user taps **Continue** (or swipes horizontally):
  - Calls `session.answer(optionIndex: selectedIndex)` — this mutates the queue (removes the answered question, re-queues if wrong, bumps cycle counter)
  - If `session.isComplete`: `finished = true`, calls `recordResult(s)`, shows `RewardView`
  - Else resets `selectedIndex = nil`, `didSubmit = false` for the next question

This split was the fix for an earlier ghost-answer bug where doing the queue mutation in `submit` would show the *next* question with the *old* selected-index highlighted. Don't change the order.

### Swipe-to-advance

`questionLayout` carries a `.simultaneousGesture(DragGesture(minimumDistance: 40))`. Horizontal swipe ≥ 60pt with vertical drift < 80pt triggers `advance()` — but **only if `didSubmit == true`**. Pre-Check swipes are silently ignored. Edge-swipe-back still works (system gesture wins on left-edge drags).

### Cycles and retry

`TestSession` tracks:

```
queue: [TestQuestion]            // remaining questions; wrong answers re-queue to back
firstCycleCorrect: Int           // accuracy numerator — counts only first-attempt wins
firstCycleSeen: Set<UUID>        // ensures firstCycleCorrect only counts each Q once
totalQuestions: Int              // = queue.count at session start (real, not requested)
cycle: Int                       // current pass number (1, 2, 3, ...)
currentCycleSize: Int            // questions in *this* pass
currentCycleAnswered: Int        // answers submitted in *this* pass
```

When the user answers wrong, the question goes to the back of the queue. When all questions in the current cycle have been answered AND the queue still has items, `cycle += 1`, `currentCycleSize = queue.count`, `currentCycleAnswered = 0`.

Display rules:
- Top progress counter: cycle 1 shows `01 / 06` (of the original); cycle 2+ shows `01 / 02` (of just the retries)
- Eyebrow: cycle 1 = "TEST · MEANING"; cycle 2+ = "RETRY ×2 · MEANING" (gold-tinted)
- The right-side `×N` badge was removed once eyebrow carried the cycle number

### TestAttempt persistence

Every completed test session creates a `TestAttempt` row:
```
date, testTypeRaw, firstCycleCorrect, totalQuestions, totalCycles,
xpEarned, namesConfirmed, namesMastered
```
Used by:
- Home `testsCompletedToday` (round counter) — `TestAttempt.date` filtered to today
- Stats weekly chart
- CooldownPolicy (counts today's attempts to determine next cooldown length)

---

## 4. Rounds & Cooldowns

### Round counter (Home CTA)

`testsCompletedToday + 1` shows on the Home CTA as "Round N" when state is `readyToTest`. Implementation in `HomeView`:

```
testAttempts.filter { startOfDay($0.date) == today }.count + 1
```

Resets to "Round 1" every calendar day. Climbs after each completed test. After Round 3 it just keeps counting ("Round 4 of 3" was rejected for awkwardness — bare "Round 4" reads fine as "doing extras").

The round counter is **purely a daily-progress signal**. It is the only number that visibly moves between tests when the user has the same pool (pool count stays put until names hit Confirmed).

### Cooldown policy (`Asma/Domain/Learning/CooldownPolicy.swift`)

After each completed test, the next round is locked for a progressive interval:

```
Round 1 done → 30 min wait → Round 2 unlocks
Round 2 done → 1 hour wait → Round 3 unlocks
Round 3 done → 2 hours wait → Round 4 unlocks
Round 4+ done → no wait (extras are free)
```

Rationale: matches spacing-effect science in miniature. Three crammed tests in 5 minutes don't build long-term memory (Cepeda 2006); spreading them gives real consolidation between sessions.

Function:
```swift
CooldownPolicy.cooldown(after roundsCompleted: Int) -> TimeInterval
CooldownPolicy.remaining(testAttempts: [TestAttempt], now: Date) -> TimeInterval
```

Both filter today's TestAttempts only — cooldown never carries through midnight.

### UI gating during cooldown

When `remaining > 0`:

- **Home CTA**: state becomes `.cooldown(remaining: TimeInterval, count: Int)`. CTA shows "Pause · Next round in 27m" with an hourglass icon and `.disabled(true)`. Button taps do nothing.
- **Tests landing**: the 4-mode list hides; a `cooldownBanner` replaces it (hourglass + countdown + explanation "Spacing rounds across the day is what makes memory stick"). Hidden mode list reappears the moment the timer expires.
- **Live countdown**: both screens use `TimelineView(.periodic(from: .now, by: 30))` so the displayed "X min" updates every 30 seconds and the state naturally transitions out of cooldown at zero.

### Cooldown notification

After every completed test, `TestSessionView.recordResult` calls `scheduleCooldownNotification()`:

1. Saves context to commit the new TestAttempt
2. Computes `eligibleAfter` via `TodayPoolFactory.eligibleToday`
3. If pool is empty (all names confirmed today) → calls `NotificationsService.cancelAll()` and returns. No misleading "Round N ready" push if there's nothing to do.
4. Otherwise calculates `roundsDone = testAttempts today count`
5. Calls `NotificationsService.scheduleCooldownEnd(at: now + cooldown(roundsDone), nextRoundNumber: roundsDone + 1)`

Notification identifier `asma.cooldown.nextRound` is stable, so each new test replaces the previous pending push. Content is baked at schedule time using current app language.

---

## 5. HP (the reward currency)

### Architecture (`Asma/Domain/Gamification/`)

Two files:

- **`XPCalculator.swift`** — pure functions, no side effects. Constants and formulas.
- **`XPService.swift`** — `award(amount:source:in:context)` — single mutator. Increments `UserStats.totalXP` AND writes an `XPEvent` audit row. Guards on `amount > 0`.

### Six sources (`enum XPSource`)

| Source | Amount | When | Where awarded |
|---|---|---|---|
| `.flashcardKnown` | 2 HP | Each "Know" tap in `.todaysPool` flashcards | `FlashcardsSessionView.advance` |
| `.dailyGoal` | 10 HP | Once/day when `studiedTodayCount` first reaches `flashcardCount` | `FlashcardsSessionView.awardDailyGoalIfHitNow` (XPEvent-query idempotent) |
| `.test` | `base × accuracy` (up to 100) | End of every test session | `TestSessionView.recordResult` |
| `.nameConfirmed` | 15 HP | Each name's `.studying → .confirmed` transition | `TestSessionView.submit` (via `outcome.becameConfirmedToday`) |
| `.nameMastered` | 30 HP | Each name passing the final 30-day box review | `TestSessionView.submit` (via `outcome.becameMastered`) |
| `.pronunciation` | 0 / 1 / 3 / 5 HP | After each pronunciation recording with score ≥ 0.35 | `PracticeView.beginRecording` |

### Formulas

**Test XP:**
```
base = 25 if totalQuestions < 5
       50 if totalQuestions in 5..<10
       100 if totalQuestions >= 10

testXP = round(base × firstCycleCorrect / totalQuestions)
```
So 8/10 first-try on a 10-question session = `100 × 0.8 = 80 HP`. Cycles (retries) don't add — only first-try counts.

**Pronunciation XP:**
```
score < 0.35  → 0 HP
score < 0.55  → 1 HP
score < 0.75  → 3 HP
score ≥ 0.75  → 5 HP
```
No daily cap. Repeated practice on the same name keeps awarding. The `pronunciationBestScore` field tracks max ever for achievements.

**Constants** (`XPCalculator`):
```swift
static let pronunciationBase = 5
static let flashcardBase = 2
static let dailyGoalBonus = 10
static let nameConfirmedBonus = 15
static let nameMasteredBonus = 30
```

### Career math (sanity check)

A user who eventually masters all 99 names earns roughly:
```
99 × 6 HP per-card (3 studies × 2 HP)        ≈   594
99 × 15 HP confirmed bonus                   ≈ 1 485
99 × 30 HP mastered bonus                    ≈ 2 970
~50 names × 5 HP pronunciation               ≈   250
55 daily-goal days × 10 HP                   ≈   550
3 tests/day × 55 days × ~40 HP avg session   ≈ 6 600
─────────────────────────────────────────────────
Total                                       ≈ 12 449 HP
```

The 100 HP and 1,000 HP achievement thresholds (`AchievementsView`) become reachable but meaningful.

### Per-session HP display

Each of the three reward-triggering views maintains a local `@State var xpEarnedInSession: Int` that's incremented at every `XPService.award` call inside the session. This drives the "+N HP" big gold number on the `RewardView`. The number is therefore the **real** total awarded that session, not a recomputation.

### Where HP is displayed

| Screen | Field | Source |
|---|---|---|
| Stats hero | `totalXP` | `UserStats.totalXP` |
| Stats weekly bar chart | per-day sum of `XPEvent` | aggregated `XPEvent.amount` by date |
| Achievements | Two thresholds (100, 1000 HP) | `stats.totalXP` boolean gates |
| Reward screens | `xpEarnedInSession` | session-local counter |

---

## 6. Reward screens (`Asma/Features/Reward/RewardView.swift`)

Full-screen post-action screen. Five variants:

| `RewardKind` | Trigger | Coin | Heading |
|---|---|---|---|
| `.flashcard` | `.todaysPool` session ends | gold | "Mashallah" |
| `.testPassed` | Test ends with first-cycle accuracy ≥ 60% | gold | "Mashallah" |
| `.testLow` | Test ends with first-cycle accuracy < 60% | silver (desaturated) | "Alhamdulillah" |
| `.practicePassed` | Pronunciation score ≥ 0.7 | gold | "Mashallah" |
| `.practiceLow` | Pronunciation score < 0.7 | silver | "Getting there" |

Layout (single VStack flow — must not regress to multiple overlapping VStacks):
```
Spacer 60pt
eyebrow                          // gold soft, 10.5pt tracking 2.4 uppercase
Spacer 24pt
heading                          // 56pt display heavy, lineLimit 2, minimumScaleFactor 0.55
Spacer 16pt
coin (220×220 Lottie)            // grayscale when isLowScore
Spacer 8pt
hpBlock                          // "+ NN HP" 84pt heavy gold + subtitle + optional "i" dot
Spacer(minLength: 24)            // flexible — pushes stats/CTA down
statsRow                         // 2 or 3 columns, optional highlight on one
Spacer 28pt
doneButton                       // gold pill + black arrow circle
Spacer 32pt
```

Close button is an overlay at top-right (38pt glass circle).

### Info sheet (for `.flashcard` / `.testPassed` / `.testLow`)

Tap the small "i" next to the subtitle → bottom modal slides up. Contains 3 numbered lines explaining the HP formula for that variant. Tap "Got it" or backdrop to dismiss. **Not shown** for practice rewards (score table is self-explanatory).

### Stats columns

| Variant | Stats |
|---|---|
| `.flashcard` | Reviewed (`seenInSession`), Time (`mm:ss` from `sessionStartedAt`) |
| `.testPassed`/`.testLow` | First try (`X/N`), Final (`N/N`), Accuracy (% — highlighted gold) |
| `.practicePassed`/`.practiceLow` | Accuracy, Score (highlighted gold), Complete |

---

## 7. Notifications (`Asma/Core/Notifications/`)

Three independent channels with distinct identifier prefixes:

| Channel | Identifier prefix | Schedule logic |
|---|---|---|
| Cooldown push | `asma.cooldown.nextRound` (stable, replaceable) | Per-session, set by `TestSessionView.recordResult` |
| Morning nudge | `asma.nudge.morning.<yyyy-MM-dd>` | Daily 09:00 if `dueReviews > 0`, set by `NudgeScheduler.refresh` |
| Evening nudge | `asma.nudge.evening.<yyyy-MM-dd>` | Daily 20:00 if anything pending, set by `NudgeScheduler.refresh` |

All gated on `AppSettingsKey.notificationsEnabled` (master toggle in Settings).

### Lifecycle (RootView)

```
.onChange(of: scenePhase) { _, new in
    .background → NudgeScheduler.refresh(progresses: ...)
    .active     → NotificationsService.cancelTodaysNudges()
}
```

`NudgeScheduler.refresh` queues a 5-day batch (depth chosen so 5+ days of inactivity self-terminates the nudge stream — no "we miss you" spam).

### Frequency rules

- **Cap**: max 2 nudges/day + 1 cooldown push when active. Total ≤ 3 push/day.
- **Quiet hours**: never schedule outside 08:00–22:00 (`NudgeScheduler` only schedules at 09:00 / 20:00, both inside the window).
- **Auto-cancel on foreground**: opening the app cancels today's still-pending nudges (don't ping a user who's already here).

### Content (3 languages)

All keys live in `Localizable.strings`:
- `notif.cooldown.title %lld` — "Round %lld is ready"
- `notif.cooldown.body` — "Your spacing pause is over — take today's next test"
- `nudge.morning.dueReviews %lld` — "%lld names ready for review"
- `nudge.evening.studyingToday %lld` — "%lld names to study today · 2 minutes"
- `nudge.evening.readyToTest %lld` — "%lld names ready to confirm"
- `nudge.title` — "Asma" (brand, not translated)

Content is baked at schedule time using `Bundle.loc(...)` — language at schedule time wins. Language change between schedule and fire is a known edge case (acceptable for MVP).

---

## 8. Day rollover (what resets vs persists)

Every midnight (local time):

| Resets daily (auto, via `startOfDay` filters) | Persists across days |
|---|---|
| `testsCompletedToday` → 0 (round counter) | `NameProgress.reviewStateRaw` |
| `studiedTodayCount` → 0 | `NameProgress.consecutiveCorrect/Wrong` |
| `CooldownPolicy.remaining` → 0 | `NameProgress.box` |
| Daily goal XP eligibility | `NameProgress.nextDueAt` |
| Evening/morning nudge slots (new ones for the day) | `UserStats.totalXP` (career sum) |
| | `XPEvent` history |
| | `TestAttempt` history |
| | `firstStudiedAt`, `lastStudiedAt`, `lastReviewedAt` |

`.confirmed` names with `nextDueAt = today + 1d` automatically appear in tomorrow's due-review pool. `.strengthening` names ride the 1/3/7/14/30 schedule. `.studying` names stay in pool indefinitely (carryover) until they either confirm or 3-wrong-in-a-row lapse them.

---

## 9. Home CTA states (`HomeView.SessionStatus`)

The single most-touched CTA. Five states with distinct copy and routing:

| State | Trigger | CTA copy | Tap → |
|---|---|---|---|
| `.fresh` | `introduced == 0` (no progress data) | "Begin · Start with your first name" | Push `FlashcardsRoute.session` |
| `.studyingToday(remaining: Int)` | `studiedToday < flashcardCount` | "Continue · Resume today's session · N more · ~M min" | Push `FlashcardsRoute.session` (flashcards) |
| `.cooldown(remaining: TimeInterval, count: Int)` | After a test, `CooldownPolicy.remaining > 0` | "Pause · Next round in 27m · Spacing strengthens memory" + hourglass | Disabled (tap is no-op) |
| `.readyToTest(count: Int)` | Goal hit, pool > 0, no cooldown | "Today · Round N · Confirm N names" | `switchTab(.tests)` |
| `.caughtUp` | Goal hit, pool empty | "Done · Today's session complete · Browse the ninety-nine" + checkmark | `switchTab(.learn)` (browse mode) |

Priority order: `fresh > studyingToday > cooldown > readyToTest > caughtUp`. The order matters — `studyingToday` deliberately wins over `cooldown` if the user hasn't done cards yet (cooldown only blocks tests, not study).

---

## 10. "Learned" count (single source of truth)

`X / 99 learned` appears on Home, Learn, Profile, Stats. **All four use the same definition:**
```
learnedCount = progresses.filter { $0.reviewStateRaw >= ReviewState.confirmed.rawValue }.count
```

Includes `.confirmed`, `.strengthening (box 1..4)`, `.mastered`. Excludes `.new` and `.studying`. The masteryLevel field is a derived mirror of this — `masteryLevel >= 3` is equivalent.

This was a real inconsistency at one point — Home used `seenCount > 0` (anyone touched ever) while Learn used `state ≥ confirmed`. Standardized on the latter; never regress.

---

## 11. Settings (`AppSettingsKey`)

User-facing knobs persisted via `@AppStorage`:

```
testQuestionCount    // 5..20, default 20 — cap on test session length
flashcardCount       // 1..10, default 3 — daily new-names goal
notificationsEnabled // false default — master toggle for all push
```

`testDefault = 20` is intentionally high — it should only bite for mature users with 30+ due reviews. New users on Day 1 always see exactly what they studied.

Removed in earlier iterations (do not re-add): `reminderHour`, `reminderMinute`, `dailyNewNamesGoal` (all dead code).

---

## 12. File map (quick navigation)

```
Asma/Core/Persistence/
  PersistenceModels.swift          // NameProgress, UserStats, TestAttempt, XPEvent
  PersistenceController.swift      // SwiftData container + ModelContext.progress(for:)

Asma/Core/Notifications/
  NotificationsService.swift       // 3 channels, requestAuthorization, cancel methods
  NudgeScheduler.swift             // 5-day batch scheduler called from RootView scenePhase

Asma/Domain/Learning/
  ReviewState (in ProgressEngine.swift)  // .new/.studying/.confirmed/.strengthening/.mastered
  ProgressEngine.swift             // markStudied, recordAnswer, recomputeDisplayMastery
  ReviewSchedule.swift             // boxDays = [1,3,7,14,30], confirmTarget = 3, lapseTarget = 3
  TodayPoolFactory.swift           // eligibleToday, todayCounts
  CooldownPolicy.swift             // cooldown(after:), remaining(testAttempts:)

Asma/Domain/Gamification/
  XPCalculator.swift               // constants + formulas + XPSource enum
  XPService.swift                  // award(amount, source, in: context)

Asma/Features/Flashcards/
  FlashcardsLandingView.swift      // session CTA + names list + favorites
  FlashcardsSessionView.swift      // Mode { .todaysPool, .freePractice }, advance, awardDailyGoalIfHitNow

Asma/Features/Tests/
  TestModel.swift                  // TestSession, TestQuestion, TestSessionFactory
  TestsLandingView.swift           // 4 mode chips, cooldown banner, today summary eyebrow
  TestSessionView.swift            // submit/advance, scheduleCooldownNotification, swipe gesture

Asma/Features/Reward/
  RewardView.swift                 // 5 variants + LottieCoinView + RewardInfoSheet

Asma/Features/Practice/
  PracticeView.swift               // SpeechScorer wrapper, fullScreenCover for reward

Asma/Features/Home/
  HomeView.swift                   // SessionStatus, smart CTA, navigationDestination for FlashcardsRoute
```

---

## 13. Glossary

| Term | Meaning |
|---|---|
| **HP** | Experience points / reward currency. Single accumulating number. |
| **Round** | One completed test session. Per-day counter. |
| **Cycle** | One pass through the queue within a single test session. Cycle 2+ = retrying wrong answers. |
| **Daily goal** | `flashcardCount` setting. Number of new names to study per day. |
| **Today's pool** | Names eligible for testing today (new + carryover studying + due reviews). |
| **Carryover** | `.studying` names from previous days, still in pool, progress preserved. |
| **Confirmed** | State a name reaches after 3 correct test answers in a row. First "learned" milestone. |
| **Strengthening** | The 4-box spaced-repetition ladder after confirmed. |
| **Mastered** | Passed the final 30-day box review. Out of active pool. |
| **Lapse** | Going backwards in the state machine (3 wrong in studying/confirmed → new; 1 wrong in strengthening → one box down; 1 wrong in mastered → strengthening box 4). |
| **Cooldown** | Forced wait between rounds (30m / 1h / 2h). |
| **Free Practice** | Browse-all-99 mode that bypasses daily goal cap and doesn't write any state. |
| **Nudge** | Daily notification (morning 09:00 or evening 20:00). |

---

## 14. Invariants (must never break)

1. Flashcards never change mastery state. Only `ProgressEngine.markStudied` runs in flashcards.
2. Tests never silently mutate the queue inside `submit` — only `advance` does.
3. Cooldown push schedules only fire when the pool will actually have items.
4. The "X / 99 learned" counter is `state >= .confirmed` across all four screens.
5. Free Practice writes nothing to `NameProgress`, awards no XP, doesn't bump `studiedTodayCount`.
6. `daily goal XP bonus` fires exactly once per calendar day (idempotent via XPEvent query).
7. Notifications respect the master toggle — `NotificationsEnabled = false` means no schedule, ever.
8. `.studying` names persist in pool across days (carryover). Only 3-wrong-in-a-row sends them back to `.new`.
9. `.mastered` names are out of the active pool until/unless they lapse.
10. `TestSession.totalQuestions` is the actual queue size at construction, not the requested `testQuestionCount`.

Breaking any of these is a regression. The conversation history that built this engine treats them as load-bearing.
