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

    static let barTabs: [AppTab] = [.trade, .predict, .leaders, .pnl]

    var label: String {
        switch self {
        case .trade:   "Trade"
        case .predict: "Predict"
        case .leaders: "Leaders"
        case .pnl:     "Portfolio"
        case .account: "Account"
        }
    }

    var icon: String {
        switch self {
        case .trade:   "chart.line.uptrend.xyaxis"
        case .predict: "target"
        case .leaders: "trophy"
        case .pnl:     "chart.bar"
        case .account: "person"
        }
    }
}

// MARK: - App state

@Observable
final class AppModel {
    var onboarded       = false
    var userName        = "Trader"
    var balance:        Double = 10_000
    var startingCapital: Double = 10_000
    var activeTab:      AppTab = .trade
    var orders:         [TradeOrder] = []
    var joinDate:       Date = Date()

    // Onboarding preferences
    var experience:       String   = ""   // "beginner" | "intermediate" | "pro"
    var goal:             String   = ""   // "learn" | "grow" | "beat" | "fun"
    var frequency:        String   = ""   // "active" | "swing" | "casual"
    var risk:             String   = ""   // "conservative" | "balanced" | "aggressive"
    var preferredSectors: [String] = []

    // Live market data
    var stocks:    [Stock]               = []
    var news:      [NewsItem]            = []
    var chartData: [String: [PricePoint]] = [:]   // key: "SYMBOL_TIMEFRAME"
    var isLoading  = false

    // Tracked PnL
    var realizedPnL:      Double = 0
    var winCount:         Int    = 0
    var closedTradeCount: Int    = 0

    var predictions: [Prediction] = AppModel.defaultPredictions

    // MARK: Derived preferences

    var archetype: (label: String, icon: String) {
        if experience == "pro"          && risk == "aggressive" { return ("Power Trader",       "⚡") }
        if experience == "pro"          && risk == "balanced"   { return ("Precision Trader",   "🎯") }
        if experience == "pro"                                  { return ("Strategic Pro",       "💎") }
        if experience == "intermediate" && frequency == "active"{ return ("Swing Trader",       "📈") }
        if experience == "intermediate"                         { return ("Strategic Investor",  "🧠") }
        if risk == "aggressive"                                 { return ("Bold Explorer",       "🚀") }
        if frequency == "active"                                { return ("Eager Learner",       "⚡") }
        return ("Rising Trader", "🌟")
    }

    /// Default stop-loss offset from entry price based on risk appetite.
    var defaultStopLossPct: Double {
        switch risk {
        case "conservative": return 0.02
        case "aggressive":   return 0.05
        default:             return 0.03
        }
    }

    /// Default take-profit offset from entry price based on risk appetite.
    var defaultTakeProfitPct: Double {
        switch risk {
        case "conservative": return 0.04
        case "aggressive":   return 0.10
        default:             return 0.06
        }
    }

    /// Default chart timeframe based on trading frequency.
    var defaultTimeframe: String {
        switch frequency {
        case "swing":  return "1W"
        case "casual": return "1M"
        default:       return "1D"
        }
    }

    /// Default sort for the stock list based on goal.
    var defaultSortLabel: String {
        switch goal {
        case "beat": return "gainers"
        case "grow": return "default_"
        default:     return "default_"
        }
    }

    // MARK: Onboarding

    func completeOnboarding(_ data: OnboardingData) {
        let trimmed = data.name.trimmingCharacters(in: .whitespaces)
        userName         = trimmed.isEmpty ? "Trader" : trimmed
        experience       = data.experience
        goal             = data.goal
        frequency        = data.frequency
        risk             = data.risk
        preferredSectors = data.sectors
        joinDate         = Date()
        switch data.capital {
        case "1k":   startingCapital = 1_000
        case "10k":  startingCapital = 10_000
        case "100k": startingCapital = 100_000
        case "1m":   startingCapital = 1_000_000
        default: break
        }
        balance = startingCapital
        onboarded = true
    }

    func signOut() {
        onboarded = false
        activeTab = .trade
    }

    func resetPortfolio() {
        orders.removeAll()
        balance          = startingCapital
        realizedPnL      = 0
        winCount         = 0
        closedTradeCount = 0
    }

    /// Sell an entire open holding at the current live price.
    func closePosition(_ holding: Holding) {
        let price = stocks.first { $0.symbol == holding.symbol }?.price ?? holding.current
        placeOrder(TradeOrder(symbol: holding.symbol, name: holding.symbol,
                              side: .sell, qty: holding.shares, entryPrice: price,
                              stopLoss: "", takeProfit: ""))
    }

    /// Remove an order from history, refunding balance for buy orders.
    func cancelOrder(_ order: TradeOrder) {
        let cost = Double(order.qty) * order.entryPrice
        if order.side == .buy {
            balance += cost
        }
        orders.removeAll { $0.id == order.id }
    }

    // MARK: Order placement

    func placeOrder(_ order: TradeOrder) {
        let cost = Double(order.qty) * order.entryPrice
        if order.side == .buy {
            balance -= cost
        } else {
            let avgCost = currentAvgCost(for: order.symbol)
            let realized = (order.entryPrice - avgCost) * Double(order.qty)
            realizedPnL += realized
            if realized > 0 { winCount += 1 }
            closedTradeCount += 1
            balance += cost
        }
        orders.insert(order, at: 0)
    }

    // MARK: Data loading

    func loadMarketData() async {
        isLoading = true
        let fetched = await MarketService.shared.fetchStocks()
        if !fetched.isEmpty { stocks = fetched }
        let fetchedNews = await MarketService.shared.fetchNewsItems()
        if !fetchedNews.isEmpty { news = fetchedNews }
        isLoading = false
    }

    func loadChartData(symbol: String, timeframe: String) async {
        let key = "\(symbol)_\(timeframe)"
        guard chartData[key] == nil else { return }
        let points = await MarketService.shared.fetchChartData(symbol: symbol, timeframe: timeframe)
        if !points.isEmpty { chartData[key] = points }
    }

    // Force-refresh quotes for all stocks (for live price updates)
    func refreshQuotes() async {
        let updated = await MarketService.shared.fetchStocks()
        if !updated.isEmpty { stocks = updated }
    }

    // Force-refresh chart for the currently viewed stock/timeframe
    func refreshChart(symbol: String, timeframe: String) async {
        let key = "\(symbol)_\(timeframe)"
        chartData.removeValue(forKey: key)
        let points = await MarketService.shared.fetchChartData(symbol: symbol, timeframe: timeframe)
        if !points.isEmpty { chartData[key] = points }
    }

    // MARK: Computed portfolio

    var holdings: [Holding] {
        currentPositions().compactMap { symbol, pos in
            guard pos.qty > 0 else { return nil }
            let price = stocks.first { $0.symbol == symbol }?.price ?? pos.avgCost
            return Holding(symbol: symbol, shares: pos.qty, avgCost: pos.avgCost, current: price)
        }.sorted { $0.marketValue > $1.marketValue }
    }

    var unrealizedPnL: Double { holdings.reduce(0) { $0 + $1.pnl } }
    var totalPnL:      Double { unrealizedPnL + realizedPnL }
    var winRate:       Double {
        guard closedTradeCount > 0 else { return 0 }
        return Double(winCount) / Double(closedTradeCount)
    }

    var pnlCandles: [Candle] {
        let chronological = orders.reversed()
        guard !chronological.isEmpty else { return [] }
        var positions: [String: (qty: Int, totalCost: Double)] = [:]
        var accRealized = 0.0
        var prevPnL     = 0.0
        var result:     [Candle] = []
        let df = DateFormatter(); df.dateFormat = "MMM d"

        for order in chronological {
            switch order.side {
            case .buy:
                let e = positions[order.symbol] ?? (qty: 0, totalCost: 0)
                positions[order.symbol] = (e.qty + order.qty,
                                           e.totalCost + Double(order.qty) * order.entryPrice)
            case .sell:
                if var e = positions[order.symbol], e.qty > 0 {
                    let soldQty = min(order.qty, e.qty)
                    let avgCost = e.totalCost / Double(e.qty)
                    accRealized += (order.entryPrice - avgCost) * Double(soldQty)
                    let frac    = Double(e.qty - soldQty) / Double(e.qty)
                    e.qty       -= soldQty
                    e.totalCost *= frac
                    positions[order.symbol] = e
                }
            }
            let unrealized = positions.reduce(0.0) { sum, kv in
                guard kv.value.qty > 0 else { return sum }
                let avg   = kv.value.totalCost / Double(kv.value.qty)
                let price = stocks.first { $0.symbol == kv.key }?.price ?? avg
                return sum + (price - avg) * Double(kv.value.qty)
            }
            let currentPnL = unrealized + accRealized
            result.append(Candle(
                day:   df.string(from: order.date),
                open:  prevPnL,
                high:  max(prevPnL, currentPnL),
                low:   min(prevPnL, currentPnL),
                close: currentPnL
            ))
            prevPnL = currentPnL
        }
        return result
    }

    // MARK: Leaderboard (simulated — real requires backend)

    var leaderboard: [LeaderboardEntry] {
        var entries: [LeaderboardEntry] = [
            .init(rank: 0, name: "Atlas",  pnl: 24_857.12, winRate: 72.6, trades: 156, colorHex: 0xF59E0B, symbol: "▲"),
            .init(rank: 0, name: "Cipher", pnl: 18_392.45, winRate: 69.3, trades: 128, colorHex: 0x6D74FF, symbol: "◆"),
            .init(rank: 0, name: "Nova",   pnl: 14_672.33, winRate: 68.8, trades: 104, colorHex: 0x38D4FF, symbol: "★"),
            .init(rank: 0, name: "Vanta",  pnl:  9_876.34, winRate: 63.7, trades:  88, colorHex: 0x4ADE80, symbol: "◉"),
            .init(rank: 0, name: "Orion",  pnl:  7_654.21, winRate: 62.3, trades:  74, colorHex: 0x38D4FF, symbol: "✦"),
            .init(rank: 0, name: "Solace", pnl:  6_321.98, winRate: 61.2, trades:  68, colorHex: 0xF472B6, symbol: "◈"),
            .init(rank: 0, name: "Apex",   pnl:  5_432.19, winRate: 60.4, trades:  59, colorHex: 0xFB923C, symbol: "▲"),
            .init(rank: 0, name: userName, pnl: totalPnL,  winRate: winRate * 100,
                  trades: orders.count, colorHex: 0xB06AFF, symbol: "♛", isMe: true),
        ]
        entries.sort { $0.pnl > $1.pnl }
        return entries.enumerated().map { i, e in
            LeaderboardEntry(rank: i + 1, name: e.name, pnl: e.pnl, winRate: e.winRate,
                             trades: e.trades, colorHex: e.colorHex, symbol: e.symbol, isMe: e.isMe)
        }
    }

    // MARK: Achievements (computed from real activity)

    var achievements: [Achievement] {
        [
            Achievement(id: 1, icon: "🔥", name: "Hot Streak",    detail: "Win 5 trades in a row",        earned: winCount >= 5),
            Achievement(id: 2, icon: "💎", name: "Diamond Hands", detail: "Hold a position for 30+ days", earned: hasLongHold),
            Achievement(id: 3, icon: "🧀", name: "Big Baller",    detail: "Make 10K+ in Mock Capital",    earned: totalPnL >= 10_000),
            Achievement(id: 4, icon: "⚡", name: "Speed Trader",  detail: "Execute 50 trades in one day",  earned: maxTradesInOneDay >= 50),
            Achievement(id: 5, icon: "🏆", name: "Top Gainer",    detail: "Reach #1 on the leaderboard",   earned: leaderboard.first?.isMe == true),
            Achievement(id: 6, icon: "🌙", name: "Night Owl",     detail: "Trade after-hours 20 times",    earned: afterHoursTrades >= 20),
        ]
    }

    // MARK: Private helpers

    private func currentPositions() -> [String: (qty: Int, avgCost: Double)] {
        var pos: [String: (qty: Int, totalCost: Double)] = [:]
        for o in orders.reversed() {
            switch o.side {
            case .buy:
                let e = pos[o.symbol] ?? (qty: 0, totalCost: 0)
                pos[o.symbol] = (e.qty + o.qty, e.totalCost + Double(o.qty) * o.entryPrice)
            case .sell:
                if var e = pos[o.symbol], e.qty > 0 {
                    let soldQty = min(o.qty, e.qty)
                    let frac    = Double(e.qty - soldQty) / Double(e.qty)
                    e.qty       -= soldQty
                    e.totalCost *= frac
                    pos[o.symbol] = e
                }
            }
        }
        return pos.mapValues { e in
            (qty: e.qty, avgCost: e.qty > 0 ? e.totalCost / Double(e.qty) : 0)
        }.filter { $0.value.qty > 0 }
    }

    private func currentAvgCost(for symbol: String) -> Double {
        currentPositions()[symbol]?.avgCost ?? 0
    }

    private var hasLongHold: Bool {
        holdings.contains { h in
            guard let order = orders.last(where: { $0.symbol == h.symbol && $0.side == .buy }) else { return false }
            return Date().timeIntervalSince(order.date) > 30 * 86_400
        }
    }

    private var maxTradesInOneDay: Int {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        var counts: [String: Int] = [:]
        for o in orders { counts[df.string(from: o.date), default: 0] += 1 }
        return counts.values.max() ?? 0
    }

    private var afterHoursTrades: Int {
        let cal = Calendar.current
        return orders.filter { o in
            let h = cal.component(.hour, from: o.date)
            return h < 9 || h >= 16
        }.count
    }

    // MARK: Default predictions

    static let defaultPredictions: [Prediction] = [
        .init(id: 1, question: "Will the Fed cut rates this quarter?",
              yesOdds: 62, noOdds: 38, volume: "$4.2M", closes: "Sep 30", myBet: nil),
        .init(id: 2, question: "Will Bitcoin reach $100K before year end?",
              yesOdds: 51, noOdds: 49, volume: "$12.8M", closes: "Dec 31", myBet: nil),
        .init(id: 3, question: "Will S&P 500 hit a new all-time high this month?",
              yesOdds: 74, noOdds: 26, volume: "$8.4M", closes: "Jul 31", myBet: nil),
        .init(id: 4, question: "Will NVIDIA maintain #1 market cap position?",
              yesOdds: 68, noOdds: 32, volume: "$3.7M", closes: "Aug 15", myBet: nil),
        .init(id: 5, question: "Will the 10-year Treasury yield stay above 4%?",
              yesOdds: 81, noOdds: 19, volume: "$1.9M", closes: "Jul 31", myBet: nil),
    ]
}

// MARK: - Trading

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
}

struct PricePoint: Identifiable {
    let time: String
    let price: Double
    var id: String { time }
}

struct Holding: Identifiable {
    let symbol:  String
    let shares:  Int
    let avgCost: Double
    let current: Double
    var id: String { symbol }

    var pnl:         Double { (current - avgCost) * Double(shares) }
    var pct:         Double { (current - avgCost) / avgCost * 100 }
    var marketValue: Double { current * Double(shares) }
}

struct NewsItem: Identifiable {
    let id:       Int
    let source:   String
    let headline: String
    let time:     String
    let tag:      String
    let bullish:  Bool
}

struct PriceAlert: Identifiable {
    let id = UUID()
    let symbol: String
    let target: String
    let above:  Bool
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

enum OrderSide: String, CaseIterable {
    case buy = "BUY"
    case sell = "SELL"
}

struct TradeOrder: Identifiable {
    let id          = UUID()
    let symbol:     String
    let name:       String
    let side:       OrderSide
    let qty:        Int
    let entryPrice: Double
    let stopLoss:   String
    let takeProfit: String
    let date:       Date = Date()
}

// MARK: - Predictions

struct PlacedBet: Hashable {
    let side:      String
    let amount:    Int
    let potential: Int
}

struct Prediction: Identifiable {
    let id:       Int
    let question: String
    let yesOdds:  Int
    let noOdds:   Int
    let volume:   String
    let closes:   String
    let myBet:    PlacedBet?
}

// MARK: - Leaderboard & achievements

struct LeaderboardEntry: Identifiable {
    let rank:      Int
    let name:      String
    let pnl:       Double
    let winRate:   Double
    let trades:    Int
    let colorHex:  UInt
    let symbol:    String
    var isMe:      Bool = false

    var id:    Int   { rank }
    var color: Color { Color(hex: colorHex) }
}

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
    var experience = ""
    var goal       = ""
    var frequency  = ""
    var capital    = ""
    var risk       = ""
    var sectors:   [String] = []
}
