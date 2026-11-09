//
//  Persistence.swift
//  Fortune
//
//  Saved app state and where it's stored. AppModel depends on the
//  PersistenceStore protocol, so tests can swap in isolated storage.
//

import Foundation

/// Everything saved between launches. Fields added after v1 are optional so older saves still decode.
/// Preference enums are stored as raw strings so unknown values fall back instead of failing the load.
struct PersistedState: Codable {
    var onboarded:        Bool
    var userName:         String
    var balance:          Decimal
    var startingCapital:  Decimal
    var orders:           [TradeOrder]
    var joinDate:         Date
    var experience:       String
    var goal:             String
    var frequency:        String
    var risk:             String
    var customStopLossPct: Double?
    var weeklyDigestEnabled: Bool?
    var notificationsEnabled: Bool?
    var stockAlertsEnabled: Bool?
    var xpMilestonesEnabled: Bool?
    var lastNewsRefresh: Date?
    var preferredSectors: [String]
    var realizedPnL:      Decimal
    var winCount:         Int
    var closedTradeCount: Int
    var closedTrades:     [ClosedTrade]
    var priceAlerts:      [PriceAlert]?
    var bonusXP:          Int?
    var challengeDay:     String?
    var awardedChallenges: [String]?
    var starredSymbols:   [String]?
    var watchlistSyncEnabled: Bool?
}

protocol PersistenceStore {
    func load() -> PersistedState?
    func save(_ state: PersistedState)
}

/// Production storage: JSON in UserDefaults.
struct UserDefaultsStore: PersistenceStore {
    static let key = "fortune_state_v1"
    var defaults: UserDefaults = .standard

    func load() -> PersistedState? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    func save(_ state: PersistedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// Starred-stock sync through iCloud key-value storage.
enum CloudWatchlist {
    private static let key = "starredSymbols"

    static func push(_ symbols: [String]) {
        let store = NSUbiquitousKeyValueStore.default
        store.set(symbols, forKey: key)
        store.synchronize()
    }

    static func fetch() -> [String] {
        NSUbiquitousKeyValueStore.default.array(forKey: key) as? [String] ?? []
    }

    /// Fires whenever another device changes the synced values.
    static func externalChanges() -> NotificationCenter.Notifications {
        NSUbiquitousKeyValueStore.default.synchronize()
        return NotificationCenter.default.notifications(named: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
    }
}
