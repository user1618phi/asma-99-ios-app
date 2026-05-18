# Asma: 99 Names

iOS app for learning the 99 Beautiful Names of Allah (Asma'ul Husna). Free, offline-first, gamified.

- **Languages:** Russian, English, Kazakh (UI + content)
- **Min iOS:** 17.0
- **Stack:** SwiftUI, SwiftData, AVFoundation, Speech, CloudKit (optional sync, no login)
- **Data source:** [islamicapi.com](https://islamicapi.com) (used offline with permission)

## First-time setup

```bash
# 1. Install dev tools
brew install xcodegen jq

# 2. Configure secrets (copy and edit)
cp .env.example .env
# Put your ISLAMICAPI_KEY into .env

# 3. Generate the offline dataset (texts + audio)
./Scripts/fetch_dataset.sh

# 4. Generate the Xcode project
xcodegen generate

# 5. Open in Xcode
open Asma.xcodeproj
```

## Project layout

```
Asma/
├── App/           # AsmaApp.swift, root navigation, theme
├── Resources/     # names.json, audio/, assets, localized strings
├── Core/          # design system, persistence, audio, speech, haptics
├── Domain/        # models, repositories, gamification
└── Features/      # one folder per screen
Scripts/           # build-time data prep (NOT in app bundle)
project.yml        # XcodeGen spec
```

See `/Users/mustafa700/.claude/plans/ios-iridescent-piglet.md` for the full MVP plan.
# asma-99-ios-app
