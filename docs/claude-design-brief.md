# Asma — Brief for Claude Design: Expand Onboarding

## What I'm asking you to do

Asma is an iOS app for learning the 99 Names of Allah. The current onboarding has 4 pages — Hero, Method, Pace, Name. It explains *what* the app is, but **not how it actually works**: tests, rewards (HP), spaced repetition, notifications, pronunciation practice.

**I need you to add 4–6 new onboarding pages between the Method page and the Pace page** that explain the app's mechanics in a way **anyone, even a child, would understand at first read**. Short text. Beautiful. One idea per page. The existing editorial dark/gold style should be preserved.

Below is everything you need to know about how the app works, so you can decide what to put on each page and how to phrase it.

---

## Existing design language (preserve this)

- **Theme**: dark `#000000` background with editorial gold `#C9A86A` accents
- **Typography**: Inter Tight (display + sans), Amiri (Arabic), JetBrains Mono (numbers)
- **Tone**: calm, restrained, no emoji, no exclamation marks, no guilt-tripping
- **Voice**: factual and specific, not emotional
- **Layout**: lots of white space, big editorial headings, eyebrows in gold tracking 2.4 uppercase
- **Inspiration**: Apple News, Headspace — **not** Duolingo

Existing onboarding pages already follow this. New pages must match.

---

## Existing onboarding (don't replace, add to)

1. **Hero**: "Asma · The Ninety-nine Names · Quietly learned, one breath at a time."
2. **Method**: "Three minutes a day" with 3 micro-steps:
   - "Meet a name" — encounter one name at a time
   - "Reflect, then reveal" — flip card to see meaning
   - "Test what stays" — short rounds keep what you learned
3. **Pace selection**: 1/3/5/10 names per day (chips labeled Easy/Gentle/Steady/Focused)
4. **Name entry**: ask user's name

The new pages go **between Method (2) and Pace (3)**, expanding on the mechanics.

---

## How the app actually works

### 1. Flashcards (the "study" half)

- **Purpose**: introduce a name. Pure preparation — no scoring, no mistakes.
- **Daily flow**: user picks a pace (3, 5, 10 names/day). Each day they open Learn and tap the session card. The app shows them N flashcards drawn from names they haven't mastered yet.
- **Card UI**: Arabic name + audio button → tap to reveal transliteration + meaning → tap "Know" or "Don't know" → next card.
- **"Don't know" is not a mistake** — it just tells the app "show me this one again sooner."
- **Daily goal cap**: once the user has done N cards today (= their pace), the session CTA flips to **Free Practice** (see below). The app refuses to add more new names — that's how the pace promise is kept.

### 2. Free Practice (unlocked after daily goal)

- Once the day's pace is hit, the Learn screen replaces "Resume today's session" with **"Free Practice · Browse all 99 names · No progress tracked"**.
- Opens a flashcard session through **all 99 names** (shuffled), with no state changes, no XP, no daily-goal effect. Pure browsing — for contemplation or quick refresh.
- Inspired by the Islamic practice of *dhikr* — going through the names slowly without an agenda.

### 3. Tests (the "prove it" half)

- **Trigger**: only names the user has studied via flashcards can appear in tests.
- **4 modes**: Name → Meaning, Meaning → Name, Audio → Arabic, Mix.
- **Question UI**: prompt + 4 options. Tap one → tap Check → see right/wrong feedback → tap Continue (or swipe).
- **Wrong answers come back**: the test loops until every name has been answered correctly at least once (multiple "cycles").
- **The "3-correct-in-a-row" rule**: a name only becomes "Confirmed" after the user answers it correctly **3 times in a row across tests** (3 separate test sessions, ideally). One test alone won't confirm it.
- **Lapse**: 3 wrong in a row sends the name back to studying (needs to be re-flashcarded).

### 4. Rounds and cooldowns (the spacing between tests)

The science says cramming 3 quick tests back-to-back is much less effective than spacing them across the day. So the app enforces a **cooldown between rounds**:

- **Round 1**: anytime
- **Round 2**: 30 minutes after Round 1
- **Round 3**: 1 hour after Round 2
- **Round 4+**: 2 hours between rounds (no further restriction)

During a cooldown, the Tests screen shows a **calm hourglass card** with a live countdown ("Next round in 27m") and an explanation: "Spacing rounds across the day is what makes memory stick." The 4 test modes are hidden until the timer expires.

The number shown on Home as "Round N" climbs after every completed test, so the user can see progress. It resets to "Round 1" every morning.

### 5. Spaced Repetition Ladder (after a name is Confirmed)

Once a name reaches Confirmed, it stops needing daily attention. Instead it enters a 5-step **review ladder**:

- Day 1 after Confirmed → appears in test
- Day 3 after that → appears again
- Day 7 → again
- Day 14 → again
- Day 30 → final review

Pass all 5 reviews → name becomes **Mastered**. Mastered names disappear from the active test pool forever (unless the user fails one in a future review — then it drops one box and re-enters the ladder).

This is the "spaced repetition" that the Method page hints at. It's based on the spacing effect from cognitive science (the same principle Anki uses, simplified for 99 items).

### 6. Test pool — what shows up today

When the user opens Tests, the pool today contains:
- **New names** studied via flashcards today
- **Carryover names** — anything still in "studying" from previous days (their progress is preserved; no punishment for taking a break)
- **Due reviews** — names whose spaced-repetition slot has arrived (days 1, 3, 7, 14, 30 after confirmed)

The user sees a small line at the top: **"Today · 5 new · 2 to review"** — total honest count.

### 7. Carryover philosophy

Critical UX principle: **the app never punishes the user for skipping a day**. If you studied 3 names yesterday and didn't finish confirming them, they wait for you today with their progress intact (e.g., 1 correct in a row preserved — you need 2 more). The same applies to forgetting for a week or longer.

The only exception: 3 wrong-in-a-row sends a name back to "needs re-studying". That's the system saying "you've lost this one, let's reintroduce it" — not a punishment, just honest about the memory.

### 8. HP (the reward currency)

HP is a single accumulating number the user sees in their stats. It comes from 6 sources:

| Source | Amount |
|---|---|
| Flashcard "Know" tap | 2 HP per tap |
| **Daily goal hit bonus** | +10 HP (once per day) |
| Test session | up to 100 HP (proportional to first-try accuracy and session size) |
| **Name reaches Confirmed** | +15 HP per name (when 3-in-a-row achieved) |
| **Name reaches Mastered** | +30 HP per name (after the 30-day final review) |
| Pronunciation recording | 0/1/3/5 HP depending on score |

A user who learns all 99 names to Mastered earns **roughly 12,000 HP** over ~55 days. The 100 and 1,000 HP achievement thresholds become meaningful early milestones.

### 9. Reward screens (after every session)

After flashcards, tests, and practice, a full-screen **Reward** appears:
- Big editorial heading: **"Mashallah"** (passing), **"Alhamdulillah"** (low test score), or **"Getting there"** (low pronunciation)
- Animated gold coin (Lottie)
- **+N HP** in huge gold numbers — the exact amount earned this session
- Three stat tiles (e.g., First try / Final / Accuracy for tests)
- For tests/flashcards: a small "i" icon reveals an **info sheet** with 3 numbered lines explaining how the HP was calculated. (Practice doesn't show the info sheet — the score speaks for itself.)
- A single gold pill "Done" button to dismiss.

### 10. Pronunciation Practice

- From the name detail page, the user can tap "Practice" to recite the Arabic name aloud.
- The app records up to 5 seconds, scores three sub-metrics (Accuracy, Clarity, Completeness) and gives an overall score 0–100%.
- After scoring, a Reward screen pops up:
  - Score ≥ 70% → **Practice passed** (gold coin, "Mashallah")
  - Score < 70% → **Practice low** (silver coin, "Getting there")
- HP awarded:
  - Score < 35% → 0 HP
  - 35–55% → 1 HP
  - 55–75% → 3 HP
  - ≥ 75% → 5 HP
- No daily limit — the user can practice the same name multiple times. Repetition is encouraged.

### 11. Notifications (calm, factual, opt-in)

Three channels, all gated on a single Settings toggle:

| Channel | When | Example text |
|---|---|---|
| **Cooldown push** | After a test, when the inter-round wait expires | "Round 2 is ready · Your spacing pause is over — take today's next test." |
| **Morning nudge** | 09:00 if any spaced-review names are due | "3 names ready for review" |
| **Evening nudge** | 20:00 if today's plan isn't done | "3 names to study today · 2 minutes" *or* "5 names ready to confirm" |

Rules:
- **Maximum 2 nudges per day** (morning + evening), plus the cooldown push when active.
- **Quiet hours**: nothing fires between 22:00 and 08:00.
- **Opens cancel pending**: if the user is already in the app today, the day's nudges quietly cancel.
- **5-day depth**: the scheduler queues 5 days at a time. After 5 days of no activity, the nudges naturally stop. No "we miss you" spam.
- **Tone**: factual, specific, no emoji, no exclamation marks, no streak-loss language.

The Settings screen has a single **Notifications** toggle. Turning it on prompts iOS permission once; turning it off cancels every pending push.

### 12. Home screen — what the user sees first

The Home tab is the entry point. It always shows:
- A name of the day (the next name the user should work on)
- A progress bar "X / 99" (names confirmed)
- A "Day N" counter (unique days the user has touched the app)
- **One smart CTA card** that changes by state:
  - First open → "Begin · Start with your first name"
  - Studying today → "Continue today's session · 2 more · ~1 min"
  - Pool ready to test → "Round 3 · Confirm 3 names" → opens Tests tab
  - Cooldown active → "Pause · Next round in 27m" (button disabled)
  - All done → "Today's session complete · Browse the ninety-nine" → opens Learn for free browsing

### 13. Languages

The app is fully localized in **English, Russian, Kazakh**. The user picks their language at any time from Profile / Language. All reward screens, notifications, and onboarding text must work in all three.

---

## Suggested new onboarding pages (your call to refine)

Here's a rough scaffold of the 4–6 pages I think would work, slotted between **Method** (page 2) and **Pace** (currently page 3). You're free to merge, split, or rearrange — the goal is to explain everything above in the simplest possible terms.

### Suggested order

1. **Page 3 — Flashcards**
   - Headline: "Cards to meet the names"
   - One sentence: "Flip a card. See the meaning. Tap Know or Don't know."
   - Visual: small flashcard illustration

2. **Page 4 — Tests**
   - Headline: "Tests to make them stay"
   - One sentence: "Pick the right meaning three times in a row · a name is yours."

3. **Page 5 — Rest between rounds**
   - Headline: "A pause between rounds"
   - One sentence: "30 minutes · 1 hour · 2 hours · Memory grows in the spaces between."
   - Visual: small hourglass

4. **Page 6 — Spaced repetition**
   - Headline: "Names you've learned come back"
   - One sentence: "On day 1 · 3 · 7 · 14 · 30 — quick reviews keep names with you for years."

5. **Page 7 — HP (the gentle reward)**
   - Headline: "A small reward for every step"
   - One sentence: "Cards, tests, recitation — each earns HP. Watch the numbers add up."

6. **Page 8 — Notifications (opt-in)**
   - Headline: "Quiet reminders, if you want them"
   - One sentence: "Mornings and evenings · only when something's waiting. Off by default."

7. **Page 9 — Pronunciation practice**
   - Headline: "Say each name out loud"
   - One sentence: "Tap the microphone · the app listens and scores your recitation gently."

Then the existing **Pace** and **Name** pages follow.

### Page design tokens

- Eyebrow: gold soft (`#C9A86A` at 72% opacity), 10.5pt Inter Tight medium, tracking 2.4, uppercase
- Headline: 56pt Inter Tight heavy, tracking -2, white (`#F4EFE3`)
- Body text: 14–15pt Inter Tight medium, dimmed white (`#F4EFE3` at 55%)
- Optional small illustration: line-only, gold accents, no fill (matches existing icon style)
- Centered or left-aligned (existing pages are left-aligned)
- Page indicators: existing dot pattern at the bottom

### Anti-patterns (please don't do these)

- No emoji
- No exclamation marks
- No "Don't break your streak" language
- No fake urgency ("only X days left!")
- No long paragraphs — one idea, one sentence, one big headline
- No screenshots of the app (it's an onboarding moment, not a tutorial)
- No quizzes or interactions during onboarding — pure read-through

---

## Localization for new pages

Every headline, eyebrow, and body line must work in English, Russian, and Kazakh. Keep sentences short so all three languages fit comfortably in the same layout. Russian and Kazakh tend to be ~20% longer than English; allow for that.

If you write copy, give me all three languages so I can drop them into the existing `Localizable.strings` files.

---

## Output you can give me back

For each new page:
1. Eyebrow text (3 languages)
2. Headline (3 languages)
3. Body / supporting line (3 languages)
4. Optional: small line-illustration spec or SF Symbol suggestion

Layout-wise, follow the existing Method page exactly. The pages should feel like a continuation of that visual rhythm, not a separate section.

---

## One last note

The whole app is built on the principle that learning the 99 Names is a **calm, lifelong practice — not a game to win**. Every system above is designed to honor that: no punishment for skipping, no guilt for being slow, no shame for forgetting. Reminders are gentle. Numbers are honest. The path is long but never rushed.

The new onboarding pages should set that expectation from the start.
