import Foundation

/// Background ambience the user can pick from the top-right glass control.
/// `.silent` is a first-class option — the user explicitly chose "no sound."
enum AmbientSound: String, CaseIterable, Identifiable, Sendable {
    case birds
    case rain
    case waves
    case thunderstorm
    case silent

    var id: String { rawValue }

    /// Bundle filename (without extension) for the looping mp3. `nil` for
    /// `.silent` — the player simply stops without loading a file.
    var fileName: String? {
        switch self {
        case .silent: return nil
        case .birds, .rain, .waves, .thunderstorm: return rawValue
        }
    }

    /// SF Symbol used by the glass circle button and popover row.
    var systemImage: String {
        switch self {
        case .birds:        return "bird.fill"
        case .rain:         return "cloud.rain.fill"
        case .waves:        return "water.waves"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        case .silent:       return "speaker.slash.fill"
        }
    }

    /// Key for `Bundle.loc(_:)` — resolved into a localized label at render.
    var localizationKey: String { "ambient.\(rawValue)" }
}
