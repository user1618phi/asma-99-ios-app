import Foundation

struct AsmaName: Identifiable, Codable, Hashable, Sendable {
    let number: Int
    let arabic: String
    let transliteration: String
    let audio: String
    let translations: [String: NameTranslation]

    var id: Int { number }

    func translation(for language: String) -> NameTranslation {
        translations[language] ?? translations["en"] ?? NameTranslation(translation: transliteration, meaning: "")
    }
}

struct NameTranslation: Codable, Hashable, Sendable {
    let translation: String
    let meaning: String
}
