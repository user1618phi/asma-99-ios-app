import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case en, ru, kk

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        case .kk: return "Қазақша"
        }
    }

    static func detected() -> AppLanguage {
        guard let code = Locale.current.language.languageCode?.identifier.lowercased() else {
            return .en
        }
        return AppLanguage(rawValue: code) ?? .en
    }
}
