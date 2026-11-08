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
                     stopLoss: String = "", takeProfit: String = "") -> TradeOrder {
        TradeOrder(symbol: symbol, name: symbol, side: .buy, qty: qty, entryPrice: price,
                   stopLoss: stopLoss, takeProfit: takeProfit)
    }

    private func sell(_ symbol: String, _ qty: Int, at price: Double) -> TradeOrder {
        TradeOrder(symbol: symbol, name: symbol, side: .sell, qty: qty, entryPrice: price,
                   stopLoss: "", takeProfit: "")
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
        model.placeOrder(buy("TSLA", 10, at: 100, stopLoss: "95", takeProfit: "120"))
        model.stocks = [stock("TSLA", 94)]
        model.checkAndTriggerSLTP()

        #expect(model.holdings.isEmpty)
        #expect(model.realizedPnL == -60)
        #expect(model.closedTrades.first?.exitReason == .stopLoss)
        #expect(model.lastAlert?.contains("Stop Loss") == true)
    }

    @Test func takeProfitAutoClosesPosition() throws {
        let (model, _) = try makeModel()
        model.placeOrder(buy("TSLA", 10, at: 100, stopLoss: "95", takeProfit: "120"))
        model.stocks = [stock("TSLA", 121)]
        model.checkAndTriggerSLTP()

        #expect(model.holdings.isEmpty)
        #expect(model.realizedPnL == 210)
        #expect(model.closedTrades.first?.exitReason == .takeProfit)
    }

    @Test func priceBetweenStopAndTargetKeepsPositionOpen() throws {
        let (model, _) = try makeModel()
        model.placeOrder(buy("TSLA", 10, at: 100, stopLoss: "95", takeProfit: "120"))
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
            PriceAlert(symbol: "AAPL", target: "110", above: true),
            PriceAlert(symbol: "AAPL", target: "90",  above: false),
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
        model.priceAlerts = [PriceAlert(symbol: "AAPL", target: "150", above: true)]
        model.toggleStar("NVDA")
        model.save()

        let relaunched = AppModel(defaults: defaults)
        #expect(relaunched.balance == 9_500)
        #expect(relaunched.holdings.first?.shares == 5)
        #expect(relaunched.priceAlerts.first?.target == "150")
        #expect(relaunched.isStarred("NVDA"))
        #expect(relaunched.bonusXP == 50)
    }

    @Test func onboardingStartsAFreshPortfolio() throws {
        let (model, _) = try makeModel()
        model.placeOrder(buy("AAPL", 5, at: 100))
        model.signOut()

        var data = OnboardingData()
        data.name = "Alex"
        data.capital = "100k"
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
        #expect(await AppModel.isOutsideMarketHours(date) == outside)
    }

    @Test func weekendsAreAlwaysOutsideMarketHours() async throws {
        // Saturday, Nov 7 2026 at noon
        let date = try newYork(2026, 11, 7, 12, 0)
        #expect(await AppModel.isOutsideMarketHours(date))
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
