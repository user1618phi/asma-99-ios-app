import Foundation
import SwiftData

@MainActor
enum XPService {
    /// Award XP for an in-app action. Inserts an `XPEvent` audit trail and
    /// bumps `UserStats.totalXP`. Zero-amount calls are dropped so the audit
    /// log only contains meaningful events.
    static func award(amount: Int, source: XPSource, in context: ModelContext) {
        guard amount > 0 else { return }
        let stats = context.userStats()
        stats.totalXP += amount
        context.insert(XPEvent(date: Date(), amount: amount, source: source.rawValue))
        try? context.save()
    }
}
