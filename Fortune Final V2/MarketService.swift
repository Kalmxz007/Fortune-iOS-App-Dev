//
//  MarketService.swift
//  Fortune
//
//  Market data service: Finnhub for quotes, fundamentals, news, and the live
//  WebSocket trade feed; Yahoo Finance for OHLC chart candles.
//
//  The Finnhub key is read from Secrets.plist (git-ignored). Copy the repo-root
//  Secrets.example.plist into this folder as Secrets.plist and add a free key
//  from https://finnhub.io
//

import Foundation

actor MarketService {
    static let shared = MarketService()

    private let base = "https://finnhub.io/api/v1"
    private let apiKey = MarketService.loadAPIKey()

    /// Reads FinnhubAPIKey from the bundled Secrets.plist; empty if missing.
    private static func loadAPIKey() -> String {
        guard let url  = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url),
              let key  = dict["FinnhubAPIKey"] as? String else { return "" }
        return key
    }

    static let watchlist = [
        "AAPL", "NVDA", "MSFT", "TSLA", "AMZN", "META",
        "GOOGL", "JPM", "AMD", "NFLX", "COIN", "V", "WMT", "INTC", "SPOT", "BABA",
        "DIS", "GS", "RIVN", "NIO", "MSTR", "MARA"
    ]


    static let sectors = ["All", "Tech", "Finance", "Consumer", "Media", "Crypto", "EV"]

    private static let nameMap: [String: String] = [
        "AAPL": "Apple Inc.",            "NVDA": "NVIDIA Corp.",
        "MSFT": "Microsoft Corp.",       "TSLA": "Tesla Inc.",
        "AMZN": "Amazon.com Inc.",       "META": "Meta Platforms",
        "GOOGL": "Alphabet Inc.",        "JPM":  "JPMorgan Chase",
        "AMD":  "Advanced Micro Devices","NFLX": "Netflix Inc.",
        "COIN": "Coinbase Global",       "V":    "Visa Inc.",
        "WMT":  "Walmart Inc.",          "INTC": "Intel Corp.",
        "SPOT": "Spotify Technology",    "BABA": "Alibaba Group",
        "DIS":  "Walt Disney Co.",       "GS":   "Goldman Sachs",
        "RIVN": "Rivian Automotive",     "NIO":  "Nio Inc.",
        "MSTR": "MicroStrategy Inc.",    "MARA": "Marathon Digital"
    ]

    private static let sectorMap: [String: String] = [
        "AAPL": "Tech",  "NVDA": "Tech",  "MSFT": "Tech",  "AMD":  "Tech", "INTC": "Tech",
        "META": "Tech",  "GOOGL":"Tech",
        "TSLA": "EV",    "RIVN": "EV",    "NIO":  "EV",
        "AMZN": "Consumer","WMT":"Consumer","BABA":"Consumer",
        "NFLX": "Media", "SPOT": "Media", "DIS":  "Media",
        "JPM":  "Finance","V":   "Finance","GS":   "Finance",
        "COIN": "Crypto", "MSTR":"Crypto", "MARA": "Crypto"
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

    /// Phase 1 load: fetches price + daily change only — 1 call per symbol (22 total).
    /// Reliably stays under Finnhub's free-tier 60 calls/minute limit.
    func fetchStocks() async -> [Stock] {
        await withTaskGroup(of: Stock?.self) { group in
            for symbol in Self.watchlist {
                group.addTask {
                    guard let q = try? await self.rawQuote(symbol: symbol) else { return nil }
                    return Stock(
                        symbol:    symbol,
                        name:      Self.nameMap[symbol] ?? symbol,
                        price:     q.current,
                        change:    q.change,
                        pct:       q.percentChange,
                        volume:    "—",
                        high52:    max(q.high, q.current),
                        low52:     min(q.low,  q.current),
                        pe:        0,
                        mktCap:    "—",
                        rating:    "—",
                        ratingHex: 0x6B7280,
                        sector:    Self.sectorMap[symbol] ?? "Other"
                    )
                }
            }
            var result: [Stock] = []
            for await s in group { if let s { result.append(s) } }
            return result.sorted {
                (Self.watchlist.firstIndex(of: $0.symbol) ?? 0) <
                (Self.watchlist.firstIndex(of: $1.symbol) ?? 0)
            }
        }
    }

    /// Phase 2 enrichment: fetches 52w range, P/E, market cap, and analyst rating for ONE symbol.
    /// Call this in batches after the initial stock list has already loaded.
    func enrichStock(symbol: String) async -> (mktCap: String, pe: Double, high52: Double, low52: Double, rating: String, ratingHex: UInt)? {
        do {
            async let m = rawMetrics(symbol: symbol)
            async let r = rawRecommendations(symbol: symbol)
            let (metrics, recs) = try await (m, r)
            let (rating, ratingHex) = resolveRating(recs)
            return (
                mktCap:    formatMarketCap(metrics.metric.marketCapitalization),
                pe:        metrics.metric.peExclExtraTTM ?? 0,
                high52:    metrics.metric.week52High ?? 0,
                low52:     metrics.metric.week52Low  ?? 0,
                rating:    rating,
                ratingHex: ratingHex
            )
        } catch { return nil }
    }

    /// Fetches full OHLC candle history from the Yahoo Finance chart API (free, no key required).
    func fetchChartData(symbol: String, timeframe: Timeframe) async -> [Candle] {
        let (interval, range): (String, String)
        switch timeframe {
        case .day:         (interval, range) = ("5m",  "1d")
        case .week:        (interval, range) = ("60m", "5d")
        case .month:       (interval, range) = ("1d",  "1mo")
        case .threeMonths: (interval, range) = ("1d",  "3mo")
        }
        let urlStr = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)"
            + "?interval=\(interval)&range=\(range)&includePrePost=false"
        guard let url = URL(string: urlStr) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        // Yahoo requires a browser-like User-Agent or it returns 401
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(YahooChartResponse.self, from: data)
            guard let result = decoded.chart.result?.first,
                  let timestamps = result.timestamp,
                  let q = result.indicators.quote.first else { return [] }
            let count = [timestamps.count, q.open.count, q.high.count, q.low.count, q.close.count].min() ?? 0
            return (0..<count).compactMap { i -> Candle? in
                let ts = timestamps[i]
                guard let o = q.open[i], let h = q.high[i],
                      let l = q.low[i],  let c = q.close[i] else { return nil }
                return Candle(day: Self.label(ts, timeframe: timeframe),
                              open: o, high: h, low: l, close: c)
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

    private static let dayTimeFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm";     return f }()
    private static let weekFormatter:    DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE HH:mm"; return f }()
    private static let monthFormatter:   DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d";     return f }()

    /// Chart x-axis label. Must be unique per bar, since Charts treats it as a category.
    private static func label(_ ts: Int, timeframe: Timeframe) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ts))
        switch timeframe {
        case .day:                  return dayTimeFormatter.string(from: d)
        case .week:                 return weekFormatter.string(from: d)
        case .month, .threeMonths:  return monthFormatter.string(from: d)
        }
    }

    // MARK: - Raw network

    private func rawQuote(symbol: String) async throws -> FinnhubQuote {
        let (data, response) = try await URLSession.shared.data(from: endpoint("/quote", ["symbol": symbol]))
        // Finnhub returns 429 + an error body when rate-limited. The lenient decoder would turn
        // that into a $0 quote, which would wipe prices and falsely trigger stop losses.
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw URLError(.badServerResponse) }
        let quote = try JSONDecoder().decode(FinnhubQuote.self, from: data)
        guard quote.current > 0 else { throw URLError(.cannotParseResponse) }
        return quote
    }

    private func rawMetrics(symbol: String) async throws -> FinnhubMetricsResponse {
        let (data, _) = try await URLSession.shared.data(from: endpoint("/stock/metric", ["symbol": symbol, "metric": "all"]))
        return try JSONDecoder().decode(FinnhubMetricsResponse.self, from: data)
    }

    private func rawRecommendations(symbol: String) async throws -> [FinnhubRecommendation] {
        let (data, _) = try await URLSession.shared.data(from: endpoint("/stock/recommendation", ["symbol": symbol]))
        return try JSONDecoder().decode([FinnhubRecommendation].self, from: data)
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

private struct FinnhubNewsItem: Decodable {
    let headline, source, related: String
    let datetime: Int
}

// MARK: - Yahoo Finance chart response types

private struct YahooChartResponse: Decodable {
    let chart: YahooChart
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chart = try c.decode(YahooChart.self, forKey: .chart)
    }
    enum CodingKeys: CodingKey { case chart }
}

private struct YahooChart: Decodable {
    let result: [YahooChartResult]?
}

private struct YahooChartResult: Decodable {
    let timestamp: [Int]?
    let indicators: YahooIndicators
}

private struct YahooIndicators: Decodable {
    let quote: [YahooQuote]
}

private struct YahooQuote: Decodable {
    // Values can be null during market closures / pre/post-hours gaps
    let open:  [Double?]
    let high:  [Double?]
    let low:   [Double?]
    let close: [Double?]
}

// MARK: - WebSocket message types

private struct WSTradeMessage: Decodable {
    let type: String
    let data: [WSTrade]?

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? ""
        data = try? c.decode([WSTrade].self, forKey: .data)
    }
    enum CodingKeys: CodingKey { case type, data }

    struct WSTrade: Decodable {
        let s: String   // symbol
        let p: Double   // price
    }
}
