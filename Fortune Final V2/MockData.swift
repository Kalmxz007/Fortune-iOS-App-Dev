//
//  MockData.swift
//  Fortune
//
//  All are sample data, can be changed for others without changing the views
//

import Foundation

enum MockData {

    // MARK: Timeframe chart data (Trade screen)

    static let chartByTimeframe: [String: [PricePoint]] = [
        "1D": [
            .init(time: "09:00", price: 208.10), .init(time: "09:30", price: 209.45),
            .init(time: "10:00", price: 208.80), .init(time: "10:30", price: 210.20),
            .init(time: "11:00", price: 211.05), .init(time: "11:30", price: 210.60),
            .init(time: "12:00", price: 212.30), .init(time: "12:30", price: 211.90),
            .init(time: "13:00", price: 213.00), .init(time: "13:30", price: 212.75),
            .init(time: "14:00", price: 213.20), .init(time: "14:30", price: 213.49),
        ],
        "1W": [
            .init(time: "Mon", price: 205.32), .init(time: "Tue", price: 207.88),
            .init(time: "Wed", price: 206.41), .init(time: "Thu", price: 210.75),
            .init(time: "Fri", price: 213.49),
        ],
        "1M": [
            .init(time: "Jun 3", price: 192.35), .init(time: "Jun 7", price: 195.87),
            .init(time: "Jun 11", price: 194.22), .init(time: "Jun 15", price: 198.56),
            .init(time: "Jun 19", price: 202.81), .init(time: "Jun 23", price: 207.14),
            .init(time: "Jun 27", price: 211.32), .init(time: "Jun 29", price: 213.49),
        ],
        "3M": [
            .init(time: "Apr 1", price: 171.83), .init(time: "Apr 15", price: 178.22),
            .init(time: "May 1", price: 181.54), .init(time: "May 15", price: 186.74),
            .init(time: "Jun 1", price: 192.35), .init(time: "Jun 15", price: 202.81),
            .init(time: "Jun 29", price: 213.49),
        ],
    ]

    static let timeframes = ["1D", "1W", "1M", "3M"]

    // MARK: Stocks

    static let stocks: [Stock] = [
        .init(symbol: "AAPL",  name: "Apple Inc.",             price: 213.49, change: +2.84,  pct: +1.35, volume: "48.2M",  high52: 237.23, low52: 164.08, pe: 34.2, mktCap: "3.27T", rating: "Buy",        ratingHex: 0x4ADE80, sector: "Tech"),
        .init(symbol: "NVDA",  name: "NVIDIA Corp.",           price: 131.38, change: +4.12,  pct: +3.24, volume: "312.5M", high52: 153.13, low52:  47.32, pe: 68.5, mktCap: "3.21T", rating: "Strong Buy", ratingHex: 0x4ADE80, sector: "Tech"),
        .init(symbol: "MSFT",  name: "Microsoft Corp.",        price: 446.37, change: -1.23,  pct: -0.28, volume: "18.7M",  high52: 468.35, low52: 309.45, pe: 38.1, mktCap: "3.32T", rating: "Buy",        ratingHex: 0x4ADE80, sector: "Tech"),
        .init(symbol: "TSLA",  name: "Tesla Inc.",             price: 248.23, change: +8.91,  pct: +3.72, volume: "94.1M",  high52: 299.29, low52: 138.80, pe: 72.3, mktCap: "794B",  rating: "Hold",       ratingHex: 0xF59E0B, sector: "EV"),
        .init(symbol: "AMZN",  name: "Amazon.com Inc.",        price: 195.61, change: -0.87,  pct: -0.44, volume: "32.4M",  high52: 201.20, low52: 118.35, pe: 43.8, mktCap: "2.09T", rating: "Buy",        ratingHex: 0x4ADE80, sector: "Consumer"),
        .init(symbol: "META",  name: "Meta Platforms",         price: 594.18, change: +11.34, pct: +1.94, volume: "11.8M",  high52: 602.95, low52: 297.44, pe: 28.7, mktCap: "1.51T", rating: "Strong Buy", ratingHex: 0x4ADE80, sector: "Tech"),
        .init(symbol: "GOOGL", name: "Alphabet Inc.",          price: 178.02, change: +1.54,  pct: +0.87, volume: "21.3M",  high52: 193.31, low52: 115.83, pe: 23.4, mktCap: "2.18T", rating: "Buy",        ratingHex: 0x4ADE80, sector: "Tech"),
        .init(symbol: "JPM",   name: "JPMorgan Chase",         price: 244.05, change: -3.12,  pct: -1.26, volume: "8.9M",   high52: 265.90, low52: 183.42, pe: 12.1, mktCap: "699B",  rating: "Buy",        ratingHex: 0x4ADE80, sector: "Finance"),
        .init(symbol: "AMD",   name: "Advanced Micro Devices", price: 174.22, change: +2.14,  pct: +1.24, volume: "42.1M",  high52: 227.30, low52:  94.26, pe: 48.3, mktCap: "282B",  rating: "Strong Buy", ratingHex: 0x4ADE80, sector: "Tech"),
        .init(symbol: "NFLX",  name: "Netflix Inc.",           price: 632.89, change: +11.57, pct: +1.86, volume: "6.4M",   high52: 691.69, low52: 344.73, pe: 42.1, mktCap: "272B",  rating: "Buy",        ratingHex: 0x4ADE80, sector: "Media"),
        .init(symbol: "COIN",  name: "Coinbase Global",        price: 224.45, change: -9.71,  pct: -4.15, volume: "18.8M",  high52: 349.75, low52:  97.09, pe: 31.8, mktCap: "54B",   rating: "Hold",       ratingHex: 0xF59E0B, sector: "Crypto"),
        .init(symbol: "V",     name: "Visa Inc.",              price: 279.18, change: +1.24,  pct: +0.45, volume: "7.2M",   high52: 290.96, low52: 220.04, pe: 30.4, mktCap: "565B",  rating: "Buy",        ratingHex: 0x4ADE80, sector: "Finance"),
        .init(symbol: "WMT",   name: "Walmart Inc.",           price: 68.92,  change: +0.21,  pct: +0.31, volume: "14.3M",  high52:  71.95, low52:  49.85, pe: 27.6, mktCap: "554B",  rating: "Buy",        ratingHex: 0x4ADE80, sector: "Consumer"),
        .init(symbol: "INTC",  name: "Intel Corp.",            price: 30.14,  change: -0.89,  pct: -2.87, volume: "55.4M",  high52:  51.28, low52:  26.86, pe: 18.2, mktCap: "128B",  rating: "Hold",       ratingHex: 0xF59E0B, sector: "Tech"),
        .init(symbol: "SPOT",  name: "Spotify Technology",     price: 312.54, change: +9.72,  pct: +3.21, volume: "3.1M",   high52: 365.37, low52: 131.56, pe: 67.4, mktCap: "61B",   rating: "Buy",        ratingHex: 0x4ADE80, sector: "Media"),
        .init(symbol: "BABA",  name: "Alibaba Group",          price: 78.23,  change: -1.13,  pct: -1.42, volume: "22.7M",  high52: 117.82, low52:  66.63, pe: 10.3, mktCap: "193B",  rating: "Hold",       ratingHex: 0xF59E0B, sector: "Consumer"),
    ]

    static let sectors = ["All", "Tech", "Finance", "Consumer", "Media", "Crypto", "EV"]

    // MARK: Holdings (Portfolio screen)

    static let holdings: [Holding] = [
        .init(symbol: "AAPL", shares: 10, avgCost: 198.20, current: 213.49),
        .init(symbol: "NVDA", shares:  5, avgCost: 118.40, current: 131.38),
        .init(symbol: "TSLA", shares:  8, avgCost: 242.10, current: 248.23),
        .init(symbol: "META", shares:  2, avgCost: 551.20, current: 594.18),
    ]

    // MARK: Market news (Portfolio screen)

    static let news: [NewsItem] = [
        .init(id: 1, source: "Bloomberg", headline: "Fed signals rates to stay higher for longer amid sticky inflation data", time: "2h", tag: "Macro", bullish: false),
        .init(id: 2, source: "Reuters",   headline: "NVIDIA posts record quarterly revenue driven by AI chip demand surge",  time: "4h", tag: "NVDA",  bullish: true),
        .init(id: 3, source: "WSJ",       headline: "Apple iPhone 16 pre-orders exceed analyst expectations by 30%",         time: "5h", tag: "AAPL",  bullish: true),
        .init(id: 4, source: "CNBC",      headline: "Tesla delivers record Q2 vehicles, stock rallies on strong margins",    time: "7h", tag: "TSLA",  bullish: true),
        .init(id: 5, source: "FT",        headline: "Meta AI ad revenue jumps 22% as Reels continues to dominate globally",  time: "9h", tag: "META",  bullish: true),
    ]

    // MARK: Prediction markets

    static let predictions: [Prediction] = [
        .init(id: 1, question: "Will the Fed cut rates at the July 2024 meeting?",
              yesOdds: 72, noOdds: 28, volume: "$4.2M", closes: "Jul 31",
              myBet: PlacedBet(side: "YES", amount: 500, potential: 694)),
        .init(id: 2, question: "Will Bitcoin reach $70K before August 2024?",
              yesOdds: 44, noOdds: 56, volume: "$12.8M", closes: "Jul 31",
              myBet: nil),
        .init(id: 3, question: "Will Apple announce an AI chip at WWDC?",
              yesOdds: 89, noOdds: 11, volume: "$1.1M", closes: "Jun 10",
              myBet: PlacedBet(side: "YES", amount: 200, potential: 225)),
        .init(id: 4, question: "Will the S&P 500 close above 5,000 in Q3?",
              yesOdds: 61, noOdds: 39, volume: "$8.4M", closes: "Sep 30",
              myBet: nil),
        .init(id: 5, question: "Will Nvidia hit $1,200 per share this quarter?",
              yesOdds: 38, noOdds: 62, volume: "$3.7M", closes: "Jul 15",
              myBet: PlacedBet(side: "NO", amount: 300, potential: 484)),
    ]

    // MARK: Leaderboard

    static let leaderboard: [LeaderboardEntry] = [
        .init(rank: 1, name: "Atlas",   pnl: 24_857.12, winRate: 72.6, trades: 156, colorHex: 0xF59E0B, symbol: "▲"),
        .init(rank: 2, name: "Cipher",  pnl: 18_392.45, winRate: 69.3, trades: 128, colorHex: 0x6D74FF, symbol: "◆"),
        .init(rank: 3, name: "Nova",    pnl: 14_672.33, winRate: 68.8, trades: 104, colorHex: 0x38D4FF, symbol: "★"),
        .init(rank: 4, name: "Monarch", pnl: 11_245.67, winRate: 64.1, trades: 97,  colorHex: 0xB06AFF, symbol: "♛", isMe: true),
        .init(rank: 5, name: "Vanta",   pnl: 9_876.34,  winRate: 63.7, trades: 88,  colorHex: 0x4ADE80, symbol: "◉"),
        .init(rank: 6, name: "Orion",   pnl: 7_654.21,  winRate: 62.3, trades: 74,  colorHex: 0x38D4FF, symbol: "✦"),
        .init(rank: 7, name: "Solace",  pnl: 6_321.98,  winRate: 61.2, trades: 68,  colorHex: 0xF472B6, symbol: "◈"),
        .init(rank: 8, name: "Apex",    pnl: 5_432.19,  winRate: 60.4, trades: 59,  colorHex: 0xFB923C, symbol: "▲"),
    ]

    // MARK: Achievements

    static let achievements: [Achievement] = [
        .init(id: 1, icon: "🔥", name: "Hot Streak",    detail: "Win 5 trades in a row",         earned: true),
        .init(id: 2, icon: "💎", name: "Diamond Hands", detail: "Hold a position for 30+ days",  earned: true),
        .init(id: 3, icon: "🧀", name: "Big Baller", detail: "Make 10K+ in Mock Cspital",  earned: true),
        .init(id: 4, icon: "⚡", name: "Speed Trader",  detail: "Execute 50 trades in one day",  earned: false),
        .init(id: 5, icon: "🏆", name: "Top Gainer",    detail: "Reach #1 on the leaderboard",   earned: false),
        .init(id: 6, icon: "🌙", name: "Night Owl",     detail: "Trade after-hours 20 times",    earned: false),
    ]

    // MARK: PnL candlestick data

    static let candles: [Candle] = [
        .init(day: "Jun 1",  open: 200,   high: 350,  low: -900,  close: -820),
        .init(day: "Jun 4",  open: -820,  high: -200, low: -1050, close: -430),
        .init(day: "Jun 7",  open: -430,  high: 400,  low: -520,  close: 190),
        .init(day: "Jun 10", open: 190,   high: 280,  low: -120,  close: -60),
        .init(day: "Jun 13", open: -60,   high: 720,  low: -100,  close: 580),
        .init(day: "Jun 16", open: 580,   high: 680,  low: 350,   close: 420),
        .init(day: "Jun 19", open: 420,   high: 1150, low: 380,   close: 1050),
        .init(day: "Jun 22", open: 1050,  high: 1200, low: 780,   close: 870),
        .init(day: "Jun 25", open: 870,   high: 1750, low: 820,   close: 1640),
        .init(day: "Jun 27", open: 1640,  high: 2050, low: 1580,  close: 1920),
        .init(day: "Jun 28", open: 1920,  high: 2350, low: 1850,  close: 2190),
        .init(day: "Jun 29", open: 2190,  high: 2680, low: 2100,  close: 2542),
    ]
}
