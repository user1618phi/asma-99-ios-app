import SwiftUI
import SwiftData
import UserNotifications

@main
struct AsmaApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("hasFinishedOnboarding") private var hasFinishedOnboarding = false
    @AppStorage("asma.userName") private var userName = ""
    @AppStorage(AppSettingsKey.notificationsEnabled) private var notificationsEnabled = false
    @State private var localization = LocalizationManager.shared

    /// Whether the "Welcome back" splash should still be on screen for this
    /// cold launch. We only ever set this to `true` on first appearance for
    /// returning users — onboarding-complete users see the splash exactly
    /// once per launch, never on every navigation back to the root.
    @State private var showWelcomeBack = false

    init() {
        LocalizationManager.bootstrap()
        AppAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                AsmaColor.bgCream
                    .ignoresSafeArea(.all)

                Group {
                    if !hasFinishedOnboarding {
                        OnboardingView(onFinish: { hasFinishedOnboarding = true })
                    } else if showWelcomeBack {
                        WelcomeBackView(userName: userName) {
                            withAnimation(.easeOut(duration: 0.4)) {
                                showWelcomeBack = false
                            }
                        }
                        .transition(.opacity)
                    } else {
                        RootView()
                    }
                }
            }
            .tint(AsmaColor.brandGold)
            .environment(localization)
            .environment(\.locale, Locale(identifier: localization.current.rawValue))
            .preferredColorScheme(.dark)
            .onAppear {
                // Show the splash only on cold-launch for returning users.
                // First-run users finish onboarding into RootView directly.
                if hasFinishedOnboarding {
                    showWelcomeBack = true
                }
                // Reconcile our in-app notifications switch with iOS on
                // cold launch — covers the case where the user revoked
                // permission in iOS Settings while the app was killed.
                Task { await syncNotificationsWithSystem() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Also reconcile every time the app comes back to the
                // foreground (user could revoke permission in iOS Settings
                // and then swipe back to Asma).
                if newPhase == .active {
                    Task { await syncNotificationsWithSystem() }
                }
            }
        }
        .modelContainer(PersistenceController.modelContainer)
    }

    /// Force `notificationsEnabled` (our master toggle that gates every
    /// scheduled push) to OFF if iOS has revoked authorisation. We never
    /// auto-flip it ON — that would bypass the user's choice on the
    /// Profile/Settings toggle and the onboarding "Not now" decision.
    private func syncNotificationsWithSystem() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let systemEnabled =
            settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
        await MainActor.run {
            if notificationsEnabled && !systemEnabled {
                notificationsEnabled = false
                NotificationsService.cancelAll()
            }
        }
    }
}
