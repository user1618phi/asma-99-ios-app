import Foundation
import SwiftData

enum PersistenceController {
    static let modelContainer: ModelContainer = {
        let schema = Schema([
            NameProgress.self,
            UserStats.self,
            TestAttempt.self,
            XPEvent.self,
        ])
        let config = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema mismatch (e.g. a field was removed in a model update and
            // we haven't shipped a versioned migration yet). Recover by
            // deleting the on-disk store and re-creating the container —
            // acceptable for an MVP pre-release because nobody has data they
            // care about losing, and far better than crashing on launch.
            print("[Persistence] schema load failed, resetting store: \(error)")
            wipeStore()
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Failed to create ModelContainer even after reset: \(error)")
            }
        }
    }()

    /// Delete every file the default SwiftData store writes (the SQLite
    /// database plus its `-wal` / `-shm` sidecars).
    private static func wipeStore() {
        let fm = FileManager.default
        let urls = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )).map { base in
            ["default.store", "default.store-wal", "default.store-shm"].map { base.appending(path: $0) }
        } ?? []
        for url in urls {
            try? fm.removeItem(at: url)
        }
    }
}

extension ModelContext {
    /// Returns the singleton UserStats row, creating it on first use.
    func userStats() -> UserStats {
        var descriptor = FetchDescriptor<UserStats>()
        descriptor.fetchLimit = 1
        if let existing = try? fetch(descriptor).first {
            return existing
        }
        let fresh = UserStats()
        insert(fresh)
        try? save()
        return fresh
    }

    /// Returns or creates a NameProgress for the given name number.
    func progress(for number: Int) -> NameProgress {
        let predicate = #Predicate<NameProgress> { $0.number == number }
        var descriptor = FetchDescriptor<NameProgress>(predicate: predicate)
        descriptor.fetchLimit = 1
        if let existing = try? fetch(descriptor).first {
            return existing
        }
        let fresh = NameProgress(number: number)
        insert(fresh)
        try? save()
        return fresh
    }
}
