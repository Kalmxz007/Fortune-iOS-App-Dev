//
//  MarketDataStore.swift
//  Fortune
//
//  Live market data for the UI: quotes, fundamentals, chart candles, news,
//  and the WebSocket price feed. Knows nothing about the user's portfolio;
//  AppModel reacts to price changes through `onPricesChanged`.
//

import Foundation
import Observation

@Observable
final class MarketDataStore {
    private(set) var stocks: [Stock] = []
    private(set) var news:   [NewsItem] = []
    private(set) var chartData: [String: [Candle]] = [:]
    private(set) var isLoading = false
    private(set) var isRefreshingPrices = false

    /// Called after any price update (REST refresh or WebSocket tick).
    @ObservationIgnored var onPricesChanged: (_ fromLiveFeed: Bool) -> Void = { _ in }

    // Symbol → index into `stocks`, so lookups are O(1) instead of a linear search per row.
    // Must stay observed: a lookup made before prices load reads only this index, and views
    // need that read to register a dependency so they refresh when the stocks arrive.
    private var index: [String: Int] = [:]
    // Price before the latest update, used to flash rows green/red.
    private var previousPrices: [String: Double] = [:]
    @ObservationIgnored private var isLoadingMarketData = false
    // WebSocket throttle: last time each symbol was pushed to the UI
    @ObservationIgnored private var lastLiveUpdate: [String: Date] = [:]

    // MARK: Lookups

    func stock(for symbol: String) -> Stock? {
        index[symbol].map { stocks[$0] }
    }

    func price(of symbol: String) -> Double? {
        stock(for: symbol)?.price
    }

    /// +1 if price rose since the last update, -1 if it fell, 0 if unchanged.
    func priceDirection(for symbol: String, current: Double) -> Int {
        guard let prev = previousPrices[symbol], abs(current - prev) > 0.001 else { return 0 }
        return current > prev ? 1 : -1
    }

    static func chartKey(_ symbol: String, _ timeframe: Timeframe) -> String {
        "\(symbol)_\(timeframe.rawValue)"
    }

    /// Replaces the stock list and rebuilds the index. Also used by tests to inject prices.
    func setStocks(_ newStocks: [Stock]) {
        stocks = newStocks
        index = Dictionary(newStocks.enumerated().map { ($1.symbol, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Loading

    func loadMarketData() async {
        // Prevent duplicate loads (e.g. RootView and TradeView both firing at launch)
        guard !isLoadingMarketData else { return }
        isLoadingMarketData = true
        defer { isLoadingMarketData = false }
        isLoading = true

        // Phase 1: quotes only — one Finnhub call per symbol, so prices appear within ~1–2 s.
        async let baseStocks = MarketService.shared.fetchStocks()
        async let newsItems  = MarketService.shared.fetchNewsItems()
        var (fetched, fetchedNews) = await (baseStocks, newsItems)

        // The first requests after launch occasionally fail (network not ready yet);
        // retry with a short backoff before showing the error state.
        for attempt in 1...2 where fetched.isEmpty && !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double(attempt) * 1.5))
            fetched = await MarketService.shared.fetchStocks()
        }

        if !fetched.isEmpty     { setStocks(fetched) }
        if !fetchedNews.isEmpty { news = fetchedNews }
        isLoading = false

        // Phase 2: enrich with 52-week range, P/E, market cap, and analyst rating.
        // 2 calls per symbol in batches of 5 with 300 ms gaps, to stay under 60 calls/minute.
        let symbols = MarketService.watchlist
        for batchStart in stride(from: 0, to: symbols.count, by: 5) {
            guard !Task.isCancelled else { break }
            let batch = Array(symbols[batchStart ..< min(batchStart + 5, symbols.count)])
            let enrichments = await withTaskGroup(
                of: (String, String, Double, Double, Double, String, UInt)?.self
            ) { group in
                for symbol in batch {
                    group.addTask {
                        guard let d = await MarketService.shared.enrichStock(symbol: symbol) else { return nil }
                        return (symbol, d.mktCap, d.pe, d.high52, d.low52, d.rating, d.ratingHex)
                    }
                }
                var out: [(String, String, Double, Double, Double, String, UInt)] = []
                for await r in group { if let r { out.append(r) } }
                return out
            }
            for (sym, mktCap, pe, high52, low52, rating, ratingHex) in enrichments {
                guard let i = index[sym] else { continue }
                let s = stocks[i]
                stocks[i] = Stock(
                    symbol: s.symbol, name: s.name,
                    price:  s.price,  change: s.change, pct: s.pct, volume: s.volume,
                    high52: high52 > 0 ? high52 : s.high52,
                    low52:  low52  > 0 ? low52  : s.low52,
                    pe:     pe, mktCap: mktCap,
                    rating: rating, ratingHex: ratingHex,
                    sector: s.sector
                )
            }
            if batchStart + 5 < symbols.count {
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    func loadChartData(symbol: String, timeframe: Timeframe) async {
        let key = Self.chartKey(symbol, timeframe)
        guard chartData[key] == nil else { return }
        let points = await MarketService.shared.fetchChartData(symbol: symbol, timeframe: timeframe)
        if !points.isEmpty { chartData[key] = points }
    }

    func refreshChart(symbol: String, timeframe: Timeframe) async {
        let points = await MarketService.shared.fetchChartData(symbol: symbol, timeframe: timeframe)
        if !points.isEmpty { chartData[Self.chartKey(symbol, timeframe)] = points }
    }

    // MARK: Price updates

    /// Lightweight price-only refresh: one /quote call per symbol, fundamentals preserved.
    func refreshPrices() async {
        isRefreshingPrices = true
        defer { isRefreshingPrices = false }
        let updates = await MarketService.shared.fetchQuotesOnly()
        guard !updates.isEmpty else { return }
        previousPrices = Dictionary(uniqueKeysWithValues: stocks.map { ($0.symbol, $0.price) })
        for (i, stock) in stocks.enumerated() {
            guard let u = updates[stock.symbol] else { continue }
            stocks[i] = stock.withPrice(u.price, change: u.change, pct: u.pct)
        }
        onPricesChanged(false)
    }

    /// Streams real-time trade prices from the Finnhub WebSocket.
    /// Throttled to one UI update per symbol every 2 s (large caps trade thousands of
    /// times a minute) and ignores sub-cent moves. Reconnects automatically.
    func startLivePriceStream() async {
        while !Task.isCancelled {
            for await (symbol, price) in await MarketService.shared.liveTradeStream() {
                let now = Date()
                if let last = lastLiveUpdate[symbol], now.timeIntervalSince(last) < 2 { continue }
                guard let i = index[symbol] else { continue }
                let s = stocks[i]
                guard abs(price - s.price) >= 0.01 else { continue }

                lastLiveUpdate[symbol] = now
                let prevClose = s.price - s.change
                let change    = price - prevClose
                let pct       = prevClose > 0 ? change / prevClose * 100 : s.pct
                previousPrices[symbol] = s.price
                stocks[i] = s.withPrice(price, change: change, pct: pct)
                onPricesChanged(true)
            }
            // Stream ended (disconnect/error) — wait, then reconnect
            try? await Task.sleep(for: .seconds(3))
        }
    }
}
