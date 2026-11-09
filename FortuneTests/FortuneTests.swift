//
//  FortuneTests.swift
//  FortuneTests
//
//  Unit tests for the trading engine in AppModel: cost basis, realized P&L,
//  stop-loss / take-profit execution, streaks, challenge XP, price alerts,
//  persistence, and market-hours detection.
//

import Foundation
import Testing
@testable import Fortune_Final_V2

@MainActor
struct AppModelTests {

    /// Each test gets its own isolated UserDefaults so nothing leaks between tests
    /// or into the real app's saved state.
    private func makeModel() throws -> (AppModel, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: "FortuneTests-\(UUID().uuidString)"))
        return (AppModel(defaults: defaults), defaults)
    }

    private func stock(_ symbol: String, _ price: Double) -> Stock {
        Stock(symbol: symbol, name: symbol, price: price, change: 0, pct: 0, volume: "—",
              high52: price, low52: price, pe: 0, mktCap: "—", rating: "—",
              ratingHex: 0x6B7280, sector: "Tech")
    }

    private func buy(_ symbol: String, _ qty: Int, at price: Double,
                     stopLoss: Double? = nil, takeProfit: Double? = nil) -> TradeOrder {
        TradeOrder(symbol: symbol, name: symbol, side: .buy, qty: qty, entryPrice: price,
                   stopLoss: stopLoss, takeProfit: takeProfit)
    }

    private func sell(_ symbol: String, _ qty: Int, at price: Double) -> TradeOrder {
        TradeOrder(symbol: symbol, name: symbol, side: .sell, qty: qty, entryPrice: price,
                   stopLoss: nil, takeProfit: nil)
    }

    // MARK: Orders & cost basis

    @Test func buyDeductsCashAndOpensPosition() throws {
        let (model, _) = try makeModel()
        model.placeOrder(buy("AAPL", 10, at: 100))

        #expect(model.balance == 9_000)
        #expect(model.holdings.count == 1)
        #expect(model.holdings.first?.shares == 10)
        #expect(model.holdings.first?.avgCost == 100)
    }

    @Test func repeatedBuysAverageTheCostBasis() throws {
        let (model, _) = try makeModel()
        model.placeOrder(buy("AAPL", 10, at: 100))
        model.placeOrder(buy("AAPL", 10, at: 200))

        #expect(model.holdings.first?.shares == 20)
        #expect(model.holdings.first?.avgCost == 150)
    }

    @Test func buyIsRejectedWithInsufficientFunds() throws {
        let (model, _) = try makeModel()
        model.placeOrder(buy("NVDA", 1_000, at: 500))

        #expect(model.balance == 10_000)
        #expect(model.orders.isEmpty)
        #expect(model.holdings.isEmpty)
    }

    @Test func partialSellRealizesProfitAgainstAverageCost() throws {
        let (model, _) = try makeModel()
        model.placeOrder(buy("AAPL", 10, at: 100))
        model.placeOrder(sell("AAPL", 4, at: 120))

        #expect(model.realizedPnL == 80)
        #expect(model.holdings.first?.shares == 6)
        #expect(model.balance == 10_000 - 1_000 + 480)
        #expect(model.closedTradeCount == 1)
        #expect(model.winCount == 1)
        #expect(model.closedTrades.first?.pnl == 80)
    }

    // MARK: Stop loss / take profit

    @Test func stopLossAutoClosesPosition() throws {
        let (model, _) = try makeModel()
        model.placeOrder(buy("TSLA", 10, at: 100, stopLoss: 95, takeProfit: 120))
        model.stocks = [stock("TSLA", 94)]
        model.checkAndTriggerSLTP()

        #expect(model.holdings.isEmpty)
        #expect(model.realizedPnL == -60)
        #expect(model.closedTrades.first?.exitReason == .stopLoss)
        #expect(model.lastAlert?.contains("Stop Loss") == true)
    }

    @Test func takeProfitAutoClosesPosition() throws {
        let (model, _) = try makeModel()
        model.placeOrder(buy("TSLA", 10, at: 100, stopLoss: 95, takeProfit: 120))
        model.stocks = [stock("TSLA", 121)]
        model.checkAndTriggerSLTP()

        #expect(model.holdings.isEmpty)
        #expect(model.realizedPnL == 210)
        #expect(model.closedTrades.first?.exitReason == .takeProfit)
    }

    @Test func priceBetweenStopAndTargetKeepsPositionOpen() throws {
        let (model, _) = try makeModel()
        model.placeOrder(buy("TSLA", 10, at: 100, stopLoss: 95, takeProfit: 120))
        model.stocks = [stock("TSLA", 105)]
        model.checkAndTriggerSLTP()

        #expect(model.holdings.first?.shares == 10)
        #expect(model.closedTrades.isEmpty)
    }

    // MARK: Streaks & XP

    @Test func winStreaksCountConsecutiveWins() throws {
        let (model, _) = try makeModel()
        // win, win, loss, win (oldest → newest)
        for exit in [110.0, 110, 90, 110] {
            model.placeOrder(buy("AMD", 1, at: 100))
            model.placeOrder(sell("AMD", 1, at: exit))
        }

        #expect(model.currentWinStreak == 1)
        #expect(model.bestWinStreak == 2)
    }

    @Test func dailyChallengeXPIsAwardedOnlyOnce() throws {
        let (model, _) = try makeModel()
        model.placeOrder(buy("AAPL", 1, at: 100))
        #expect(model.bonusXP == 50)            // First Blood

        model.placeOrder(buy("AAPL", 1, at: 100))
        #expect(model.bonusXP == 50)            // not awarded twice
    }

    @Test func diversifyChallengeAwardsXPAtThreeHoldings() throws {
        let (model, _) = try makeModel()
        model.placeOrder(buy("AAPL", 1, at: 100))
        model.placeOrder(buy("MSFT", 1, at: 100))
        model.placeOrder(buy("NVDA", 1, at: 100))

        #expect(model.bonusXP == 50 + 100)
        #expect(model.dailyChallenges.first { $0.id == "diversify" }?.done == true)
    }

    // MARK: Price alerts

    @Test func priceAlertFiresOnceWhenTargetIsCrossed() throws {
        let (model, _) = try makeModel()
        model.priceAlerts = [
            PriceAlert(symbol: "AAPL", target: 110, above: true),
            PriceAlert(symbol: "AAPL", target: 90,  above: false),
        ]
        model.stocks = [stock("AAPL", 111)]
        model.checkPriceAlerts()

        #expect(model.priceAlerts.count == 1)
        #expect(model.priceAlerts.first?.above == false)
        #expect(model.lastAlert?.contains("AAPL") == true)
    }

    // MARK: Persistence

    @Test func stateSurvivesRelaunch() throws {
        let (model, defaults) = try makeModel()
        model.placeOrder(buy("AAPL", 5, at: 100))
        model.priceAlerts = [PriceAlert(symbol: "AAPL", target: 150, above: true)]
        model.toggleStar("NVDA")
        model.save()

        let relaunched = AppModel(defaults: defaults)
        #expect(relaunched.balance == 9_500)
        #expect(relaunched.holdings.first?.shares == 5)
        #expect(relaunched.priceAlerts.first?.target == 150)
        #expect(relaunched.isStarred("NVDA"))
        #expect(relaunched.bonusXP == 50)
    }

    /// Saves written before values were typed stored them as strings ("" = none).
    @Test func legacyStringBasedSaveStillLoads() throws {
        let defaults = try #require(UserDefaults(suiteName: "FortuneTests-\(UUID().uuidString)"))
        let legacy = """
        {"onboarded":true,"userName":"Old","balance":9500,"startingCapital":10000,
         "joinDate":0,"experience":"pro","goal":"beat","frequency":"swing","risk":"aggressive",
         "preferredSectors":[],"realizedPnL":0,"winCount":0,"closedTradeCount":0,"closedTrades":[],
         "orders":[{"id":"7E57A6F2-0000-4000-8000-000000000001","symbol":"AAPL","name":"Apple",
                    "side":"BUY","qty":5,"entryPrice":100,"stopLoss":"95","takeProfit":"","date":0}],
         "priceAlerts":[{"id":"7E57A6F2-0000-4000-8000-000000000002","symbol":"AAPL",
                         "target":"150","above":true}]}
        """
        defaults.set(Data(legacy.utf8), forKey: "fortune_state_v1")

        let model = AppModel(defaults: defaults)
        #expect(model.onboarded)
        #expect(model.risk == .aggressive)
        #expect(model.experience == .pro)
        #expect(model.defaultTimeframe == .week)
        #expect(model.orders.first?.stopLoss == 95)
        #expect(model.orders.first?.takeProfit == nil)
        #expect(model.priceAlerts.first?.target == 150)
    }

    @Test func onboardingStartsAFreshPortfolio() throws {
        let (model, _) = try makeModel()
        model.placeOrder(buy("AAPL", 5, at: 100))
        model.signOut()

        var data = OnboardingData()
        data.name = "Alex"
        data.capital = .hundredThousand
        model.completeOnboarding(data)

        #expect(model.orders.isEmpty)
        #expect(model.holdings.isEmpty)
        #expect(model.bonusXP == 0)
        #expect(model.balance == 100_000)
    }

    // MARK: P&L chart

    @Test func pnlChartHasOneCandlePerDay() throws {
        let (model, _) = try makeModel()
        model.placeOrder(buy("AAPL", 1, at: 100))
        model.placeOrder(buy("MSFT", 1, at: 100))
        model.placeOrder(sell("AAPL", 1, at: 110))

        #expect(model.pnlCandles.count == 1)
        #expect(model.pnlCandles.first?.close == 10)
    }
}

// MARK: - Market hours

struct MarketHoursTests {

    /// Builds a date from New York wall-clock components.
    private func newYork(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) throws -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        return try #require(cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)))
    }

    @Test(arguments: [
        (9, 29, true),    // pre-market
        (9, 30, false),   // opening bell
        (12, 0, false),   // midday
        (15, 59, false),  // last minute
        (16, 0, true),    // closing bell
        (20, 0, true),    // evening
    ])
    func weekdayHours(hour: Int, minute: Int, outside: Bool) async throws {
        // Wednesday, Nov 4 2026
        let date = try newYork(2026, 11, 4, hour, minute)
        #expect(await MarketHours.isOutsideRegularSession(date) == outside)
    }

    @Test func weekendsAreAlwaysOutsideMarketHours() async throws {
        // Saturday, Nov 7 2026 at noon
        let date = try newYork(2026, 11, 7, 12, 0)
        #expect(await MarketHours.isOutsideRegularSession(date))
    }
}

// MARK: - Formatting

struct FormattingTests {

    @Test(arguments: [
        (12.5,   "+$12.50"),
        (-3.1,   "-$3.10"),
        (-0.001, "$0.00"),    // rounds to zero → no "-$0.00"
        (0.0,    "$0.00"),
    ])
    func signedMoney(value: Double, expected: String) async {
        #expect(await value.signedMoney() == expected)
    }

    @Test func signedPercentNeverShowsNegativeZero() async {
        #expect(await (-0.0001).signedPercent() == "0.00%")
        #expect(await 1.256.signedPercent() == "+1.26%")
    }
}

// MARK: - Portfolio engine

@MainActor
struct PortfolioEngineTests {

    private func order(_ side: OrderSide, _ symbol: String, _ qty: Int, at price: Double) -> TradeOrder {
        TradeOrder(symbol: symbol, name: symbol, side: side, qty: qty, entryPrice: price,
                   stopLoss: nil, takeProfit: nil)
    }

    @Test func incrementalPositionsMatchFullReplay() throws {
        var engine = PortfolioEngine(startingCapital: 100_000)
        let script: [(OrderSide, String, Int, Double)] = [
            (.buy, "AAPL", 10, 101.25), (.buy, "MSFT", 4, 310.10), (.buy, "AAPL", 5, 98.40),
            (.sell, "AAPL", 7, 104.00), (.buy, "NVDA", 3, 880.55), (.sell, "MSFT", 4, 305.00),
            (.sell, "AAPL", 8, 99.99), (.buy, "MSFT", 2, 300.00),
        ]
        for (side, symbol, qty, price) in script {
            try engine.execute(order(side, symbol, qty, at: price))
            // After every trade, the incrementally maintained positions must equal a from-scratch replay
            #expect(engine.positions == PortfolioEngine.replay(engine.orders))
        }
        #expect(engine.positions["AAPL"] == nil)   // fully closed
        #expect(engine.positions["MSFT"]?.shares == 2)
    }

    @Test func decimalLedgerKeepsCentsExact() throws {
        // 33.33 × 3 in Double is 99.99000000000001; in the Decimal ledger it's exactly 99.99
        var engine = PortfolioEngine(startingCapital: 100)
        try engine.execute(order(.buy, "X", 3, at: 33.33))
        #expect(engine.cash == Decimal(string: "0.01"))

        try engine.execute(order(.sell, "X", 3, at: 33.34))
        #expect(engine.cash == Decimal(string: "100.03"))
        #expect(engine.realizedPnL == Decimal(string: "0.03"))
    }

    @Test func cannotSellMoreThanHeld() throws {
        var engine = PortfolioEngine(startingCapital: 1_000)
        try engine.execute(order(.buy, "AAPL", 2, at: 100))
        #expect(throws: PortfolioEngine.TradeError.insufficientShares) {
            try engine.execute(order(.sell, "AAPL", 3, at: 100))
        }
        #expect(engine.positions["AAPL"]?.shares == 2)
    }
}

// MARK: - Stock filter

@MainActor
struct StockFilterTests {

    private func stock(_ symbol: String, pct: Double, price: Double = 100, sector: String = "Tech") -> Stock {
        Stock(symbol: symbol, name: symbol, price: price, change: 0, pct: pct, volume: "—",
              high52: price, low52: price, pe: 0, mktCap: "—", rating: "—",
              ratingHex: 0, sector: sector)
    }

    private func symbols(_ filter: StockFilter, _ stocks: [Stock], starred: Set<String> = []) -> [String] {
        filter.apply(to: stocks, isStarred: { starred.contains($0) }).map { $0.symbol }
    }

    @Test func filtersBySectorSearchAndStars() {
        let stocks = [stock("AAPL", pct: 1), stock("JPM", pct: 2, sector: "Finance"), stock("NVDA", pct: 3)]

        var filter = StockFilter()
        filter.sector = "Tech"
        #expect(symbols(filter, stocks) == ["AAPL", "NVDA"])

        filter.search = "nv"
        #expect(symbols(filter, stocks) == ["NVDA"])

        filter = StockFilter()
        filter.sector = StockFilter.starredChip
        #expect(symbols(filter, stocks, starred: ["JPM"]) == ["JPM"])
    }

    @Test func sortsAndPicksMoversBySign() {
        let stocks = [stock("A", pct: -2), stock("B", pct: 5), stock("C", pct: 1), stock("D", pct: -4)]

        var filter = StockFilter()
        filter.sort = .losers
        #expect(symbols(filter, stocks) == ["D", "A", "C", "B"])

        #expect(StockFilter.movers(in: stocks, gainers: true).map { $0.symbol } == ["B", "C"])
        #expect(StockFilter.movers(in: stocks, gainers: false).map { $0.symbol } == ["D", "A"])
    }
}

// MARK: - Practice League

@MainActor
struct PracticeLeagueTests {

    private let fixedNow = Date(timeIntervalSince1970: 1_793_000_000)

    @Test func rankingIsByPercentReturnNotDollars() {
        // +$100 on a $1K account (+10%) must outrank +$5,000 on a $1M account (+0.5%)
        let small = LeagueStanding(name: "Small", pnl: 100, startingCapital: 1_000, winRate: 0, trades: 1)
        let big   = LeagueStanding(name: "Big", pnl: 5_000, startingCapital: 1_000_000, winRate: 0, trades: 1)
        let smallReturn = PracticeLeague.allTime(me: small, now: fixedNow).first { $0.isMe }?.returnPct
        let bigReturn   = PracticeLeague.allTime(me: big,   now: fixedNow).first { $0.isMe }?.returnPct

        #expect(smallReturn == 10)
        #expect(bigReturn == 0.5)
    }

    @Test func entriesAreSortedAndRankedFromOne() {
        let me = LeagueStanding(name: "Me", pnl: 0, startingCapital: 10_000, winRate: 0, trades: 0)
        let board = PracticeLeague.weekly(me: me, now: fixedNow)
        let ranks = board.map { $0.rank }
        let isSorted = zip(board, board.dropFirst()).allSatisfy { $0.returnPct >= $1.returnPct }
        let myCount  = board.filter { $0.isMe }.count
        let botCount = board.filter { $0.isBot }.count

        #expect(ranks == Array(1...board.count))
        #expect(isSorted)
        #expect(myCount == 1)
        #expect(botCount == board.count - 1)
    }
}
