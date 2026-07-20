//
//  MarketService.swift
//  Fortune
//
//  Finnhub API service. Get a free key at https://finnhub.io
//  Replace the placeholder below with your key before running.
//

import Foundation

actor MarketService {
    static let shared = MarketService()

    private let base = "https://finnhub.io/api/v1"
    private let apiKey = "d9akmi9r01qg31s551f0d9akmi9r01qg31s551fg"

    static let watchlist = [
        "AAPL", "NVDA", "MSFT", "TSLA", "AMZN", "META",
        "GOOGL", "JPM", "AMD", "NFLX", "COIN", "V", "WMT", "INTC", "SPOT", "BABA"
    ]

    static let timeframes = ["1D", "1W", "1M", "3M"]

    static let sectors = ["All", "Tech", "Finance", "Consumer", "Media", "Crypto", "EV"]

    private static let nameMap: [String: String] = [
        "AAPL": "Apple Inc.",           "NVDA": "NVIDIA Corp.",
        "MSFT": "Microsoft Corp.",      "TSLA": "Tesla Inc.",
        "AMZN": "Amazon.com Inc.",      "META": "Meta Platforms",
        "GOOGL": "Alphabet Inc.",       "JPM":  "JPMorgan Chase",
        "AMD":  "Advanced Micro Devices","NFLX": "Netflix Inc.",
        "COIN": "Coinbase Global",      "V":    "Visa Inc.",
        "WMT":  "Walmart Inc.",         "INTC": "Intel Corp.",
        "SPOT": "Spotify Technology",   "BABA": "Alibaba Group"
    ]

    private static let sectorMap: [String: String] = [
        "AAPL": "Tech",  "NVDA": "Tech",  "MSFT": "Tech",  "AMD":  "Tech", "INTC": "Tech",
        "META": "Tech",  "GOOGL":"Tech",  "TSLA": "EV",
        "AMZN": "Consumer","WMT":"Consumer","BABA":"Consumer",
        "NFLX": "Media", "SPOT": "Media",
        "JPM":  "Finance","V":   "Finance",
        "COIN": "Crypto"
    ]

    // MARK: - Public

    // MARK: - WebSocket live feed

    /// Opens a Finnhub WebSocket and streams (symbol, price) pairs in real time.
    /// The caller is responsible for reconnecting if the stream ends.
    func liveTradeStream() -> AsyncStream<(symbol: String, price: Double)> {
        let url = URL(string: "wss://ws.finnhub.io?token=\(apiKey)")!
        let ws  = URLSession.shared.webSocketTask(with: url)
        ws.resume()

        return AsyncStream { continuation in
            Task {
                // Subscribe to every watchlist symbol
                for symbol in Self.watchlist {
                    let msg = #"{"type":"subscribe","symbol":"\#(symbol)"}"#
                    try? await ws.send(.string(msg))
                }

                continuation.onTermination = { _ in ws.cancel(with: .goingAway, reason: nil) }

                while !Task.isCancelled {
                    guard let raw = try? await ws.receive() else { break }
                    if case .string(let text) = raw,
                       let data = text.data(using: .utf8),
                       let msg  = try? JSONDecoder().decode(WSTradeMessage.self, from: data),
                       msg.type == "trade" {
                        for trade in msg.data ?? [] {
                            continuation.yield((trade.s, trade.p))
                        }
                    }
                }
                continuation.finish()
            }
        }
    }

    /// Lightweight refresh: only hits /quote (1 call per symbol instead of 3).
    func fetchQuotesOnly() async -> [String: (price: Double, change: Double, pct: Double)] {
        await withTaskGroup(of: (String, Double, Double, Double)?.self) { group in
            for symbol in Self.watchlist {
                group.addTask {
                    guard let q = try? await self.rawQuote(symbol: symbol) else { return nil }
                    return (symbol, q.current, q.change, q.percentChange)
                }
            }
            var result: [String: (Double, Double, Double)] = [:]
            for await item in group {
                if let (sym, price, change, pct) = item { result[sym] = (price, change, pct) }
            }
            return result
        }
    }

    func fetchStocks() async -> [Stock] {
        await withTaskGroup(of: Stock?.self) { group in
            for symbol in Self.watchlist {
                group.addTask { await self.buildStock(symbol: symbol) }
            }
            var result: [Stock] = []
            for await s in group { if let s { result.append(s) } }
            return result.sorted {
                (Self.watchlist.firstIndex(of: $0.symbol) ?? 0) <
                (Self.watchlist.firstIndex(of: $1.symbol) ?? 0)
            }
        }
    }

    func fetchChartData(symbol: String, timeframe: String) async -> [PricePoint] {
        let now = Int(Date().timeIntervalSince1970)
        let resolution: String
        let from: Int
        switch timeframe {
        case "1D": resolution = "5";  from = now - 86_400
        case "1W": resolution = "60"; from = now - 7  * 86_400
        case "1M": resolution = "D";  from = now - 30 * 86_400
        case "3M": resolution = "D";  from = now - 90 * 86_400
        default:   resolution = "D";  from = now - 30 * 86_400
        }
        do {
            let raw = try await rawCandles(symbol: symbol, resolution: resolution, from: from, to: now)
            guard raw.status == "ok", let closes = raw.closes, let timestamps = raw.timestamps else { return [] }
            return zip(timestamps, closes).map { ts, price in
                PricePoint(time: Self.label(ts, timeframe: timeframe), price: price)
            }
        } catch { return [] }
    }

    func fetchNewsItems() async -> [NewsItem] {
        do {
            let raw = try await rawNews()
            return raw.prefix(10).enumerated().map { i, n in
                let hoursAgo = Int((Date().timeIntervalSince1970 - Double(n.datetime)) / 3600)
                let timeStr  = hoursAgo < 1 ? "now" : "\(hoursAgo)h"
                let tag      = n.related.split(separator: ",").first.map(String.init) ?? "Macro"
                let hl       = n.headline.lowercased()
                let bullish  = ["surge","jump","rise","record","beat","gain","rally","profit","strong"]
                    .contains { hl.contains($0) }
                return NewsItem(id: i, source: n.source, headline: n.headline,
                                time: timeStr, tag: String(tag.prefix(5)), bullish: bullish)
            }
        } catch { return [] }
    }

    // MARK: - Stock builder

    private func buildStock(symbol: String) async -> Stock? {
        do {
            async let q = rawQuote(symbol: symbol)
            async let m = rawMetrics(symbol: symbol)
            async let r = rawRecommendations(symbol: symbol)
            let (quote, metrics, recs) = try await (q, m, r)
            let (rating, ratingHex) = resolveRating(recs)
            return Stock(
                symbol:    symbol,
                name:      Self.nameMap[symbol] ?? symbol,
                price:     quote.current,
                change:    quote.change,
                pct:       quote.percentChange,
                volume:    "—",
                high52:    metrics.metric.week52High ?? max(quote.high, quote.current),
                low52:     metrics.metric.week52Low  ?? min(quote.low,  quote.current),
                pe:        metrics.metric.peExclExtraTTM ?? 0,
                mktCap:    formatMarketCap(metrics.metric.marketCapitalization),
                rating:    rating,
                ratingHex: ratingHex,
                sector:    Self.sectorMap[symbol] ?? "Other"
            )
        } catch { return nil }
    }

    private func resolveRating(_ recs: [FinnhubRecommendation]) -> (String, UInt) {
        guard let r = recs.first else { return ("N/A", 0x6B7280) }
        let total = r.strongBuy + r.buy + r.hold + r.sell + r.strongSell
        guard total > 0 else { return ("N/A", 0x6B7280) }
        let bullScore = Double(r.strongBuy * 2 + r.buy) / Double(total)
        let bearScore = Double(r.strongSell * 2 + r.sell) / Double(total)
        if bullScore > 1.2 { return ("Strong Buy", 0x4ADE80) }
        if bullScore > 0.6 { return ("Buy",        0x4ADE80) }
        if bearScore > 0.6 { return ("Sell",       0xEF4444) }
        return ("Hold", 0xF59E0B)
    }

    private func formatMarketCap(_ val: Double?) -> String {
        guard let v = val, v > 0 else { return "N/A" }
        // Finnhub returns market cap in millions
        if v >= 1_000_000 { return String(format: "%.2fT", v / 1_000_000) }
        if v >= 1_000     { return String(format: "%.0fB", v / 1_000) }
        return String(format: "%.0fM", v)
    }

    private static func label(_ ts: Int, timeframe: String) -> String {
        let d   = Date(timeIntervalSince1970: TimeInterval(ts))
        let fmt = DateFormatter()
        switch timeframe {
        case "1D": fmt.dateFormat = "HH:mm"
        case "1W": fmt.dateFormat = "EEE"
        default:   fmt.dateFormat = "MMM d"
        }
        return fmt.string(from: d)
    }

    // MARK: - Raw network

    private func rawQuote(symbol: String) async throws -> FinnhubQuote {
        let (data, _) = try await URLSession.shared.data(from: endpoint("/quote", ["symbol": symbol]))
        return try JSONDecoder().decode(FinnhubQuote.self, from: data)
    }

    private func rawMetrics(symbol: String) async throws -> FinnhubMetricsResponse {
        let (data, _) = try await URLSession.shared.data(from: endpoint("/stock/metric", ["symbol": symbol, "metric": "all"]))
        return try JSONDecoder().decode(FinnhubMetricsResponse.self, from: data)
    }

    private func rawRecommendations(symbol: String) async throws -> [FinnhubRecommendation] {
        let (data, _) = try await URLSession.shared.data(from: endpoint("/stock/recommendation", ["symbol": symbol]))
        return try JSONDecoder().decode([FinnhubRecommendation].self, from: data)
    }

    private func rawCandles(symbol: String, resolution: String, from: Int, to: Int) async throws -> FinnhubCandles {
        let (data, _) = try await URLSession.shared.data(from: endpoint("/stock/candle",
            ["symbol": symbol, "resolution": resolution, "from": "\(from)", "to": "\(to)"]))
        return try JSONDecoder().decode(FinnhubCandles.self, from: data)
    }

    private func rawNews() async throws -> [FinnhubNewsItem] {
        let (data, _) = try await URLSession.shared.data(from: endpoint("/news", ["category": "general"]))
        return try JSONDecoder().decode([FinnhubNewsItem].self, from: data)
    }

    private func endpoint(_ path: String, _ params: [String: String]) -> URL {
        var comps = URLComponents(string: base + path)!
        var items = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "token", value: apiKey))
        comps.queryItems = items
        return comps.url!
    }
}

// MARK: - Finnhub response types (private)

private struct FinnhubQuote: Decodable {
    let current, change, percentChange, high, low: Double
    enum CodingKeys: String, CodingKey { case current="c", change="d", percentChange="dp", high="h", low="l" }
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        current       = (try? c.decode(Double.self, forKey: .current))       ?? 0
        change        = (try? c.decode(Double.self, forKey: .change))        ?? 0
        percentChange = (try? c.decode(Double.self, forKey: .percentChange)) ?? 0
        high          = (try? c.decode(Double.self, forKey: .high))          ?? 0
        low           = (try? c.decode(Double.self, forKey: .low))           ?? 0
    }
}

private struct FinnhubMetricsResponse: Decodable {
    let metric: FinnhubMetric
    enum CodingKeys: CodingKey { case metric }
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metric = try c.decode(FinnhubMetric.self, forKey: .metric)
    }
}

private struct FinnhubMetric: Decodable {
    let week52High, week52Low, peExclExtraTTM, marketCapitalization: Double?
    enum CodingKeys: String, CodingKey {
        case week52High = "52WeekHigh", week52Low = "52WeekLow"
        case peExclExtraTTM, marketCapitalization
    }
}

private struct FinnhubRecommendation: Decodable {
    let strongBuy, buy, hold, sell, strongSell: Int
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        strongBuy  = (try? c.decode(Int.self, forKey: .strongBuy))  ?? 0
        buy        = (try? c.decode(Int.self, forKey: .buy))        ?? 0
        hold       = (try? c.decode(Int.self, forKey: .hold))       ?? 0
        sell       = (try? c.decode(Int.self, forKey: .sell))       ?? 0
        strongSell = (try? c.decode(Int.self, forKey: .strongSell)) ?? 0
    }
    enum CodingKeys: String, CodingKey { case strongBuy, buy, hold, sell, strongSell }
}

private struct FinnhubCandles: Decodable {
    let closes: [Double]?, timestamps: [Int]?, status: String
    enum CodingKeys: String, CodingKey { case closes="c", timestamps="t", status="s" }
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        closes     = try? c.decode([Double].self, forKey: .closes)
        timestamps = try? c.decode([Int].self, forKey: .timestamps)
        status     = (try? c.decode(String.self, forKey: .status)) ?? ""
    }
}

private struct FinnhubNewsItem: Decodable {
    let headline, source, related: String
    let datetime: Int
}

// MARK: - WebSocket message types

private struct WSTradeMessage: Decodable {
    let type: String
    let data: [WSTrade]?

    struct WSTrade: Decodable {
        let s: String   // symbol
        let p: Double   // price
    }
}
