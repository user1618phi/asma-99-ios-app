# Asma: 99 Names

iOS app for learning the 99 Names of Allah (Asma'ul Husna). Free, offline-first, no account required.

**Russian · English · Kazakh** — both interface and content · **iOS 17+** · SwiftUI

---

## What it does

Learning the 99 Names is a memorization task people usually approach by rereading a list. This app treats it as a retrieval problem instead — flashcards prepare a name, but it only counts as learned once you recall it correctly under test.

- **Flashcards → tests → spaced review**, driven by a state machine per name
- **Pronunciation practice** with on-device speech recognition
- **Gamification that never punishes** — HP as a soft currency, cooldowns instead of streak guilt
- **Ambient background sound** that yields to pronunciation playback and the speech recognizer
- **Fully offline** — the dataset (texts + audio) ships inside the app
- **Optional CloudKit sync** across devices, with no login

## Design principles

The learning engine is built on three ideas, and every threshold in the code traces back to one of them:

1. **Calm, lifelong practice — not a game to win.** Restrained tone. Never punish, never guilt, never manufacture urgency.
2. **Backed by cognitive science** — the testing effect (Roediger & Karpicke, 2006), the spacing effect (Cepeda et al., 2006), and Fogg's behavior model (2009).
3. **Flashcards prepare, tests prove.** Passive viewing never marks a name as learned.

The full logic is documented in [`docs/learning-engine.md`](docs/learning-engine.md) — state machine, HP economy, cooldowns and round counter.

## Stack

![Swift](https://img.shields.io/badge/Swift-F05138?style=flat-square&logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-0071E3?style=flat-square&logo=swift&logoColor=white)
![SwiftData](https://img.shields.io/badge/SwiftData-0071E3?style=flat-square)
![CloudKit](https://img.shields.io/badge/CloudKit-1BADF8?style=flat-square&logo=icloud&logoColor=white)

SwiftUI · SwiftData · AVFoundation · Speech · CloudKit · XcodeGen

## Setup

```bash
brew install xcodegen jq          # dev tools

cp .env.example .env              # then set ISLAMICAPI_KEY
./Scripts/fetch_dataset.sh        # build the offline dataset (texts + audio)

xcodegen generate                 # generate the Xcode project
open Asma.xcodeproj
```

Content comes from [islamicapi.com](https://islamicapi.com), fetched once at build time and bundled for offline use, with permission.

## Layout

```
Asma/
├── App/           # entry point, root navigation, theme
├── Core/          # design system, persistence, audio, speech, haptics, notifications
├── Domain/        # models, repositories, learning engine, gamification
├── Features/      # one folder per screen — 11 of them
└── Resources/     # names.json, audio, ambience, fonts, en/ru/kk localization
Scripts/           # build-time data prep (not shipped in the app bundle)
project.yml        # XcodeGen spec
```

## Docs

- [`docs/learning-engine.md`](docs/learning-engine.md) — flashcards, tests, rounds and HP
- [`docs/ambient-sound.md`](docs/ambient-sound.md) — ambience playback and how it coexists with speech
- [`docs/claude-design-brief.md`](docs/claude-design-brief.md) — visual design direction
