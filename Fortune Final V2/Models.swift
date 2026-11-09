//
//  Models.swift
//  Fortune
//
//  Domain types shared across the app. App state lives in AppModel.swift;
//  trading rules live in PortfolioEngine.swift.
//

import SwiftUI

// MARK: - Tabs

enum AppTab: String, CaseIterable, Hashable {
    case trade, leaders, pnl, account

    static let barTabs: [AppTab] = [.trade, .pnl, .leaders, .account]

    var label: String {
        switch self {
        case .trade:   "Trade"
        case .leaders: "Leaders"
        case .pnl:     "Portfolio"
        case .account: "Account"
        }
    }

    var icon: String {
        switch self {
        case .trade:   "chart.line.uptrend.xyaxis"
        case .leaders: "trophy"
        case .pnl:     "chart.bar"
        case .account: "person"
        }
    }
}

// MARK: - Orders

enum OrderSide: String, CaseIterable, Codable {
    case buy = "BUY"
    case sell = "SELL"
}

struct TradeOrder: Identifiable, Codable {
    let id:         UUID
    let symbol:     String
    let name:       String
    let side:       OrderSide
    let qty:        Int
    let entryPrice: Decimal
    let stopLoss:   Decimal?
    let takeProfit: Decimal?
    let date:       Date

    /// Prices come in as market quotes (Double) and are stored as exact dollars and cents.
    init(symbol: String, name: String, side: OrderSide, qty: Int,
         entryPrice: Double, stopLoss: Double?, takeProfit: Double?, date: Date = Date()) {
        self.id         = UUID()
        self.symbol     = symbol
        self.name       = name
        self.side       = side
        self.qty        = qty
        self.entryPrice = Decimal(price: entryPrice)
        self.stopLoss   = stopLoss.map(Decimal.init(price:))
        self.takeProfit = takeProfit.map(Decimal.init(price:))
        self.date       = date
    }

    /// Older versions saved prices as Doubles and stop loss / take profit as Strings ("" for none).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self, forKey: .id)
        symbol     = try c.decode(String.self, forKey: .symbol)
        name       = try c.decode(String.self, forKey: .name)
        side       = try c.decode(OrderSide.self, forKey: .side)
        qty        = try c.decode(Int.self, forKey: .qty)
        entryPrice = try c.decode(Decimal.self, forKey: .entryPrice).roundedToCents()
        date       = try c.decode(Date.self, forKey: .date)
        stopLoss   = try c.decodeLenientDecimal(forKey: .stopLoss)
        takeProfit = try c.decodeLenientDecimal(forKey: .takeProfit)
    }
}

// MARK: - Closed trade journal

struct ClosedTrade: Identifiable, Codable {
    let id:          UUID
    let symbol:      String
    let name:        String
    let shares:      Int
    let entryPrice:  Decimal
    let exitPrice:   Decimal
    let pnl:         Decimal
    let exitReason:  ExitReason
    let openedAt:    Date
    let closedAt:    Date

    init(symbol: String, name: String, shares: Int,
         entryPrice: Decimal, exitPrice: Decimal, pnl: Decimal,
         exitReason: ExitReason, openedAt: Date, closedAt: Date = Date()) {
        self.id         = UUID()
        self.symbol     = symbol
        self.name       = name
        self.shares     = shares
        self.entryPrice = entryPrice
        self.exitPrice  = exitPrice
        self.pnl        = pnl
        self.exitReason = exitReason
        self.openedAt   = openedAt
        self.closedAt   = closedAt
    }

    enum ExitReason: String, Codable {
        case manual     = "Manual"
        case stopLoss   = "Stop Loss"
        case takeProfit = "Take Profit"

        var icon: String {
            switch self {
            case .manual:     "✋"
            case .stopLoss:   "🛑"
            case .takeProfit: "🎯"
            }
        }
    }

    var pct: Double {
        guard entryPrice > 0 else { return 0 }
        return ((exitPrice - entryPrice) / entryPrice * 100).doubleValue
    }
    var isWin: Bool { pnl > 0 }
}

// MARK: - Portfolio display

/// An open position valued at the latest quote. Display values only; the ledger is in PortfolioEngine.
struct Holding: Identifiable {
    let symbol:  String
    let shares:  Int
    let avgCost: Double
    let current: Double
    var id: String { symbol }

    var pnl:         Double { (current - avgCost) * Double(shares) }
    var pct:         Double { guard avgCost > 0 else { return 0 }; return (current - avgCost) / avgCost * 100 }
    var marketValue: Double { current * Double(shares) }
}

// MARK: - Market data

struct Stock: Identifiable, Hashable {
    let symbol: String
    let name:   String
    let price:  Double
    let change: Double
    let pct:    Double
    let volume: String
    let high52: Double
    let low52:  Double
    let pe:     Double
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

    /// Same stock at a new price; fundamentals are kept.
    func withPrice(_ price: Double, change: Double, pct: Double) -> Stock {
        Stock(symbol: symbol, name: name, price: price, change: change, pct: pct,
              volume: volume, high52: high52, low52: low52, pe: pe, mktCap: mktCap,
              rating: rating, ratingHex: ratingHex, sector: sector)
    }
}

struct NewsItem: Identifiable {
    let id:       Int
    let source:   String
    let headline: String
    let time:     String
    let tag:      String
    let bullish:  Bool
}

struct Candle: Identifiable {
    let day:   String
    let open:  Double
    let high:  Double
    let low:   Double
    let close: Double
    var isUp:  Bool { close >= open }
    var id:    String { day }
}

// MARK: - Alerts

struct PriceAlert: Identifiable, Codable {
    var id = UUID()
    let symbol: String
    let target: Double
    let above:  Bool

    init(symbol: String, target: Double, above: Bool) {
        self.symbol = symbol
        self.target = target
        self.above  = above
    }

    /// Older versions saved `target` as a String.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id     = try c.decode(UUID.self, forKey: .id)
        symbol = try c.decode(String.self, forKey: .symbol)
        above  = try c.decode(Bool.self, forKey: .above)
        target = try c.decodeLenientDecimal(forKey: .target)?.doubleValue ?? 0
    }
}

// MARK: - Achievements

struct Achievement: Identifiable {
    let id:     Int
    let icon:   String
    let name:   String
    let detail: String
    let earned: Bool
}

// MARK: - Onboarding

struct OnboardingData {
    var name       = ""
    var experience: ExperienceLevel?  = nil
    var goal:       TradingGoal?      = nil
    var frequency:  TradingFrequency? = nil
    var capital:    StartingCapital?  = nil
    var risk:       RiskLevel?        = nil
    var sectors:    [String] = []
}

// MARK: - Decoding helpers

extension KeyedDecodingContainer {
    /// Decodes an amount saved either as a number or as a numeric String.
    /// Missing, null, or empty/non-numeric strings decode as nil.
    func decodeLenientDecimal(forKey key: Key) throws -> Decimal? {
        if let number = try? decodeIfPresent(Decimal.self, forKey: key) { return number.roundedToCents() }
        guard let text = try? decodeIfPresent(String.self, forKey: key),
              let value = Decimal(string: text) else { return nil }
        return value.roundedToCents()
    }
}
