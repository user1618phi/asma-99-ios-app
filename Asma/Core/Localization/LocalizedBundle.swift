import Foundation
import SwiftUI

extension Bundle {
    /// Returns the `.lproj` bundle for the user-selected language. Reads
    /// `UserDefaults` on every access so a language switch immediately
    /// changes which strings come back.
    ///
    /// Used as the explicit `bundle:` argument on every `Text(_:bundle:)`
    /// call site — SwiftUI's default Bundle.main resolution caches
    /// `preferredLocalizations` at process launch and does **not** see
    /// runtime AppleLanguages changes.
    static var localized: Bundle {
        let lang = currentLanguageCode
        if let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    private static var currentLanguageCode: String {
        // Always read fresh from UserDefaults so a runtime language switch
        // immediately reflects on the next render pass.
        let stored = UserDefaults.standard.string(forKey: LocalizationManager.userDefaultsKey)
        return stored ?? AppLanguage.detected().rawValue
    }

    /// Resolve `key` against the user's selected language.
    ///
    /// We bypass `Bundle.localizedString` entirely and read the .strings
    /// dictionary directly — that's the only path that has been observed to
    /// reliably ignore SwiftUI's process-wide bundle caching across iOS
    /// versions when the language switches at runtime.
    static func loc(_ key: String) -> String {
        cachedStrings(for: currentLanguageCode)[key] ?? key
    }

    /// `printf`-style interpolation against `loc(_:)` — for keys like
    /// `"home.continue.due %lld %lld"` or `"home.greeting %@"`.
    static func loc(_ key: String, _ args: any CVarArg...) -> String {
        let format = loc(key)
        return String(format: format, locale: Locale(identifier: currentLanguageCode), arguments: args)
    }

    // MARK: - Strings dictionary cache

    /// Memoised in-process map of language code → `[key: value]`. The .strings
    /// files don't change at runtime, so we only ever read each one once.
    /// Cleared automatically when the bundle's underlying file mtime moves
    /// (in practice never — they ship with the bundle).
    nonisolated(unsafe) private static var cache: [String: [String: String]] = [:]
    private static let cacheLock = NSLock()

    private static func cachedStrings(for lang: String) -> [String: String] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let existing = cache[lang] { return existing }
        let dict = loadStrings(for: lang)
        cache[lang] = dict
        return dict
    }

    private static func loadStrings(for lang: String) -> [String: String] {
        // Read the .strings file directly from disk, bypassing Apple's
        // `url(forResource:withExtension:subdirectory:localization:)` API,
        // which honours `CFBundleLocalizations` from Info.plist — Xcode's
        // synthetic Info.plist doesn't always include every available
        // localization, so Kazakh in particular wasn't being found.
        let url = Bundle.main.bundleURL
            .appendingPathComponent("\(lang).lproj")
            .appendingPathComponent("Localizable.strings")
        if let dict = NSDictionary(contentsOf: url) as? [String: String] {
            return dict
        }
        return [:]
    }
}

// MARK: - LocText
//
// Drop-in replacement for `Text(LocalizedStringKey)` that bypasses SwiftUI's
// LocalizedStringResource pipeline (which doesn't always honour explicit
// `bundle:` arguments on language-switch) and goes straight through
// `Bundle.loc(_:)`. Use anywhere previously written as
// `Text("some.key")` — and observe `LocalizationManager.current` somewhere
// in the parent so the body re-evaluates on language change.

struct LocText: View {
    private let resolved: String

    init(_ key: String) {
        self.resolved = Bundle.loc(key)
    }

    /// Variadic version for keys containing `%@`, `%lld` etc.
    init(_ key: String, _ args: any CVarArg...) {
        self.resolved = Bundle.loc(key, args: args)
    }

    var body: some View {
        Text(verbatim: resolved)
    }
}

extension Bundle {
    /// Helper called by `LocText` — keeps the variadic stays at one layer.
    static func loc(_ key: String, args: [any CVarArg]) -> String {
        let format = loc(key)
        return String(format: format, locale: Locale(identifier: currentLanguageCode), arguments: args)
    }
}
