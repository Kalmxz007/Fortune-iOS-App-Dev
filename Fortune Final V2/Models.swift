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

// MARK: - Closed trade journal

struct ClosedTrade: Identifiable, Codable {
    let id:          UUID
    let symbol:      String
    let name:        String
    let shares:      Int
    let entryPrice:  Double
    let exitPrice:   Double
    let pnl:         Double
    let exitReason:  ExitReason
    let openedAt:    Date
    let closedAt:    Date

    init(symbol: String, name: String, shares: Int,
         entryPrice: Double, exitPrice: Double, pnl: Double,
         exitReason: ExitReason, openedAt: Date) {
        self.id         = UUID()
        self.symbol     = symbol
        self.name       = name
        self.shares     = shares
        self.entryPrice = entryPrice
        self.exitPrice  = exitPrice
        self.pnl        = pnl
        self.exitReason = exitReason
        self.openedAt   = openedAt
        self.closedAt   = Date()
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

    var pct:   Double { guard entryPrice > 0 else { return 0 }; return (exitPrice - entryPrice) / entryPrice * 100 }
    var isWin: Bool   { pnl > 0 }
}

// MARK: - Persistence container

private struct PersistedState: Codable {
    var onboarded:        Bool
    var userName:         String
    var balance:          Double
    var startingCapital:  Double
    var orders:           [TradeOrder]
    var joinDate:         Date
    var experience:       String
    var goal:             String
    var frequency:        String
    var risk:             String
    var customStopLossPct: Double?
    var weeklyDigestEnabled: Bool?
    var lastNewsRefresh: Date?
    var preferredSectors: [String]
    var realizedPnL:      Double
    var winCount:         Int
    var closedTradeCount: Int
    var closedTrades:     [ClosedTrade]
}

// MARK: - App state

@Observable
final class AppModel {
    var onboarded        = false
    var userName         = "Trader"
    var balance:         Double = 10_000
    var startingCapital: Double = 10_000
    var activeTab:       AppTab = .trade
    var orders:          [TradeOrder] = []
    var joinDate:        Date = Date()

    // Onboarding preferences
    var experience:       String   = ""
    var goal:             String   = ""
    var frequency:        String   = ""
    var risk:             String   = ""
    var customStopLossPct: Double? = nil
    var weeklyDigestEnabled = true
    var preferredSectors: [String] = []

    // Live market data
    var stocks:    [Stock]                = []
    var news:      [NewsItem]             = []
    var chartData: [String: [Candle]] = [:]
    var isLoading  = false
    var lastNewsRefresh: Date? = nil

    // PnL tracking
    var realizedPnL:      Double = 0
    var winCount:         Int    = 0
    var closedTradeCount: Int    = 0
    var closedTrades:     [ClosedTrade] = []

    // Trade confirmation toast (set on every buy/sell, cleared by UI)
    var tradeConfirmation: String? = nil
    // Last SL/TP alert message (cleared after display)
    var lastAlert: String? = nil
    // Controls the tutorial sheet
    var showTutorial = false
    // Triggers the First Blood confetti celebration (first trade of the day)
    var showFirstBloodCelebration = false

    // Price direction tracking: populated before each quote refresh
    var previousPrices:      [String: Double] = [:]
    var isRefreshingPrices   = false

    // WebSocket throttle — last time each symbol's price was pushed to the UI
    private var lastWSUpdate: [String: Date] = [:]

    private static let storeKey = "fortune_state_v1"

    init() { load() }

    // MARK: Derived preferences

    var archetype: (label: String, icon: String) {
        if experience == "pro"          && risk == "aggressive" { return ("Power Trader",      "⚡") }
        if experience == "pro"          && risk == "balanced"   { return ("Precision Trader",  "🎯") }
        if experience == "pro"                                  { return ("Strategic Pro",      "💎") }
        if experience == "intermediate" && frequency == "active"{ return ("Swing Trader",      "📈") }
        if experience == "intermediate"                         { return ("Strategic Investor", "🧠") }
        if risk == "aggressive"                                 { return ("Bold Explorer",      "🚀") }
        if frequency == "active"                                { return ("Eager Learner",      "⚡") }
        return ("Rising Trader", "🌟")
    }

    var defaultStopLossPct: Double {
        customStopLossPct ?? riskBasedStopLossPct
    }

    private var riskBasedStopLossPct: Double {
        switch risk {
        case "conservative": return 0.02
        case "aggressive":   return 0.05
        default:             return 0.03
        }
    }

    var defaultTakeProfitPct: Double {
        switch risk {
        case "conservative": return 0.04
        case "aggressive":   return 0.10
        default:             return 0.06
        }
    }

    var defaultTimeframe: String {
        switch frequency {
        case "swing":  return "1W"
        case "casual": return "1M"
        default:       return "1D"
        }
    }

    // MARK: Gamification (derived from real activity)

    var totalXP: Int {
        closedTradeCount * 200 + winCount * 100 + max(0, Int(realizedPnL / 100))
    }
    var level: Int { max(1, 1 + totalXP / 1_000) }
    var xpInCurrentLevel: Int { totalXP % 1_000 }
    var xpProgress: Double { Double(xpInCurrentLevel) / 1_000.0 }

    var totalPortfolioValue: Double {
        balance + holdings.reduce(0) { $0 + $1.marketValue }
    }

    var defaultSortLabel: String {
        switch goal {
        case "beat": return "gainers"
        default:     return "default_"
        }
    }

    // MARK: Persistence

    func save() {
        let state = PersistedState(
            onboarded:        onboarded,
            userName:         userName,
            balance:          balance,
            startingCapital:  startingCapital,
            orders:           orders,
            joinDate:         joinDate,
            experience:       experience,
            goal:             goal,
            frequency:        frequency,
            risk:             risk,
            customStopLossPct: customStopLossPct,
            weeklyDigestEnabled: weeklyDigestEnabled,
            lastNewsRefresh: lastNewsRefresh,
            preferredSectors: preferredSectors,
            realizedPnL:      realizedPnL,
            winCount:         winCount,
            closedTradeCount: closedTradeCount,
            closedTrades:     closedTrades
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }

    private func load() {
        guard let data  = UserDefaults.standard.data(forKey: Self.storeKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data)
        else { return }
        onboarded        = state.onboarded
        userName         = state.userName
        balance          = state.balance
        startingCapital  = state.startingCapital
        orders           = state.orders
        joinDate         = state.joinDate
        experience       = state.experience
        goal             = state.goal
        frequency        = state.frequency
        risk             = state.risk
        customStopLossPct = state.customStopLossPct
        weeklyDigestEnabled = state.weeklyDigestEnabled ?? true
        lastNewsRefresh = state.lastNewsRefresh
        preferredSectors = state.preferredSectors
        realizedPnL      = state.realizedPnL
        winCount         = state.winCount
        closedTradeCount = state.closedTradeCount
        closedTrades     = state.closedTrades
    }

    // MARK: Onboarding

    func completeOnboarding(_ data: OnboardingData) {
        let trimmed = data.name.trimmingCharacters(in: .whitespaces)
        userName         = trimmed.isEmpty ? "Trader" : trimmed
        experience       = data.experience
        goal             = data.goal
        frequency        = data.frequency
        risk             = data.risk
        customStopLossPct = nil
        weeklyDigestEnabled = true
        lastNewsRefresh = nil
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
        if experience == "beginner" || experience == "intermediate" {
            showTutorial = true
        }
        save()
    }

    func signOut() {
        onboarded = false
        activeTab = .trade
        save()
    }

    func updateRisk(_ newRisk: String) {
        risk = newRisk
        save()
    }

    func updateDefaultStopLossPct(_ pct: Double) {
        customStopLossPct = pct
        save()
    }

    func updateWeeklyDigestEnabled(_ isEnabled: Bool) {
        weeklyDigestEnabled = isEnabled
        save()
    }

    func resetPortfolio() {
        orders.removeAll()
        closedTrades.removeAll()
        balance          = startingCapital
        realizedPnL      = 0
        winCount         = 0
        closedTradeCount = 0
        tradeConfirmation = nil
        lastAlert         = nil
        save()
    }

    /// Returns whether the user can afford to buy qty shares at price.
    func canAfford(qty: Int, price: Double) -> Bool {
        balance >= Double(qty) * price
    }

    /// Sell an entire open holding at the current live price.
    func closePosition(_ holding: Holding) {
        let price = stocks.first { $0.symbol == holding.symbol }?.price ?? holding.current
        placeOrder(TradeOrder(symbol: holding.symbol, name: holding.symbol,
                              side: .sell, qty: holding.shares, entryPrice: price,
                              stopLoss: "", takeProfit: ""))
    }

    /// Sell a specific number of shares from a holding.
    func partialSell(holding: Holding, shares: Int) {
        guard shares > 0, shares <= holding.shares else { return }
        let price = stocks.first { $0.symbol == holding.symbol }?.price ?? holding.current
        placeOrder(TradeOrder(symbol: holding.symbol, name: holding.symbol,
                              side: .sell, qty: shares, entryPrice: price,
                              stopLoss: "", takeProfit: ""))
    }

    /// Remove a pending buy from history, refunding the balance.
    func cancelOrder(_ order: TradeOrder) {
        let cost = Double(order.qty) * order.entryPrice
        if order.side == .buy { balance += cost }
        orders.removeAll { $0.id == order.id }
        save()
    }

    // MARK: Order placement

    func placeOrder(_ order: TradeOrder) {
        let cost = Double(order.qty) * order.entryPrice
        let isFirstTodayBuy = order.side == .buy && !hasTradeToday()
        if order.side == .buy {
            guard balance >= cost else { return }
            balance -= cost
            tradeConfirmation = "Bought \(order.qty) × \(order.symbol) @ $\(String(format: "%.2f", order.entryPrice))"
        } else {
            let avgCost  = currentAvgCost(for: order.symbol)
            let realized = (order.entryPrice - avgCost) * Double(order.qty)
            realizedPnL      += realized
            if realized > 0 { winCount += 1 }
            closedTradeCount += 1
            balance          += cost

            let openedAt = orders.last(where: { $0.symbol == order.symbol && $0.side == .buy })?.date ?? order.date
            closedTrades.insert(ClosedTrade(
                symbol:     order.symbol,
                name:       order.name,
                shares:     order.qty,
                entryPrice: avgCost,
                exitPrice:  order.entryPrice,
                pnl:        realized,
                exitReason: .manual,
                openedAt:   openedAt
            ), at: 0)

            tradeConfirmation = realized >= 0
                ? "Sold \(order.symbol) · +$\(String(format: "%.2f", realized))"
                : "Sold \(order.symbol) · -$\(String(format: "%.2f", abs(realized)))"
        }
        orders.insert(order, at: 0)
        if isFirstTodayBuy { showFirstBloodCelebration = true }
        save()
    }

    private func hasTradeToday() -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return orders.contains { Calendar.current.startOfDay(for: $0.date) == today }
    }

    // MARK: SL/TP auto-execution

    /// Call this after every quote refresh — closes positions whose SL or TP has been hit.
    func checkAndTriggerSLTP() {
        var triggered: Set<String> = []
        for holding in holdings {
            guard !triggered.contains(holding.symbol) else { continue }
            guard let price = stocks.first(where: { $0.symbol == holding.symbol })?.price else { continue }
            // Use the most recent buy order's SL/TP values
            guard let ref = orders.first(where: { $0.symbol == holding.symbol && $0.side == .buy }) else { continue }
            let sl = Double(ref.stopLoss)   ?? 0
            let tp = Double(ref.takeProfit) ?? 0
            if sl > 0 && price <= sl {
                autoClose(holding: holding, price: price, reason: .stopLoss)
                triggered.insert(holding.symbol)
            } else if tp > 0 && price >= tp {
                autoClose(holding: holding, price: price, reason: .takeProfit)
                triggered.insert(holding.symbol)
            }
        }
    }

    private func autoClose(holding: Holding, price: Double, reason: ClosedTrade.ExitReason) {
        let avgCost  = holding.avgCost
        let realized = (price - avgCost) * Double(holding.shares)
        realizedPnL      += realized
        if realized > 0 { winCount += 1 }
        closedTradeCount += 1
        balance          += Double(holding.shares) * price

        let openedAt = orders.last(where: { $0.symbol == holding.symbol && $0.side == .buy })?.date ?? Date()
        closedTrades.insert(ClosedTrade(
            symbol:     holding.symbol,
            name:       holding.symbol,
            shares:     holding.shares,
            entryPrice: avgCost,
            exitPrice:  price,
            pnl:        realized,
            exitReason: reason,
            openedAt:   openedAt
        ), at: 0)

        // Insert synthetic sell order so position collapses in computed holdings
        orders.insert(TradeOrder(symbol: holding.symbol, name: holding.symbol,
                                 side: .sell, qty: holding.shares, entryPrice: price,
                                 stopLoss: "", takeProfit: ""), at: 0)

        lastAlert = reason == .stopLoss
            ? "🛑 Stop Loss hit — \(holding.symbol) sold @ $\(String(format: "%.2f", price))"
            : "🎯 Take Profit hit — \(holding.symbol) sold @ $\(String(format: "%.2f", price))"
        save()
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

    /// Connects to Finnhub WebSocket and applies real-time trade prices.
    /// Throttled to at most one UI update per symbol per 2 seconds so large-caps
    /// (AAPL/NVDA trade 1000s of times/min) don't flood SwiftUI's render loop.
    /// Auto-reconnects on disconnect. Call once from a long-lived Task.
    func startLivePriceStream() async {
        while !Task.isCancelled {
            for await (symbol, price) in await MarketService.shared.liveTradeStream() {
                let now = Date()
                // Throttle: skip if same symbol updated within 2 s
                if let last = lastWSUpdate[symbol], now.timeIntervalSince(last) < 2 { continue }
                // Skip noise below 1 cent
                guard let idx = stocks.firstIndex(where: { $0.symbol == symbol }) else { continue }
                let s = stocks[idx]
                guard abs(price - s.price) >= 0.01 else { continue }

                lastWSUpdate[symbol] = now
                let prevClose = s.price - s.change
                let newChange = price - prevClose
                let newPct    = prevClose > 0 ? newChange / prevClose * 100 : s.pct
                previousPrices[symbol] = s.price
                stocks[idx] = Stock(
                    symbol: s.symbol, name: s.name,
                    price: price, change: newChange, pct: newPct,
                    volume: s.volume, high52: s.high52, low52: s.low52,
                    pe: s.pe, mktCap: s.mktCap,
                    rating: s.rating, ratingHex: s.ratingHex, sector: s.sector
                )
                checkAndTriggerSLTP()
            }
            // Stream ended (disconnect/error) — wait 3 s then reconnect
            try? await Task.sleep(for: .seconds(3))
        }
    }

    func refreshQuotes() async {
        let updated = await MarketService.shared.fetchStocks()
        if !updated.isEmpty {
            previousPrices = Dictionary(uniqueKeysWithValues: stocks.map { ($0.symbol, $0.price) })
            stocks = updated
            checkAndTriggerSLTP()
        }
    }

    /// Lightweight price-only refresh — 1 API call per symbol instead of 3.
    /// Safe to call every 15 s without hitting Finnhub rate limits.
    func refreshPrices() async {
        isRefreshingPrices = true
        defer { isRefreshingPrices = false }
        let updates = await MarketService.shared.fetchQuotesOnly()
        guard !updates.isEmpty else { return }
        previousPrices = Dictionary(uniqueKeysWithValues: stocks.map { ($0.symbol, $0.price) })
        stocks = stocks.map { stock in
            guard let u = updates[stock.symbol] else { return stock }
            return Stock(symbol: stock.symbol, name: stock.name,
                         price: u.price, change: u.change, pct: u.pct,
                         volume: stock.volume, high52: stock.high52, low52: stock.low52,
                         pe: stock.pe, mktCap: stock.mktCap,
                         rating: stock.rating, ratingHex: stock.ratingHex, sector: stock.sector)
        }
        checkAndTriggerSLTP()
    }

    /// +1 if price rose since last refresh, -1 if fell, 0 if unchanged.
    func priceDirection(for symbol: String, current: Double) -> Int {
        guard let prev = previousPrices[symbol], abs(current - prev) > 0.001 else { return 0 }
        return current > prev ? 1 : -1
    }

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

    // MARK: Leaderboard

    /// Incremented every 60 s by LeaderboardView so @Observable re-evaluates bot PnLs.
    var leaderboardRefreshTick = 0

    var leaderboard: [LeaderboardEntry] {
        _ = leaderboardRefreshTick  // register @Observable dependency for live updates
        var entries: [LeaderboardEntry] = [
            .init(rank: 0, name: "Atlas",  pnl: allTimeBotPnL( 2_200,  5.5, 140, 1001), winRate: 58.4, trades: 42 + botTradeOffset(1001), colorHex: 0xF59E0B, symbol: "▲"),
            .init(rank: 0, name: "Cipher", pnl: allTimeBotPnL( 1_050,  2.8,  90, 1002), winRate: 54.1, trades: 37 + botTradeOffset(1002), colorHex: 0x6D74FF, symbol: "◆"),
            .init(rank: 0, name: "Nova",   pnl: allTimeBotPnL(   380,  1.0,  70, 1003), winRate: 51.8, trades: 31 + botTradeOffset(1003), colorHex: 0x38D4FF, symbol: "★"),
            .init(rank: 0, name: "Vanta",  pnl: allTimeBotPnL(  -280, -1.8,  80, 1004), winRate: 46.2, trades: 28 + botTradeOffset(1004), colorHex: 0x4ADE80, symbol: "◉"),
            .init(rank: 0, name: "Orion",  pnl: allTimeBotPnL(  -750, -3.5, 100, 1005), winRate: 43.5, trades: 24 + botTradeOffset(1005), colorHex: 0x38D4FF, symbol: "✦"),
            .init(rank: 0, name: "Solace", pnl: allTimeBotPnL(-1_150, -2.2, 110, 1006), winRate: 40.8, trades: 19 + botTradeOffset(1006), colorHex: 0xF472B6, symbol: "◈"),
            .init(rank: 0, name: "Apex",   pnl: allTimeBotPnL(-1_900, -6.0, 130, 1007), winRate: 37.3, trades: 15 + botTradeOffset(1007), colorHex: 0xFB923C, symbol: "▲"),
            .init(rank: 0, name: userName, pnl: totalPnL, winRate: winRate * 100,
                  trades: orders.count, colorHex: 0xB06AFF, symbol: "♛", isMe: true),
        ]
        entries.sort { $0.pnl > $1.pnl }
        return entries.enumerated().map { i, e in
            LeaderboardEntry(rank: i + 1, name: e.name, pnl: e.pnl, winRate: e.winRate,
                             trades: e.trades, colorHex: e.colorHex, symbol: e.symbol, isMe: e.isMe)
        }
    }

    var weeklyLeaderboard: [LeaderboardEntry] {
        _ = leaderboardRefreshTick  // register @Observable dependency for live updates
        var entries: [LeaderboardEntry] = [
            .init(rank: 0, name: "Vanta",  pnl: weeklyBotPnL( 1.7,  55, 2001), winRate: 66.7, trades: 12 + botTradeOffset(2001), colorHex: 0x4ADE80, symbol: "◉"),
            .init(rank: 0, name: "Solace", pnl: weeklyBotPnL( 0.9,  40, 2002), winRate: 60.0, trades:  9 + botTradeOffset(2002), colorHex: 0xF472B6, symbol: "◈"),
            .init(rank: 0, name: "Nova",   pnl: weeklyBotPnL( 0.3,  30, 2003), winRate: 55.6, trades:  8 + botTradeOffset(2003), colorHex: 0x38D4FF, symbol: "★"),
            .init(rank: 0, name: "Orion",  pnl: weeklyBotPnL(-0.4,  38, 2004), winRate: 44.4, trades:  7 + botTradeOffset(2004), colorHex: 0x38D4FF, symbol: "✦"),
            .init(rank: 0, name: "Cipher", pnl: weeklyBotPnL(-0.9,  48, 2005), winRate: 40.0, trades:  6 + botTradeOffset(2005), colorHex: 0x6D74FF, symbol: "◆"),
            .init(rank: 0, name: "Atlas",  pnl: weeklyBotPnL(-1.4,  52, 2006), winRate: 37.5, trades:  8 + botTradeOffset(2006), colorHex: 0xF59E0B, symbol: "▲"),
            .init(rank: 0, name: "Apex",   pnl: weeklyBotPnL(-2.1,  60, 2007), winRate: 33.3, trades:  5 + botTradeOffset(2007), colorHex: 0xFB923C, symbol: "▲"),
            .init(rank: 0, name: userName, pnl: totalPnL, winRate: winRate * 100,
                  trades: orders.count, colorHex: 0xB06AFF, symbol: "♛", isMe: true),
        ]
        entries.sort { $0.pnl > $1.pnl }
        return entries.enumerated().map { i, e in
            LeaderboardEntry(rank: i + 1, name: e.name, pnl: e.pnl, winRate: e.winRate,
                             trades: e.trades, colorHex: e.colorHex, symbol: e.symbol, isMe: e.isMe)
        }
    }

    // MARK: Bot simulation helpers

    /// All-time PnL: base + daily trend since Jan 1 2025 + deterministic daily/hourly noise.
    private func allTimeBotPnL(_ base: Double, _ dailyDrift: Double, _ vol: Double, _ seed: UInt64) -> Double {
        let daysSinceEpoch = Date().timeIntervalSince1970 / 86_400
        let day  = Int(floor(daysSinceEpoch))
        let hour = Int((daysSinceEpoch - floor(daysSinceEpoch)) * 24)
        let elapsed     = Double(day - 20_089)  // days since Jan 1 2025
        let dailyNoise  = botNoise(seed: seed,        day: day, hour: 0)    * vol
        let hourlyNoise = botNoise(seed: seed &+ 999, day: day, hour: hour) * vol * 0.15
        return base + dailyDrift * elapsed + dailyNoise + hourlyNoise
    }

    /// Weekly PnL: resets each Monday, accumulates hourly drift + noise through the week.
    private func weeklyBotPnL(_ hourlyDrift: Double, _ vol: Double, _ seed: UInt64) -> Double {
        let now = Date()
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone.current
        let startOfWeek  = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        let hoursIntoWeek = now.timeIntervalSince(startOfWeek) / 3_600
        let dayInWeek    = Int(hoursIntoWeek / 24)
        let hourInWeek   = Int(hoursIntoWeek)
        let dailyNoise   = botNoise(seed: seed,        day: dayInWeek, hour: 0)         * vol
        let hourlyNoise  = botNoise(seed: seed &+ 999, day: dayInWeek, hour: hourInWeek) * vol * 0.2
        return hourlyDrift * hoursIntoWeek + dailyNoise + hourlyNoise
    }

    /// Deterministic value in [-0.5, 0.5] from seed + day + hour (splitmix64-style hash).
    private func botNoise(seed: UInt64, day: Int, hour: Int) -> Double {
        var v = seed
            &+ UInt64(bitPattern: Int64(day)  &* Int64(2_654_435_761))
            &+ UInt64(bitPattern: Int64(hour) &* Int64(1_013_904_223))
        v = (v ^ (v >> 30)) &* 0xBF58_476D_1CE4_E5B9
        v = (v ^ (v >> 27)) &* 0x94D0_49BB_1331_11EB
        v =  v ^ (v >> 31)
        return Double(v >> 11) / Double(1 << 53) - 0.5
    }

    /// Extra trades that vary day-to-day per bot (0–3 additional trades).
    private func botTradeOffset(_ seed: UInt64) -> Int {
        let day = Int(Date().timeIntervalSince1970 / 86_400)
        var v = seed &+ UInt64(bitPattern: Int64(day) &* Int64(1_000_003))
        v = (v ^ (v >> 30)) &* 0xBF58_476D_1CE4_E5B9
        v =  v ^ (v >> 31)
        return Int(v >> 62)  // 0–3
    }

    // MARK: Achievements

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
    var pct:         Double { guard avgCost > 0 else { return 0 }; return (current - avgCost) / avgCost * 100 }
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

enum OrderSide: String, CaseIterable, Codable {
    case buy = "BUY"
    case sell = "SELL"
}

struct TradeOrder: Identifiable, Codable {
    let id:         UUID   = UUID()
    let symbol:     String
    let name:       String
    let side:       OrderSide
    let qty:        Int
    let entryPrice: Double
    let stopLoss:   String
    let takeProfit: String
    let date:       Date   = Date()
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
