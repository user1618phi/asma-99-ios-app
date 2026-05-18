import SwiftUI
import SwiftData

enum RootTab: Hashable {
    case home, learn, tests, profile
}

struct RootView: View {
    @State private var tab: RootTab = .home
    @Environment(LocalizationManager.self) private var localization
    @Environment(\.scenePhase) private var scenePhase
    /// Used by `NudgeScheduler.refresh` when the app moves to the
    /// background — we recompute the next few days of reminders from a
    /// fresh snapshot of the user's progress.
    @Query private var progresses: [NameProgress]

    var body: some View {
        TabView(selection: $tab) {
            HomeView(switchTab: { tab = $0 })
                .tabItem {
                    Label("tab.home", systemImage: "house.fill")
                }
                .tag(RootTab.home)

            FlashcardsLandingView()
                .tabItem {
                    Label("tab.learn", systemImage: "rectangle.on.rectangle")
                }
                .tag(RootTab.learn)

            TestsLandingView()
                .tabItem {
                    Label("tab.tests", systemImage: "list.bullet.rectangle")
                }
                .tag(RootTab.tests)

            ProfileView()
                .tabItem {
                    Label("tab.profile", systemImage: "person.crop.circle")
                }
                .tag(RootTab.profile)
        }
        .tint(AsmaColor.brandGold)
        .background(AsmaColor.bgCream.ignoresSafeArea(.all))
        // Force the entire tab tree to re-instantiate when the user picks a
        // different language. SwiftUI's @Observable wiring re-renders only
        // the views that *read* `localization.current`; pushed/deep views
        // that don't observe it would otherwise keep stale strings. Tagging
        // the TabView's identity by language guarantees every leaf re-resolves
        // its localized text on a language change.
        .id(localization.current)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // App closing — schedule the next few days of nudges so
                // the user gets timely reminders even when away.
                NudgeScheduler.refresh(progresses: progresses)
            case .active:
                // User opened the app — silence today's pending nudges
                // (they're already engaged; no need to ping later).
                NotificationsService.cancelTodaysNudges()
                // Returning to foreground resumes the ambience the user
                // had picked (or stays silent if that's what they chose).
                AmbientSoundPlayer.shared.start()
            default:
                break
            }
        }
        .onAppear {
            // First time the tabbed UI mounts after onboarding — kick the
            // ambient loop. Idempotent on re-appearances.
            AmbientSoundPlayer.shared.start()
        }
    }
}
