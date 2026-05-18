import Foundation
import StoreKit
import SwiftUI

/// State machine + Apple-prompt invocation for the Rate-us flow.
///
/// One UI surface: the centered overlay ("Worth a moment?"). Shown the
/// first time the user finishes a test round, then again every **14
/// days** if they keep tapping Later. Vanishes forever once
/// `rated = true`.
///
/// The Home folder-tab banner that used to follow Later was removed —
/// only the overlay survives. The `Rate us` row in Profile takes the
/// user straight to Apple's native prompt without going through this
/// flow.
///
/// All persistence uses UserDefaults so the state survives kills. We
/// re-read on each call (no caching) since the call frequency is tiny.
enum RateUsService {
    /// Days between successive auto-appearances of the centered overlay.
    /// Pulls double-duty as the "Apple's review prompt is throttled to
    /// ~3x per year per device anyway" alignment number.
    private static let overlayReshowDays: Double = 14

    // MARK: - Storage keys

    private enum Key {
        static let rated = "rateUs.rated"
        static let firstRoundComplete = "rateUs.firstRoundComplete"
        /// TimeInterval since 1970 — last time the centered overlay was
        /// dismissed by the user. `0` means "never shown yet". Used to
        /// gate the 14-day re-show.
        static let overlayLastDismissedAt = "rateUs.overlayLastDismissedAt"
    }

    private static var defaults: UserDefaults { .standard }

    // MARK: - Reads

    /// Once `true`, no automatic Rate-us UI is ever shown again. The
    /// explicit "Rate us" row in Profile still works (sends the user
    /// straight to Apple's prompt).
    static var rated: Bool {
        defaults.bool(forKey: Key.rated)
    }

    /// Whether the centered modal should appear on the next Home render.
    /// First time → after the user finishes their first test round.
    /// Subsequent times → every 14 days after the previous dismissal.
    static var shouldShowOverlay: Bool {
        guard !rated else { return false }
        guard defaults.bool(forKey: Key.firstRoundComplete) else { return false }

        let lastDismissedAt = defaults.double(forKey: Key.overlayLastDismissedAt)
        if lastDismissedAt == 0 {
            // Never shown — first encounter after the first test round.
            return true
        }

        let secondsSince = Date().timeIntervalSince1970 - lastDismissedAt
        return secondsSince >= overlayReshowDays * 24 * 60 * 60
    }

    // MARK: - Writes

    /// Called the moment the user finishes their first-ever test session.
    /// Idempotent — only flips the flag if it's still false.
    static func markFirstRoundComplete() {
        guard !defaults.bool(forKey: Key.firstRoundComplete) else { return }
        defaults.set(true, forKey: Key.firstRoundComplete)
    }

    /// User tapped Later (or × on the overlay corner). Stores the
    /// dismissal timestamp so the overlay won't re-show for another
    /// 14 days.
    static func dismissOverlayAsLater() {
        defaults.set(Date().timeIntervalSince1970, forKey: Key.overlayLastDismissedAt)
    }

    /// User tapped "Rate Asma" anywhere (overlay, Profile). We trigger
    /// Apple's native review prompt and mark the user as rated so no
    /// further automatic UI is shown.
    ///
    /// Apple's `requestReview()` is throttled (≤3 times per year per
    /// device per app) and silently no-ops past that — we can't observe
    /// whether they actually submitted, only that we tried. Treating
    /// "tried" as "rated" is the standard pattern.
    @MainActor
    static func triggerSystemPrompt(requestReview: RequestReviewAction) {
        defaults.set(true, forKey: Key.rated)
        requestReview()
    }
}
