import Foundation

@Observable
final class NamesRepository {
    static let shared = NamesRepository()

    private(set) var names: [AsmaName] = []
    private var byNumber: [Int: AsmaName] = [:]

    private init() {
        load()
    }

    func name(number: Int) -> AsmaName? {
        byNumber[number]
    }

    func next(after number: Int) -> AsmaName? {
        names.first(where: { $0.number == number + 1 })
    }

    func previous(before number: Int) -> AsmaName? {
        names.first(where: { $0.number == number - 1 })
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "names", withExtension: "json") else {
            assertionFailure("names.json not found in bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([AsmaName].self, from: data)
            self.names = decoded.sorted { $0.number < $1.number }
            self.byNumber = Dictionary(uniqueKeysWithValues: decoded.map { ($0.number, $0) })
            assert(decoded.count == 99, "Expected exactly 99 names, found \(decoded.count)")
        } catch {
            assertionFailure("Failed to decode names.json: \(error)")
        }
    }
}
