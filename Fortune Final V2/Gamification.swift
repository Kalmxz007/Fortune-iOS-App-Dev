//
//  Gamification.swift
//  Fortune
//
//  XP, levels, daily challenges, and achievements — all derived from real
//  trading activity in the PortfolioEngine. The only stored state is the
//  bonus XP earned from challenges and which challenges were awarded today.
//

import Foundation

struct DailyChallenge: Identifiable {
    let id: String
    let icon: String, title: String, detail: String
    let xp: Int, progress: Int, total: Int
    var done: Bool { progress >= total }
}

struct Gamification {
    static let xpPerLevel = 1_000

    var bonusXP = 0
    var challengeDay = ""                      // "yyyy-MM-dd" of the day `awardedChallenges` refers to
    var awardedChallenges: Set<String> = []

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    // MARK: XP & levels

    func totalXP(for portfolio: PortfolioEngine) -> Int {
        portfolio.closedTradeCount * 200
            + portfolio.winCount * 100
            + max(0, Int(portfolio.realizedPnL.doubleValue / 100))
            + bonusXP
    }

    static func level(forXP xp: Int) -> Int { max(1, 1 + xp / xpPerLevel) }

    // MARK: Daily challenges

    static func dailyChallenges(for portfolio: PortfolioEngine, now: Date = Date()) -> [DailyChallenge] {
        [
            .init(id: "firstBlood", icon: "⚡", title: "First Blood", detail: "Place your first trade today",
                  xp: 50, progress: portfolio.hasTrade(on: now) ? 1 : 0, total: 1),
            .init(id: "diversify", icon: "📊", title: "Diversify", detail: "Hold 3 different stocks at once",
                  xp: 100, progress: min(portfolio.positions.count, 3), total: 3),
            .init(id: "profitStreak", icon: "🔥", title: "Profit Streak", detail: "Close 3 trades in the green",
                  xp: 200, progress: min(portfolio.winningCloses(on: now), 3), total: 3),
        ]
    }

    /// Grants XP once per day for each newly completed challenge.
    mutating func awardCompletedChallenges(for portfolio: PortfolioEngine, now: Date = Date()) {
        let today = Self.dayKeyFormatter.string(from: now)
        if challengeDay != today {
            challengeDay = today
            awardedChallenges.removeAll()
        }
        for challenge in Self.dailyChallenges(for: portfolio, now: now)
        where challenge.done && !awardedChallenges.contains(challenge.id) {
            awardedChallenges.insert(challenge.id)
            bonusXP += challenge.xp
        }
    }

    // MARK: Achievements

    static func achievements(for portfolio: PortfolioEngine, totalPnL: Double,
                             isLeagueLeader: Bool, now: Date = Date()) -> [Achievement] {
        let hasLongHold = portfolio.positions.values.contains { now.timeIntervalSince($0.openedAt) > 30 * 86_400 }
        let tradesPerDay = Dictionary(grouping: portfolio.orders) { Calendar.current.startOfDay(for: $0.date) }
        let maxTradesInOneDay = tradesPerDay.values.map(\.count).max() ?? 0
        let afterHoursTrades = portfolio.orders.filter { MarketHours.isOutsideRegularSession($0.date) }.count

        return [
            Achievement(id: 1, icon: "🔥", name: "Hot Streak",    detail: "Win 5 trades in a row",
                        earned: portfolio.bestWinStreak >= 5),
            Achievement(id: 2, icon: "💎", name: "Diamond Hands", detail: "Hold a position for 30+ days",
                        earned: hasLongHold),
            Achievement(id: 3, icon: "🧀", name: "Big Baller",    detail: "Make 10K+ in Mock Capital",
                        earned: totalPnL >= 10_000),
            Achievement(id: 4, icon: "⚡", name: "Speed Trader",  detail: "Execute 50 trades in one day",
                        earned: maxTradesInOneDay >= 50),
            Achievement(id: 5, icon: "🏆", name: "Top Gainer",    detail: "Reach #1 in the Practice League",
                        earned: isLeagueLeader),
            Achievement(id: 6, icon: "🌙", name: "Night Owl",     detail: "Trade after-hours 20 times",
                        earned: afterHoursTrades >= 20),
        ]
    }
}

enum MarketHours {
    /// True outside regular NYSE hours: Mon–Fri 9:30–16:00 New York time.
    static func isOutsideRegularSession(_ date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = c.weekday, let hour = c.hour, let minute = c.minute else { return false }
        if weekday == 1 || weekday == 7 { return true }   // Sunday / Saturday
        let minutes = hour * 60 + minute
        return minutes < 9 * 60 + 30 || minutes >= 16 * 60
    }
}
