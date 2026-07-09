//
//  Models.swift
//  Fortune
//
//  Domain models + the app-wide observable state object.
//

import SwiftUI
import Observation

// MARK: - Tabs

enum AppTab: String, CaseIterable, Hashable {
    case trade, predict, leaders, pnl, account

    /// Tabs that appear in the bottom bar. Account is reached from the
    /// PnL screen's avatar button, matching the original design.
    static let barTabs: [AppTab] = [.trade, .predict, .leaders, .pnl]

    var label: String {
        switch self {
        case .trade: "Trade"
        case .predict: "Predict"
        case .leaders: "Leaders"
        case .pnl: "Portfolio"
        case .account: "Account"
        }
    }

    var icon: String {
        switch self {
        case .trade: "chart.line.uptrend.xyaxis"
        case .predict: "target"
        case .leaders: "trophy"
        case .pnl: "chart.bar"
        case .account: "person"
        }
    }
}

// MARK: - App state

@Observable
final class AppModel {
    var onboarded = false
    var userName = "Alex Fortune"
    var balance: Double = 22_470
    var startingCapital: Double = 10_000
    var activeTab: AppTab = .trade
    var orders: [TradeOrder] = []

    func completeOnboarding(_ data: OnboardingData) {
        let trimmed = data.name.trimmingCharacters(in: .whitespaces)
        userName = trimmed.isEmpty ? "Trader" : trimmed
        // to match the mockups; startingCapital reflects the onboarding choice.
        switch data.capital {
        case "1k":   startingCapital = 1_000
        case "10k":  startingCapital = 10_000
        case "100k": startingCapital = 100_000
        case "1m":   startingCapital = 1_000_000
        default: break
        }
        onboarded = true
    }

    func signOut() {
        onboarded = false
        activeTab = .trade
    }

    func resetPortfolio() {
        orders.removeAll()
        balance = 22_470
    }
}

// MARK: - Trading

struct Stock: Identifiable, Hashable {
    let symbol: String
    let name: String
    let price: Double
    let change: Double
    let pct: Double
    let volume: String
    let high52: Double
    let low52: Double
    let pe: Double
    let mktCap: String
    let rating: String
    let ratingHex: UInt
    let sector: String

    var id: String { symbol }
    var ratingColor: Color { Color(hex: ratingHex) }

    var range52Fraction: Double {
        guard high52 > low52 else { return 0 }
        return (price - low52) / (high52 - low52)
    }
}

struct PricePoint: Identifiable {
    let time: String
    let price: Double
    var id: String { time }
}

/// A user's open position, used on the Portfolio screen.
struct Holding: Identifiable {
    let symbol: String
    let shares: Int
    let avgCost: Double
    let current: Double
    var id: String { symbol }

    var pnl: Double { (current - avgCost) * Double(shares) }
    var pct: Double { (current - avgCost) / avgCost * 100 }
    var marketValue: Double { current * Double(shares) }
}

/// A market-news headline shown on the Portfolio screen.
struct NewsItem: Identifiable {
    let id: Int
    let source: String
    let headline: String
    let time: String
    let tag: String
    let bullish: Bool
}

/// A price alert created from the Trade screen.
struct PriceAlert: Identifiable {
    let id = UUID()
    let symbol: String
    let target: String
    let above: Bool
}

struct Candle: Identifiable {
    let day: String
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    var isUp: Bool { close >= open }
    var id: String { day }
}

enum OrderSide: String, CaseIterable {
    case buy = "BUY"
    case sell = "SELL"
}

struct TradeOrder: Identifiable {
    let id = UUID()
    let symbol: String
    let name: String
    let side: OrderSide
    let qty: Int
    let entryPrice: Double
    let stopLoss: String
    let takeProfit: String
}

// MARK: - Predictions

struct PlacedBet: Hashable {
    let side: String
    let amount: Int
    let potential: Int
}

struct Prediction: Identifiable {
    let id: Int
    let question: String
    let yesOdds: Int
    let noOdds: Int
    let volume: String
    let closes: String
    let myBet: PlacedBet?
}

// MARK: - Leaderboard & achievements

struct LeaderboardEntry: Identifiable {
    let rank: Int
    let name: String
    let pnl: Double
    let winRate: Double
    let trades: Int
    let colorHex: UInt
    let symbol: String
    var isMe: Bool = false

    var id: Int { rank }
    var color: Color { Color(hex: colorHex) }
}

struct Achievement: Identifiable {
    let id: Int
    let icon: String
    let name: String
    let detail: String
    let earned: Bool
}

// MARK: - Onboarding

struct OnboardingData {
    var name = ""
    var experience = ""
    var goal = ""
    var frequency = ""
    var capital = ""
    var risk = ""
    var sectors: [String] = []
}
