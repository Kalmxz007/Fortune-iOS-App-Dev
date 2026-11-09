//
//  PracticeLeague.swift
//  Fortune
//
//  The Practice League: the user ranked against simulated traders.
//  Everyone is ranked by % return, so a $1K account competes fairly with a $1M one.
//

import SwiftUI

struct LeaderboardEntry: Identifiable {
    let rank:      Int
    let name:      String
    let returnPct: Double
    let pnl:       Double
    let winRate:   Double
    let trades:    Int
    let colorHex:  UInt
    let symbol:    String
    var isMe:      Bool = false

    var isBot: Bool  { !isMe }
    var id:    Int   { rank }
    var color: Color { Color(hex: colorHex) }
}

/// The user's numbers for one leaderboard period.
struct LeagueStanding {
    let name:            String
    let pnl:             Double
    let startingCapital: Double
    let winRate:         Double
    let trades:          Int
}

enum PracticeLeague {

    /// Simulated traders all start from this balance; their P&L is converted to % return against it.
    static let botStartingCapital = 10_000.0

    private struct Bot {
        let name: String, colorHex: UInt, symbol: String
        let base: Double, drift: Double, vol: Double, seed: UInt64
        let winRate: Double, trades: Int
    }

    private static let allTimeBots: [Bot] = [
        .init(name: "Atlas",  colorHex: 0xF59E0B, symbol: "▲", base:  2_200, drift:  5.5, vol: 140, seed: 1001, winRate: 58.4, trades: 42),
        .init(name: "Cipher", colorHex: 0x6D74FF, symbol: "◆", base:  1_050, drift:  2.8, vol:  90, seed: 1002, winRate: 54.1, trades: 37),
        .init(name: "Nova",   colorHex: 0x38D4FF, symbol: "★", base:    380, drift:  1.0, vol:  70, seed: 1003, winRate: 51.8, trades: 31),
        .init(name: "Vanta",  colorHex: 0x4ADE80, symbol: "◉", base:   -280, drift: -1.8, vol:  80, seed: 1004, winRate: 46.2, trades: 28),
        .init(name: "Orion",  colorHex: 0x38D4FF, symbol: "✦", base:   -750, drift: -3.5, vol: 100, seed: 1005, winRate: 43.5, trades: 24),
        .init(name: "Solace", colorHex: 0xF472B6, symbol: "◈", base: -1_150, drift: -2.2, vol: 110, seed: 1006, winRate: 40.8, trades: 19),
        .init(name: "Apex",   colorHex: 0xFB923C, symbol: "▲", base: -1_900, drift: -6.0, vol: 130, seed: 1007, winRate: 37.3, trades: 15),
    ]

    /// Weekly bots have no base; `drift` is per hour since Monday.
    private static let weeklyBots: [Bot] = [
        .init(name: "Vanta",  colorHex: 0x4ADE80, symbol: "◉", base: 0, drift:  1.7, vol: 55, seed: 2001, winRate: 66.7, trades: 12),
        .init(name: "Solace", colorHex: 0xF472B6, symbol: "◈", base: 0, drift:  0.9, vol: 40, seed: 2002, winRate: 60.0, trades:  9),
        .init(name: "Nova",   colorHex: 0x38D4FF, symbol: "★", base: 0, drift:  0.3, vol: 30, seed: 2003, winRate: 55.6, trades:  8),
        .init(name: "Orion",  colorHex: 0x38D4FF, symbol: "✦", base: 0, drift: -0.4, vol: 38, seed: 2004, winRate: 44.4, trades:  7),
        .init(name: "Cipher", colorHex: 0x6D74FF, symbol: "◆", base: 0, drift: -0.9, vol: 48, seed: 2005, winRate: 40.0, trades:  6),
        .init(name: "Atlas",  colorHex: 0xF59E0B, symbol: "▲", base: 0, drift: -1.4, vol: 52, seed: 2006, winRate: 37.5, trades:  8),
        .init(name: "Apex",   colorHex: 0xFB923C, symbol: "▲", base: 0, drift: -2.1, vol: 60, seed: 2007, winRate: 33.3, trades:  5),
    ]

    static func allTime(me: LeagueStanding, now: Date = Date()) -> [LeaderboardEntry] {
        rank(me: me, bots: allTimeBots.map { ($0, allTimePnL($0, now: now)) }, now: now)
    }

    static func weekly(me: LeagueStanding, now: Date = Date()) -> [LeaderboardEntry] {
        rank(me: me, bots: weeklyBots.map { ($0, weeklyPnL($0, now: now)) }, now: now)
    }

    /// Start of the current ISO week (Monday 00:00 local time).
    static func startOfWeek(_ now: Date = Date()) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
    }

    // MARK: Ranking

    private static func rank(me: LeagueStanding, bots: [(Bot, Double)], now: Date) -> [LeaderboardEntry] {
        var entries = bots.map { bot, pnl in
            LeaderboardEntry(rank: 0, name: bot.name, returnPct: pnl / botStartingCapital * 100, pnl: pnl,
                             winRate: bot.winRate, trades: bot.trades + tradeOffset(bot.seed, now: now),
                             colorHex: bot.colorHex, symbol: bot.symbol)
        }
        let myReturn = me.startingCapital > 0 ? me.pnl / me.startingCapital * 100 : 0
        entries.append(LeaderboardEntry(rank: 0, name: me.name, returnPct: myReturn, pnl: me.pnl,
                                        winRate: me.winRate, trades: me.trades,
                                        colorHex: 0xB06AFF, symbol: "♛", isMe: true))
        entries.sort { $0.returnPct > $1.returnPct }
        return entries.enumerated().map { i, e in
            LeaderboardEntry(rank: i + 1, name: e.name, returnPct: e.returnPct, pnl: e.pnl,
                             winRate: e.winRate, trades: e.trades,
                             colorHex: e.colorHex, symbol: e.symbol, isMe: e.isMe)
        }
    }

    // MARK: Bot simulation

    /// Base + daily drift since Jan 1 2025 + deterministic daily/hourly noise.
    private static func allTimePnL(_ bot: Bot, now: Date) -> Double {
        let daysSinceEpoch = now.timeIntervalSince1970 / 86_400
        let day  = Int(floor(daysSinceEpoch))
        let hour = Int((daysSinceEpoch - floor(daysSinceEpoch)) * 24)
        let elapsed     = Double(day - 20_089)  // days since Jan 1 2025
        let dailyNoise  = noise(seed: bot.seed,        day: day, hour: 0)    * bot.vol
        let hourlyNoise = noise(seed: bot.seed &+ 999, day: day, hour: hour) * bot.vol * 0.15
        return bot.base + bot.drift * elapsed + dailyNoise + hourlyNoise
    }

    /// Resets each Monday; accumulates hourly drift + noise through the week.
    private static func weeklyPnL(_ bot: Bot, now: Date) -> Double {
        let hoursIntoWeek = now.timeIntervalSince(startOfWeek(now)) / 3_600
        let dayInWeek     = Int(hoursIntoWeek / 24)
        let hourInWeek    = Int(hoursIntoWeek)
        let dailyNoise    = noise(seed: bot.seed,        day: dayInWeek, hour: 0)          * bot.vol
        let hourlyNoise   = noise(seed: bot.seed &+ 999, day: dayInWeek, hour: hourInWeek) * bot.vol * 0.2
        return bot.drift * hoursIntoWeek + dailyNoise + hourlyNoise
    }

    /// Deterministic value in [-0.5, 0.5] from seed + day + hour (splitmix64-style hash).
    private static func noise(seed: UInt64, day: Int, hour: Int) -> Double {
        var v = seed
            &+ UInt64(bitPattern: Int64(day)  &* Int64(2_654_435_761))
            &+ UInt64(bitPattern: Int64(hour) &* Int64(1_013_904_223))
        v = (v ^ (v >> 30)) &* 0xBF58_476D_1CE4_E5B9
        v = (v ^ (v >> 27)) &* 0x94D0_49BB_1331_11EB
        v =  v ^ (v >> 31)
        return Double(v >> 11) / Double(1 << 53) - 0.5
    }

    /// Extra trades that vary day-to-day per bot (0–3).
    private static func tradeOffset(_ seed: UInt64, now: Date) -> Int {
        let day = Int(now.timeIntervalSince1970 / 86_400)
        var v = seed &+ UInt64(bitPattern: Int64(day) &* Int64(1_000_003))
        v = (v ^ (v >> 30)) &* 0xBF58_476D_1CE4_E5B9
        v =  v ^ (v >> 31)
        return Int(v >> 62)
    }
}
