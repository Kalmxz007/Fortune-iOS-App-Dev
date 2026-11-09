//
//  PortfolioEngine.swift
//  Fortune
//
//  The trading ledger: cash, orders, open positions, realized P&L, and the
//  closed-trade journal. A plain value type with no UI, networking, or storage,
//  so every rule here is directly unit tested.
//
//  Positions are updated incrementally on each trade (O(1) per order) instead of
//  being re-derived from the full order history every time they're read.
//

import Foundation

/// An open position in the ledger.
struct Position: Equatable {
    var shares:     Int
    var costBasis:  Decimal      // total cost of the shares still held
    var openedAt:   Date
    var stopLoss:   Decimal?     // from the most recent buy
    var takeProfit: Decimal?

    var avgCost: Decimal { shares > 0 ? costBasis / Decimal(shares) : 0 }
}

struct PortfolioEngine {
    enum TradeError: Error, Equatable {
        case invalidQuantity, insufficientFunds, insufficientShares
    }

    /// Result of an executed order; `closedTrade` is set for sells.
    struct Fill {
        let order:       TradeOrder
        let closedTrade: ClosedTrade?
    }

    private(set) var startingCapital: Decimal
    private(set) var cash:            Decimal
    private(set) var orders:          [TradeOrder]  = []   // newest first
    private(set) var closedTrades:    [ClosedTrade] = []   // newest first
    private(set) var positions:       [String: Position] = [:]
    private(set) var realizedPnL:     Decimal = 0
    private(set) var winCount         = 0
    private(set) var closedTradeCount = 0

    init(startingCapital: Decimal) {
        self.startingCapital = startingCapital
        self.cash            = startingCapital
    }

    /// Restores a saved ledger. Positions are rebuilt once from the order history.
    init(startingCapital: Decimal, cash: Decimal, orders: [TradeOrder], closedTrades: [ClosedTrade],
         realizedPnL: Decimal, winCount: Int, closedTradeCount: Int) {
        self.startingCapital  = startingCapital.roundedToCents()
        self.cash             = cash.roundedToCents()
        self.orders           = orders
        self.closedTrades     = closedTrades
        self.realizedPnL      = realizedPnL.roundedToCents()
        self.winCount         = winCount
        self.closedTradeCount = closedTradeCount
        self.positions        = Self.replay(orders)
    }

    mutating func reset(startingCapital newCapital: Decimal? = nil) {
        self = PortfolioEngine(startingCapital: newCapital ?? startingCapital)
    }

    // MARK: Executing orders

    @discardableResult
    mutating func execute(_ order: TradeOrder, exitReason: ClosedTrade.ExitReason = .manual) throws -> Fill {
        guard order.qty > 0 else { throw TradeError.invalidQuantity }
        let amount = order.entryPrice * Decimal(order.qty)

        switch order.side {
        case .buy:
            guard cash >= amount else { throw TradeError.insufficientFunds }
            cash -= amount
            _ = Self.apply(order, to: &positions)
            orders.insert(order, at: 0)
            return Fill(order: order, closedTrade: nil)

        case .sell:
            guard let position = positions[order.symbol], position.shares >= order.qty else {
                throw TradeError.insufficientShares
            }
            let realized = Self.apply(order, to: &positions) ?? 0
            cash             += amount
            realizedPnL      += realized
            closedTradeCount += 1
            if realized > 0 { winCount += 1 }

            let trade = ClosedTrade(
                symbol:     order.symbol,
                name:       order.name,
                shares:     order.qty,
                entryPrice: position.avgCost.roundedToCents(),
                exitPrice:  order.entryPrice,
                pnl:        realized,
                exitReason: exitReason,
                openedAt:   position.openedAt,
                closedAt:   order.date
            )
            closedTrades.insert(trade, at: 0)
            orders.insert(order, at: 0)
            return Fill(order: order, closedTrade: trade)
        }
    }

    /// The single position-update rule, shared by live trading and history replay.
    /// Returns the realized P&L (rounded to cents) for sells, nil for buys.
    private static func apply(_ order: TradeOrder, to positions: inout [String: Position]) -> Decimal? {
        switch order.side {
        case .buy:
            var p = positions[order.symbol]
                ?? Position(shares: 0, costBasis: 0, openedAt: order.date, stopLoss: nil, takeProfit: nil)
            p.shares     += order.qty
            p.costBasis  += order.entryPrice * Decimal(order.qty)
            p.stopLoss    = order.stopLoss
            p.takeProfit  = order.takeProfit
            positions[order.symbol] = p
            return nil

        case .sell:
            guard var p = positions[order.symbol], p.shares > 0 else { return 0 }
            let sold     = min(order.qty, p.shares)
            let avgCost  = p.avgCost
            let realized = ((order.entryPrice - avgCost) * Decimal(sold)).roundedToCents()
            p.costBasis -= avgCost * Decimal(sold)
            p.shares    -= sold
            positions[order.symbol] = p.shares > 0 ? p : nil
            return realized
        }
    }

    /// Rebuilds positions from scratch by replaying orders oldest-first.
    /// Used when restoring a save, and by tests to verify the incremental positions.
    static func replay(_ orders: [TradeOrder]) -> [String: Position] {
        var positions: [String: Position] = [:]
        for order in orders.reversed() { _ = apply(order, to: &positions) }
        return positions
    }

    // MARK: Stop loss / take profit

    /// Positions whose stop loss or take profit has been crossed at the current price.
    func triggeredExits(priceOf: (String) -> Double?) -> [(symbol: String, price: Double, reason: ClosedTrade.ExitReason)] {
        positions.compactMap { symbol, p in
            guard let price = priceOf(symbol) else { return nil }
            let quote = Decimal(price: price)
            if let sl = p.stopLoss, sl > 0, quote <= sl { return (symbol, price, .stopLoss) }
            if let tp = p.takeProfit, tp > 0, quote >= tp { return (symbol, price, .takeProfit) }
            return nil
        }
        .sorted { $0.symbol < $1.symbol }
    }

    // MARK: Valuation (display)

    /// Open positions valued at the latest quote (falls back to cost if no quote yet), largest first.
    func holdings(priceOf: (String) -> Double?) -> [Holding] {
        positions.map { symbol, p in
            let avg = p.avgCost.doubleValue
            return Holding(symbol: symbol, shares: p.shares, avgCost: avg, current: priceOf(symbol) ?? avg)
        }
        .sorted { $0.marketValue > $1.marketValue }
    }

    var winRate: Double {
        closedTradeCount > 0 ? Double(winCount) / Double(closedTradeCount) : 0
    }

    /// Consecutive winning closes, most recent first.
    var currentWinStreak: Int { closedTrades.prefix(while: \.isWin).count }

    /// Longest run of consecutive winning closes ever.
    var bestWinStreak: Int {
        var best = 0, run = 0
        for trade in closedTrades {
            run = trade.isWin ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    func hasTrade(on day: Date, calendar: Calendar = .current) -> Bool {
        orders.contains { calendar.isDate($0.date, inSameDayAs: day) }
    }

    func winningCloses(on day: Date, calendar: Calendar = .current) -> Int {
        closedTrades.filter { $0.isWin && calendar.isDate($0.closedAt, inSameDayAs: day) }.count
    }

    // MARK: Equity curve

    private static let dayLabelFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    /// Total P&L after each trading day, one candle per day.
    /// Unrealized P&L uses current quotes, so this is recomputed when prices move.
    func equityCurve(priceOf: (String) -> Double?) -> [Candle] {
        var positions: [String: Position] = [:]
        var realized: Decimal = 0
        var previous = 0.0
        var result: [Candle] = []

        for order in orders.reversed() {
            realized += Self.apply(order, to: &positions) ?? 0
            let unrealized = positions.reduce(0.0) { sum, kv in
                let avg = kv.value.avgCost.doubleValue
                return sum + ((priceOf(kv.key) ?? avg) - avg) * Double(kv.value.shares)
            }
            let current = realized.doubleValue + unrealized
            let day = Self.dayLabelFormatter.string(from: order.date)
            if let last = result.last, last.day == day {
                result[result.count - 1] = Candle(day: day, open: last.open,
                                                  high: max(last.high, current), low: min(last.low, current),
                                                  close: current)
            } else {
                result.append(Candle(day: day, open: previous,
                                     high: max(previous, current), low: min(previous, current),
                                     close: current))
            }
            previous = current
        }
        return result
    }
}
