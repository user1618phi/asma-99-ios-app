# Asma — Ambient Background Sound Reference

**Audience**: AI models / engineers reading the codebase cold.
**Scope**: Complete logic and rationale for the looping background ambience system — what plays, when it plays, when it pauses, how the UI exposes it, and how it coexists with name pronunciation playback and the speech recognizer.
**Source of truth**: `Asma/Core/Audio/AmbientSoundPlayer.swift`, `Asma/Core/Audio/AmbientSound.swift`, `Asma/Core/DesignSystem/AmbientSoundButton.swift`, plus the integration sites listed in §10. This document **describes** what the code does; the code is canonical.

---

## 0. Why this feature exists (read first)

Asma is a calm, editorial app for learning the 99 Names of Allah. The product brief explicitly states the experience should feel "calm, lifelong practice — not a game to win." A continuous low-volume ambience (birds, rain, waves, thunderstorm) makes the dark/gold UI feel **inhabited** rather than sterile, and matches the contemplative tone the rest of the app already enforces (editorial typography, no exclamation marks, no streak language, no urgency).

Three constraints fall out of that goal:

1. **It must be quiet.** Volume is fixed at `0.25` of unity so it never competes with the recited Arabic name or the user's own voice during pronunciation practice.
2. **It must defer to learning audio.** When the app plays a name pronunciation, ambience pauses. When the user records their voice, ambience pauses. The user should always hear the name and themselves cleanly.
3. **It must never punish.** No "complete onboarding to unlock sounds," no streak language tied to listening, no notification telling you ambient sound is off. The user can silence it with one tap and forget it exists.

Default sound is **`birds`**. It starts only after onboarding finishes (onboarding stays silent so the read-through feel is preserved) and persists across launches via `UserDefaults`.

---

## 1. The four sounds and the enum

Source: [`Asma/Core/Audio/AmbientSound.swift`](../Asma/Core/Audio/AmbientSound.swift)

```swift
enum AmbientSound: String, CaseIterable, Identifiable, Sendable {
    case birds
    case rain
    case waves
    case thunderstorm
    case silent
}
```

`.silent` is a **first-class case**, not the absence of a selection. The user explicitly chose "no sound." This matters because:

- The picker UI always renders 5 rows; "Silent" is one of them and gets the gold checkmark when selected.
- The persistence layer stores `"silent"` like any other choice — there is no "no value saved" branch to special-case.
- The pause/resume machinery treats `.silent` as a sentinel: `current == .silent` short-circuits every play path, so background pauses are no-ops.

### Resource bundling

The four mp3 files live at:

```
Asma/Resources/Ambience/birds.mp3
Asma/Resources/Ambience/rain.mp3
Asma/Resources/Ambience/waves.mp3
Asma/Resources/Ambience/thunderstorm.mp3
```

They are bundled because [`project.yml`](../project.yml) declares `resources: [Asma/Resources]` as a folder reference. XcodeGen regenerates `Asma.xcodeproj` and picks up anything inside that tree automatically — there is no per-file `pbxproj` entry to maintain. If you add a fifth sound, you only need to: drop the mp3 in `Asma/Resources/Ambience/`, add a case to `AmbientSound`, add three localization strings, and run `xcodegen`.

`AmbientSound.fileName` returns the case's `rawValue` (e.g. `"birds"`), looked up via `Bundle.main.url(forResource: name, withExtension: "mp3")`. `.silent.fileName` returns `nil` and short-circuits the loader.

### SF Symbols

Each case maps to one symbol used by both the top-right pill and the popover row:

| Case | SF Symbol |
|---|---|
| `.birds` | `bird.fill` |
| `.rain` | `cloud.rain.fill` |
| `.waves` | `water.waves` |
| `.thunderstorm` | `cloud.bolt.rain.fill` |
| `.silent` | `speaker.slash.fill` |

All five exist on iOS 17 (the project's deployment target — see `project.yml`).

### Localization

Each case maps to a key `ambient.<rawValue>`. The six keys live at the end of each `Localizable.strings`:

| Key | en | ru | kk |
|---|---|---|---|
| `ambient.title` | Sound | Звук | Дыбыс |
| `ambient.birds` | Birds | Птицы | Құстар |
| `ambient.rain` | Rain | Дождь | Жаңбыр |
| `ambient.waves` | Waves | Волны | Толқындар |
| `ambient.thunderstorm` | Thunderstorm | Гроза | Найзағай |
| `ambient.silent` | Silent | Тишина | Үнсіз |

`ambient.title` is currently unused in code but is preserved for any future "Sound" section header in Settings.

---

## 2. `AmbientSoundPlayer` — the engine

Source: [`Asma/Core/Audio/AmbientSoundPlayer.swift`](../Asma/Core/Audio/AmbientSoundPlayer.swift)

A `@MainActor @Observable` singleton: `AmbientSoundPlayer.shared`. Owns exactly one `AVAudioPlayer` configured to loop infinitely at low volume.

### Public surface

```swift
static let shared: AmbientSoundPlayer

// Observable state (drives the UI)
var current: AmbientSound          // currently selected
var pauseReasons: Set<PauseReason> // active pause requests

// Imperative API
func start()                       // begin / resume the loop (idempotent)
func setSound(_ sound: AmbientSound)
func pause(reason: PauseReason)
func resume(reason: PauseReason)
```

### `init()` — restoring user choice

```swift
if let raw = UserDefaults.standard.string(forKey: AppSettingsKey.ambientSound),
   let stored = AmbientSound(rawValue: raw) {
    current = stored
}
```

Read once on first access of `.shared`. If the user has never set a value (first launch after onboarding) `current` stays at its initialised default of `.birds`. No audio plays yet — that's deferred to `start()`.

### `start()` — boot sequence

Called from [`RootView.onAppear`](../Asma/App/RootView.swift) and on every `scenePhase == .active` transition. It must be idempotent because both fire repeatedly.

```swift
func start() {
    activatePlaybackSession()
    if !hasStarted {
        hasStarted = true
        UserDefaults.standard.set(current.rawValue, forKey: AppSettingsKey.ambientSound)
    }
    guard pauseReasons.isEmpty else { return }
    loadAndPlay(current)
}
```

Two behaviours matter:

- On the very first invocation, the persisted value (if any) is *re-written* to `UserDefaults`. This is intentional: it pins the default `.birds` for first-time users so subsequent reads are deterministic, and it future-proofs against migration scenarios where the key format might change.
- If anything is currently asking for a pause (Practice screen, etc.), `start()` configures the session but does **not** force playback. The next `resume()` is what actually plays.

### `setSound(_ sound)` — switching ambience

Called by [`AmbientSoundButton`](../Asma/Core/DesignSystem/AmbientSoundButton.swift) when the user taps a popover row.

```swift
func setSound(_ sound: AmbientSound) {
    guard sound != current else { return }
    current = sound
    UserDefaults.standard.set(sound.rawValue, forKey: AppSettingsKey.ambientSound)

    if sound == .silent {
        fadeOut { [weak self] in
            self?.player?.stop()
            self?.player = nil
        }
        return
    }

    if pauseReasons.isEmpty {
        activatePlaybackSession()
        loadAndPlay(sound)
    }
}
```

- Same-sound tap is a no-op — no audible glitch from re-loading the same file.
- `.silent` fades out, then nils the player. Selecting any other sound later will create a fresh `AVAudioPlayer`.
- Non-silent switches with active pause reasons just update `current` + persist — no audio change. When the pause clears, `resume()` reads `current` and loads the new file.

### `pause(reason:)` / `resume(reason:)` — the coordination contract

This is the most important part of the file. **Read carefully.**

```swift
private(set) var pauseReasons: Set<PauseReason> = []

func pause(reason: PauseReason) {
    let wasPlaying = pauseReasons.isEmpty
    pauseReasons.insert(reason)
    if wasPlaying {
        fadeOut { [weak self] in self?.player?.pause() }
    }
}

func resume(reason: PauseReason) {
    guard pauseReasons.contains(reason) else { return }
    pauseReasons.remove(reason)
    guard pauseReasons.isEmpty else { return }
    guard current != .silent else { return }
    activatePlaybackSession()
    if player == nil {
        loadAndPlay(current)
    } else {
        player?.play()
        fadeIn()
    }
}
```

**The mental model:** `pauseReasons` is a *set of independent owners that each want silence*. The loop is audible if and only if the set is empty AND `current != .silent`.

- `pause` transitions empty → non-empty: fade out, then `AVAudioPlayer.pause()`.
- `pause` from non-empty → still non-empty: no audible change; just records the new owner.
- `resume` removes the owner; if the set is still non-empty, no audible change.
- `resume` transitions non-empty → empty: re-activate session, then play.

**Why a `Set` and not a counter or a Bool?** Because the pause owners are independent. A `Bool` would race: PracticeView pauses on entry, SpeechScorer pauses again when the mic starts; if SpeechScorer's stop-recording handler then sets the Bool to false, ambience would un-pause while PracticeView is still on screen. A `Set` keyed by owner makes each `pause`/`resume` pair self-balancing: SpeechScorer's `.recording` resume can never accidentally cancel PracticeView's `.practice` pause.

### `PauseReason` cases — who pauses, when

```swift
enum PauseReason: Hashable {
    case pronunciation  // single-shot name audio from AudioPlayer
    case practice       // entire PracticeView lifetime
    case recording      // SpeechScorer's mic session
}
```

The three cases were chosen to give each subsystem its own bit in the set. Critically, `.practice` and `.recording` are distinct: PracticeView holds `.practice` for as long as the user is on the screen (potentially many seconds, including reading the result), while SpeechScorer holds `.recording` only during the ~5-second mic capture window. They overlap when the user taps the mic — both are in the set; the loop stays paused; when recording ends, only `.recording` is removed and ambience stays off because `.practice` is still present.

If you ever add a new caller, give it its own case. Reusing an existing case is a bug — see "Why we use distinct reasons" in §7.

### The fade machinery

```swift
private let targetVolume: Float = 0.25
private func fadeIn(duration: TimeInterval = 0.5) { ... }
private func fadeOut(duration: TimeInterval = 0.3, onComplete: ...) { ... }
```

Both fades are driven by a `Timer` scheduled at 30 Hz (`steps = duration * 30`). On each tick, `player.volume` is linearly interpolated between start and end. When the last step fires, the timer invalidates itself and runs the optional completion block.

- Fade-in is 500 ms (gentle reappearance — never jarring).
- Fade-out is 300 ms (snappy enough that pronunciation audio doesn't fight the ambience for the first few hundred ms).
- `fadeTimer` is `invalidate()`-ed at the top of `runFade` so back-to-back pause/resume cycles don't stack timers.

The timer block hops to `@MainActor` because the player and timer are MainActor-isolated (the whole class is `@MainActor`).

### `activatePlaybackSession()` — the audio session dance

```swift
private func activatePlaybackSession() {
    try? AVAudioSession.sharedInstance().setCategory(
        .playback, mode: .default, options: [.mixWithOthers]
    )
    try? AVAudioSession.sharedInstance().setActive(true, options: [])
}
```

**This is called on every `start()`, `resume()`, and non-silent `setSound()` — not once at boot.** That's deliberate.

iOS audio sessions are process-wide. `AudioPlayer` (name pronunciation) sets the category to `.playback` mode `.spokenAudio` while a name is playing and then `setActive(false)` when done. `SpeechScorer` sets the category to `.record` mode `.measurement` for recording and `setActive(false)` afterwards. Both leave the session in a state where our ambient `AVAudioPlayer` cannot produce sound on its own.

Earlier in the implementation, `activatePlaybackSession` was called only once and gated by a `hasConfiguredSession` flag. The result was a **silent ambience after the first pronunciation playback or any Practice session** — exactly the bug a user reported. The fix is to treat session activation as cheap and call it every time we want sound to play.

`.mixWithOthers` is what allows our ambient loop to coexist with the pronunciation `AudioPlayer` (which uses `.duckOthers` to suppress *other apps*, e.g. Spotify, but does not affect our same-session player). Without `.mixWithOthers`, the category swap to `.spokenAudio` would interrupt our loop hard.

---

## 3. The pause-coordination integration sites

There are exactly **three** places that call `pause`/`resume`. Each owns its own `PauseReason`.

### 3.1 `AudioPlayer` — name pronunciation

Source: [`Asma/Core/Audio/AudioPlayer.swift`](../Asma/Core/Audio/AudioPlayer.swift)

`AudioPlayer.shared.play(file:)` is invoked from name detail / flashcards / tests to play the recited Arabic name (e.g. `ar-Rahman.mp3`). It uses `.pronunciation`:

```swift
func play(file: String) {
    AmbientSoundPlayer.shared.pause(reason: .pronunciation)
    try AVAudioSession.sharedInstance().setCategory(
        .playback, mode: .spokenAudio,
        options: [.duckOthers, .mixWithOthers]
    )
    // ... start AVAudioPlayer ...
}

func stop() { ... ; AmbientSoundPlayer.shared.resume(reason: .pronunciation) }
func audioPlayerDidFinishPlaying(...) { ... ; AmbientSoundPlayer.shared.resume(reason: .pronunciation) }
```

The `pause` fires **before** `setCategory` is called, so by the time iOS swaps the session into spokenAudio mode the ambient player is already gracefully fading out. Resume fires on every exit path: explicit stop, natural finish, and the catch block on session-setup failure.

`.duckOthers` plus `.mixWithOthers` is the magic incantation that lets the pronunciation player (a) duck external apps like Spotify, while (b) allowing our own ambient player to keep its `.playback` category alive in the same process. Without `.mixWithOthers`, this category swap would hard-interrupt our ambient `AVAudioPlayer`.

### 3.2 `SpeechScorer` — microphone recording

Source: [`Asma/Core/Speech/SpeechScorer.swift`](../Asma/Core/Speech/SpeechScorer.swift)

The recognizer captures up to 5 seconds of audio for Practice. `.record` category is incompatible with any concurrent playback, so we pause hard:

```swift
private func startSession() throws {
    AmbientSoundPlayer.shared.pause(reason: .recording)
    try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
    try session.setActive(true, ...)
}

private func stopSession() {
    // ... tear down audio engine ...
    try? AVAudioSession.sharedInstance().setActive(false, ...)
    AmbientSoundPlayer.shared.resume(reason: .recording)
}
```

The resume here is what eventually re-activates the playback session (because `resume()` calls `activatePlaybackSession()` before playing). Don't be tempted to merge `.recording` into `.practice` — see §7.

### 3.3 `PracticeView` — the screen lifetime

Source: [`Asma/Features/Practice/PracticeView.swift`](../Asma/Features/Practice/PracticeView.swift)

```swift
.onAppear { AmbientSoundPlayer.shared.pause(reason: .practice) }
.onDisappear { AmbientSoundPlayer.shared.resume(reason: .practice) }
```

The user is on the Practice screen for several seconds beyond the actual recording (reading results, deciding whether to try again, dismissing the reward sheet). The screen-lifetime pause guarantees the ambience is off for that entire window, not just during the ~5 seconds the mic is hot. This makes the silence feel deliberate ("I'm focused on my pronunciation") rather than glitchy ("why did the rain come back for 2 seconds in the middle of my session?").

### 3.4 Reward screens — *no* pause

Source: [`Asma/Features/Reward/RewardView.swift`](../Asma/Features/Reward/RewardView.swift)

An earlier iteration paused on `RewardView.onAppear` and resumed on disappear. The product owner explicitly reversed that decision: ambience should continue during Mashallah / Alhamdulillah / Getting there sheets. The reward is calm, not a moment of silence — keeping the rain or birds running underneath reinforces the "this is a continuous experience" tone the brief calls for.

There is therefore **no `.reward` case in `PauseReason`** and no pause/resume calls in RewardView. If you ever add one, remember to also re-add the enum case.

---

## 4. The UI — top-right pill on every main tab

Source: [`Asma/Core/DesignSystem/AmbientSoundButton.swift`](../Asma/Core/DesignSystem/AmbientSoundButton.swift)

A 38pt circular glass button matching the existing `CircleGlassButton` ([`FlashcardsSessionView.swift:431`](../Asma/Features/Flashcards/FlashcardsSessionView.swift#L431)) — `.ultraThinMaterial` background, hairline white border, gold icon (or dim white when `.silent` is selected). Tapping it opens a SwiftUI `.popover` with `.presentationCompactAdaptation(.popover)` so it renders as a popover on iPhone too.

The popover lists all five `AmbientSound` cases. Each row is a `Label`-style line: SF Symbol on the left (gold or dim), localized label, gold checkmark on the trailing edge when the row is the current selection. Tapping a row calls `AmbientSoundPlayer.shared.setSound(...)` and dismisses the popover. A 1pt divider between rows (left-padded past the icon column) gives editorial separation.

### Why `@State` + `AmbientSoundPlayer.shared`

```swift
@State private var ambient = AmbientSoundPlayer.shared
```

`AmbientSoundPlayer` is `@Observable`, so reading `ambient.current` inside `body` re-renders the icon and popover automatically when `setSound` fires from any view. `@State` is used (not `@Bindable`) because we don't need two-way binding; we just need a stable reference for the lifetime of the view. Since `.shared` is a singleton, re-instantiating `@State` on view reload still points to the same instance.

The view also tags itself with `.id(localization.current)` so a language switch tears down and rebuilds the popover content, forcing every `Bundle.loc(...)` to re-resolve.

### Where the pill is rendered

| Tab | File | Mounting pattern |
|---|---|---|
| Home | [`HomeView.swift`](../Asma/Features/Home/HomeView.swift) | `.overlay(alignment: .topTrailing)` on the body's ZStack |
| Tests | [`TestsLandingView.swift`](../Asma/Features/Tests/TestsLandingView.swift) | `.overlay(alignment: .topTrailing)` on the NavigationStack body |
| Profile | [`ProfileView.swift`](../Asma/Features/Profile/ProfileView.swift) | Sibling of the ScrollView inside an outer `ZStack(alignment: .topTrailing)` |
| Learn | [`FlashcardsLandingView.swift`](../Asma/Features/Flashcards/FlashcardsLandingView.swift) | Inside the existing top-right `HStack` next to the search button |
| Flashcards session | [`FlashcardsSessionView.swift`](../Asma/Features/Flashcards/FlashcardsSessionView.swift) | Replaces the old bookmark icon in the session top bar |

All sites use `.padding(.top, 8).padding(.trailing, 18)` so the pill sits in the identical position across tabs. **Profile uses the sibling-in-ZStack pattern instead of `.overlay`** because the body contains a `ScrollView`; an `.overlay` on a parent that wraps a ScrollView was reported to visually scroll under some conditions, and the sibling pattern is unambiguously pinned.

The pill is intentionally **not** shown on nested / immersive screens: name detail, test sessions, the reward sheet, the language picker. Those are focus moments where extra chrome would be visual noise.

---

## 5. Boot sequence — when does ambience start?

The full path from cold launch to first audible birds:

1. `AsmaApp` mounts the `WindowGroup`. If `hasFinishedOnboarding == false`, `OnboardingView` is shown. **Ambience does not play.**
2. User finishes onboarding (taps "Begin" on screen 8). `hasFinishedOnboarding = true`.
3. `WelcomeBackView` shows on next cold launch only — not on the immediate transition from onboarding to root. Ambience still doesn't play during the welcome splash.
4. `RootView` is mounted. `.onAppear` fires:
   ```swift
   .onAppear { AmbientSoundPlayer.shared.start() }
   ```
5. `start()` activates the playback session, persists `current.rawValue` (`"birds"`) into `UserDefaults`, and calls `loadAndPlay(.birds)`. The player fades in over 500 ms.

On every subsequent cold launch the splash shows first, then `RootView.onAppear` fires and `start()` reads the persisted value (`"birds"` or whatever the user picked) and resumes from there.

`scenePhase` transitions to `.active` (returning from background) also re-invoke `start()`. iOS pauses the app's `AVAudioPlayer` when the app backgrounds; calling `start()` on resume re-activates the session and re-plays. Because `start()` is idempotent, calling it multiple times causes no glitches: the `loadAndPlay` path checks `existing.url == url` and just calls `play()` on the already-loaded player.

---

## 6. Persistence

One key in `UserDefaults`, declared in [`AppSettings.swift`](../Asma/Features/Settings/AppSettings.swift):

```swift
static let ambientSound = "settings.ambientSound"   // stores AmbientSound.rawValue
```

Stored as the raw string of the case (`"birds"`, `"rain"`, ...). No migration needed for new cases — if a stored value doesn't parse into the current enum, the init fallback is the default `.birds`. If a user downgrades from a future build that added a new case, they silently revert to birds; no crash.

---

## 7. Subtle behaviour notes and past bugs

These are the things that look easy to "simplify" and aren't.

### Why we use distinct PauseReasons for SpeechScorer and PracticeView

Early implementation used `.practice` for *both* PracticeView's screen-lifetime pause **and** SpeechScorer's recording-window pause. Because `pauseReasons` is a `Set` (not a counter), this meant SpeechScorer's `resume(.practice)` at end-of-recording would remove `.practice` from the set even though PracticeView still wanted it paused — ambience un-paused mid-screen. Then PracticeView's `onDisappear → resume(.practice)` would find the reason already removed and be a no-op.

Splitting into `.practice` and `.recording` makes each owner's pause/resume self-balancing.

### Why session activation is *not* one-shot

The `hasConfiguredSession` flag was removed for a reason. `AudioPlayer` and `SpeechScorer` both mutate the shared `AVAudioSession` and `setActive(false)` it on exit. Our ambient player needs the session in `.playback` `.mixWithOthers` and **active** to make sound. We pay the cost of re-activating it every `start`/`resume`/`setSound` because anything less leaves the player muted after the first pronunciation playback or after any Practice session.

### Why `.mixWithOthers` on the pronunciation player

`AudioPlayer.play` sets the session to `.playback` mode `.spokenAudio` with `[.duckOthers, .mixWithOthers]`. The `.mixWithOthers` is what allows our ambient `AVAudioPlayer` to keep running on the same session while the pronunciation plays. Without it, the category swap to `.spokenAudio` would terminate the ambient player immediately, defeating the purpose of the fade-pause coordination.

`.duckOthers` is preserved because external apps (Spotify, podcast players) *should* be ducked so the user clearly hears the name being recited. Our own ambient player is unaffected by `.duckOthers` because they share the same audio session.

### Why we removed the favorites bookmark from FlashcardsSessionView

The flashcards session previously had a `bookmark` icon top-right that toggled `NameProgress.isFavorite`. Product decision: the ambient pill needed to be in that slot for consistency with the other landing screens, and favorites are still settable from the name detail view (where there's more room). The `toggleFavorite` helper was removed when the button was replaced — it had no other callers.

### Why onboarding stays silent

The 8-screen onboarding is a read-through moment. Sound starts only when `RootView` mounts (i.e. after the user has tapped "Begin"). This matches the brief's "calm read-through" tone for onboarding and gives the ambience an introduction moment — the user transitions from silence into the app's atmospheric layer.

### Why reward screens don't pause

The Mashallah / Alhamdulillah / Getting there sheets are part of the continuous calm experience. Pausing the rain or birds for the few seconds of reward would feel glitchy and "ceremonial" in a way the rest of the app avoids. Product decision: keep playing. There is therefore no `.reward` case in the enum and no `onAppear`/`onDisappear` hook in `RewardView`.

---

## 8. Volume and the "never loud" rule

`targetVolume = 0.25` in [`AmbientSoundPlayer.swift`](../Asma/Core/Audio/AmbientSoundPlayer.swift). Tuned by the product owner; do not raise without explicit request. If the user expressed that the ambience competes with the name audio, the correct response is to *lower* this value, not to add a volume slider — every knob added to the UI dilutes the calm, single-purpose tone of the app.

There is intentionally **no per-sound volume override.** All four soundscapes were either chosen or normalised at edit time so they sit at roughly the same perceived loudness at 0.25.

---

## 9. Looping

```swift
p.numberOfLoops = -1
```

`AVAudioPlayer` with `numberOfLoops = -1` loops indefinitely without re-loading the file, so the loop point is gapless (any audible seam is a property of the mp3, not the playback). The four current mp3s are nature recordings that loop cleanly enough that the seam is imperceptible at low volume.

---

## 10. File map

```
Asma/
├── Core/
│   ├── Audio/
│   │   ├── AmbientSound.swift            ← the enum
│   │   ├── AmbientSoundPlayer.swift      ← the singleton player + pause coordinator
│   │   └── AudioPlayer.swift             ← pronunciation player; calls pause/resume(.pronunciation)
│   ├── Speech/
│   │   └── SpeechScorer.swift            ← mic capture; calls pause/resume(.recording)
│   └── DesignSystem/
│       └── AmbientSoundButton.swift      ← top-right pill + popover
├── App/
│   └── RootView.swift                    ← calls .shared.start() on appear + scene .active
├── Features/
│   ├── Home/HomeView.swift               ← mounts pill via .overlay(alignment: .topTrailing)
│   ├── Tests/TestsLandingView.swift      ← mounts pill via .overlay
│   ├── Profile/ProfileView.swift         ← mounts pill via ZStack sibling
│   ├── Flashcards/
│   │   ├── FlashcardsLandingView.swift   ← mounts pill in existing top-right HStack
│   │   └── FlashcardsSessionView.swift   ← pill replaces the old bookmark icon
│   ├── Practice/PracticeView.swift       ← .onAppear pause(.practice) / .onDisappear resume
│   └── Settings/AppSettings.swift        ← declares the `ambientSound` UserDefaults key
└── Resources/
    ├── Ambience/                         ← the four mp3s (XcodeGen picks them up as folder ref)
    │   ├── birds.mp3
    │   ├── rain.mp3
    │   ├── waves.mp3
    │   └── thunderstorm.mp3
    └── {en,ru,kk}.lproj/Localizable.strings  ← 6 keys per locale
```

---

## 11. End-to-end verification (re-run after any change to this subsystem)

1. **First launch after onboarding** — complete onboarding; birds should fade in within 500 ms of `RootView` appearing. Top-right of Home shows the bird glass circle.
2. **Switch sound** — tap the pill on Home → popover → tap Rain → smooth handoff to rain.mp3, popover dismisses, icon becomes a rain cloud. Confirm the same pill appears top-right on Learn, Tests, Profile, and inside the flashcards session.
3. **Select Silent** — tap pill → Silent → fade-out; pill icon switches to speaker-slash in dim white. Reopen popover: Silent has the gold checkmark.
4. **Persist across launches** — kill the app, relaunch through the splash. Last-selected sound resumes (or silence stays silence).
5. **Pronunciation pause** — pick Rain. Open a name detail, tap the audio button. Rain pauses → name plays cleanly → rain resumes within a frame of completion.
6. **Practice pause** — pick Birds. Enter Practice on any name. Birds pauses on entry → record voice → see the score → exit Practice → birds resumes. Record twice in a row — ambience should stay off for the entire screen lifetime, not flicker on between recordings.
7. **Reward keeps playing** — finish a flashcard session. Reward sheet appears → ambience stays at normal volume → dismiss → still playing. Same for test reward and practice reward.
8. **Onboarding silence** — wipe the app, run again. Onboarding's 8 pages have no ambience. Only after tapping "Begin" on the final page does birds start.
9. **Backgrounding** — switch to another app; ambience stops (iOS pauses the AVAudioPlayer). Return to Asma; `RootView.onAppear` fires `start()` and ambience resumes.
10. **Language change** — change language in Profile → re-open the ambient popover → labels render in the new language.

These tests are mandatory on a **physical device** after any change to `AmbientSoundPlayer`, `AudioPlayer`, or `SpeechScorer`. The simulator's audio-session behaviour is unreliable; race conditions between three concurrent players only manifest at runtime.
