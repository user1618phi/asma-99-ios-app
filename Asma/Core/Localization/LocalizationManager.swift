import Foundation

@Observable
final class LocalizationManager {
    static let shared = LocalizationManager()
    static let userDefaultsKey = "asma.preferredLanguage"

    /// The current UI language. Changing it persists the choice to
    /// `UserDefaults` (which `Bundle.loc(_:)` reads on every call), and
    /// the published property invalidates SwiftUI views observing the
    /// manager so the next render pulls strings in the new language.
    var current: AppLanguage {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: Self.userDefaultsKey)
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.userDefaultsKey)
        let initial = saved.flatMap { AppLanguage(rawValue: $0) } ?? .detected()
        UserDefaults.standard.set(initial.rawValue, forKey: Self.userDefaultsKey)
        self.current = initial
    }

    /// Call once at the very start of the app, before any UI is constructed.
    /// All localized text resolution flows through `Bundle.loc(_:)`, which
    /// reads the user-selected language from `UserDefaults` and looks up
    /// strings against the correct `.lproj`. No `Bundle.main` class swizzle
    /// is required (and previous attempts at one interfered with SwiftUI's
    /// internal bundle caching).
    static func bootstrap() {
        _ = LocalizationManager.shared
    }
}
