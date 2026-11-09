//
//  AppModel.swift
//  Fortune
//
//  App-wide observable state. A thin coordinator: it owns the user's profile and
//  settings, and delegates to focused types:
//
//    PortfolioEngine   ledger: orders, positions, P&L          (PortfolioEngine.swift)
//    Gamification      XP, levels, challenges, achievements     (Gamification.swift)
//    MarketDataStore   quotes, charts, news, live feed          (MarketDataStore.swift)
//    PracticeLeague    leaderboard vs. simulated traders        (PracticeLeague.swift)
//    PersistenceStore  saving/loading, iCloud watchlist         (Persistence.swift)
//
//  AppModel's job is the glue: reacting to price changes (stop loss / take profit,
//  alerts), sending notifications, driving toasts, and saving after changes.
//

import SwiftUI
import Observation

@Observable
final class AppModel {

    // MARK: Collaborators

    let market = MarketDataStore()
    private(set) var portfolio  = PortfolioEngine(startingCapital: 10_000)
    private var gamification    = Gamification()
    @ObservationIgnored private let store: PersistenceStore

    // MARK: Profile & preferences

    var onboarded  = false
    var userName   = "Trader"
    var joinDate   = Date()
    var activeTab: AppTab = .trade

    var experience: ExperienceLevel  = .beginner
    var goal:       TradingGoal      = .learn
    var frequency:  TradingFrequency = .active
    var risk:       RiskLevel        = .balanced
    var customStopLossPct: Double?   = nil
    var preferredSectors: [String]   = []
    var weeklyDigestEnabled = true
    var lastNewsRefresh: Date? = nil

    // Notifications: master switch + per-category toggles
    var notificationsEnabled = false
    var stockAlertsEnabled   = true
    var xpMilestonesEnabled  = true

    // Starred stocks, optionally synced across devices via iCloud
    var starredSymbols: [String] = []
    var watchlistSyncEnabled = true

    // User-created price alerts; each fires once when its target is crossed, then is removed
    var priceAlerts: [PriceAlert] = []

    // MARK: Transient UI state

    var tradeConfirmation: String? = nil        // toast after every buy/sell
    var lastAlert: String? = nil                // toast for SL/TP and price alerts
    var showTutorial = false
    var showFirstBloodCelebration = false
    var tradeSector:    String?    = nil        // Trade filters survive tab switches (nil = onboarding defaults)
    var tradeTimeframe: Timeframe? = nil
    var leaderboardRefreshTick = 0              // bumped by LeaderboardView so bot P&L re-evaluates

    @ObservationIgnored private var lastBigMoveAlert: [String: Date] = [:]
    private static let bigMoveThresholdPct = 5.0

    // MARK: Init

    init(store: PersistenceStore = UserDefaultsStore()) {
        self.store = store
        load()
        market.onPricesChanged = { [weak self] fromLiveFeed in
            self?.pricesDidChange(fromLiveFeed: fromLiveFeed)
        }
        #if DEBUG
        // Debug-only: launch straight to a tab, e.g. `-initialTab account` (used for screenshots)
        if let raw = UserDefaults.standard.string(forKey: "initialTab"), let tab = AppTab(rawValue: raw) {
            activeTab = tab
        }
        #endif
    }

    convenience init(defaults: UserDefaults) {
        self.init(store: UserDefaultsStore(defaults: defaults))
    }

    // MARK: Portfolio (display values)

    var balance:         Double { portfolio.cash.doubleValue }
    var startingCapital: Double { portfolio.startingCapital.doubleValue }
    var realizedPnL:     Double { portfolio.realizedPnL.doubleValue }
    var orders:          [TradeOrder]  { portfolio.orders }
    var closedTrades:    [ClosedTrade] { portfolio.closedTrades }
    var winCount:        Int    { portfolio.winCount }
    var closedTradeCount: Int   { portfolio.closedTradeCount }
    var winRate:         Double { portfolio.winRate }
    var currentWinStreak: Int   { portfolio.currentWinStreak }
    var bestWinStreak:   Int    { portfolio.bestWinStreak }

    var holdings:      [Holding] { portfolio.holdings(priceOf: market.price(of:)) }
    var unrealizedPnL: Double    { holdings.reduce(0) { $0 + $1.pnl } }
    var totalPnL:      Double    { unrealizedPnL + realizedPnL }
    var totalPortfolioValue: Double { balance + holdings.reduce(0) { $0 + $1.marketValue } }
    var pnlCandles:    [Candle]  { portfolio.equityCurve(priceOf: market.price(of:)) }

    func hasTradeToday() -> Bool { portfolio.hasTrade(on: Date()) }

    // MARK: Market data (forwarded)

    var stocks: [Stock] {
        get { market.stocks }
        set { market.setStocks(newValue) }
    }
    var news:               [NewsItem]          { market.news }
    var chartData:          [String: [Candle]]  { market.chartData }
    var isLoading:          Bool                { market.isLoading }
    var isRefreshingPrices: Bool                { market.isRefreshingPrices }

    func stock(for symbol: String) -> Stock? { market.stock(for: symbol) }
    func priceDirection(for symbol: String, current: Double) -> Int {
        market.priceDirection(for: symbol, current: current)
    }
    static func chartKey(_ symbol: String, _ timeframe: Timeframe) -> String {
        MarketDataStore.chartKey(symbol, timeframe)
    }

    func loadMarketData() async { await market.loadMarketData() }
    func refreshPrices() async  { await market.refreshPrices() }
    func startLivePriceStream() async { await market.startLivePriceStream() }
    func loadChartData(symbol: String, timeframe: Timeframe) async {
        await market.loadChartData(symbol: symbol, timeframe: timeframe)
    }
    func refreshChart(symbol: String, timeframe: Timeframe) async {
        await market.refreshChart(symbol: symbol, timeframe: timeframe)
    }

    // MARK: Derived preferences

    var archetype: Archetype { Archetype(experience: experience, risk: risk, frequency: frequency) }
    var defaultStopLossPct:   Double    { customStopLossPct ?? risk.defaultStopLossPct }
    var defaultTakeProfitPct: Double    { risk.defaultTakeProfitPct }
    var defaultTimeframe:     Timeframe { frequency.defaultTimeframe }
    /// Users who want to beat the market see top gainers first.
    var prefersGainersSort: Bool { goal == .beat }

    // MARK: Gamification

    var bonusXP:          Int    { gamification.bonusXP }
    var totalXP:          Int    { gamification.totalXP(for: portfolio) }
    var level:            Int    { Gamification.level(forXP: totalXP) }
    var xpInCurrentLevel: Int    { totalXP % Gamification.xpPerLevel }
    var xpProgress:       Double { Double(xpInCurrentLevel) / Double(Gamification.xpPerLevel) }

    var dailyChallenges: [DailyChallenge] { Gamification.dailyChallenges(for: portfolio) }

    var achievements: [Achievement] {
        Gamification.achievements(for: portfolio, totalPnL: totalPnL,
                                  isLeagueLeader: leaderboard.first?.isMe == true)
    }

    // MARK: Practice League

    var leaderboard: [LeaderboardEntry] {
        _ = leaderboardRefreshTick  // register @Observable dependency for live updates
        return PracticeLeague.allTime(me: LeagueStanding(
            name: userName, pnl: totalPnL, startingCapital: startingCapital,
            winRate: winRate * 100, trades: orders.count))
    }

    /// This week only: P&L from trades closed since Monday plus current unrealized P&L.
    var weeklyLeaderboard: [LeaderboardEntry] {
        _ = leaderboardRefreshTick
        let weekStart  = PracticeLeague.startOfWeek()
        let weekCloses = closedTrades.filter { $0.closedAt >= weekStart }
        let weekWins   = weekCloses.filter(\.isWin).count
        return PracticeLeague.weekly(me: LeagueStanding(
            name: userName,
            pnl: weekCloses.reduce(0) { $0 + $1.pnl.doubleValue } + unrealizedPnL,
            startingCapital: startingCapital,
            winRate: weekCloses.isEmpty ? 0 : Double(weekWins) / Double(weekCloses.count) * 100,
            trades: orders.filter { $0.date >= weekStart }.count))
    }

    // MARK: Trading

    func placeOrder(_ order: TradeOrder) {
        let levelBefore = level
        let isFirstTradeToday = !hasTradeToday()
        guard let fill = try? portfolio.execute(order) else { return }

        if let trade = fill.closedTrade {
            tradeConfirmation = "Sold \(order.symbol) · \(trade.pnl.doubleValue.signedMoney())"
        } else {
            tradeConfirmation = "Bought \(order.qty) × \(order.symbol) @ $\(order.entryPrice.doubleValue.money())"
        }
        if isFirstTradeToday { showFirstBloodCelebration = true }
        afterTrade(levelBefore: levelBefore)
    }

    /// Sell an entire open holding at the current live price.
    func closePosition(_ holding: Holding) {
        partialSell(holding: holding, shares: holding.shares)
    }

    /// Sell a specific number of shares from a holding.
    func partialSell(holding: Holding, shares: Int) {
        guard shares > 0, shares <= holding.shares else { return }
        let price = market.price(of: holding.symbol) ?? holding.current
        placeOrder(TradeOrder(symbol: holding.symbol, name: holding.symbol, side: .sell,
                              qty: shares, entryPrice: price, stopLoss: nil, takeProfit: nil))
    }

    /// Closes positions whose stop loss or take profit has been crossed. Runs after every price update.
    func checkAndTriggerSLTP() {
        for exit in portfolio.triggeredExits(priceOf: market.price(of:)) {
            guard let shares = portfolio.positions[exit.symbol]?.shares else { continue }
            let levelBefore = level
            let order = TradeOrder(symbol: exit.symbol, name: exit.symbol, side: .sell,
                                   qty: shares, entryPrice: exit.price, stopLoss: nil, takeProfit: nil)
            guard let trade = (try? portfolio.execute(order, exitReason: exit.reason))?.closedTrade else { continue }

            let isStop = exit.reason == .stopLoss
            lastAlert = isStop
                ? "🛑 Stop Loss hit — \(exit.symbol) sold @ $\(exit.price.money())"
                : "🎯 Take Profit hit — \(exit.symbol) sold @ $\(exit.price.money())"
            if notificationsEnabled && stockAlertsEnabled {
                NotificationManager.shared.send(
                    title: isStop ? "🛑 Stop Loss triggered on \(exit.symbol)" : "🎯 Take Profit hit on \(exit.symbol)",
                    body: "Sold \(shares) share\(shares == 1 ? "" : "s") @ $\(exit.price.money()) · \(trade.pnl.doubleValue.signedMoney())"
                )
            }
            afterTrade(levelBefore: levelBefore)
        }
    }

    /// Fires and removes any price alerts whose target has been crossed.
    func checkPriceAlerts() {
        guard !priceAlerts.isEmpty else { return }
        let fired = priceAlerts.filter { alert in
            guard let price = market.price(of: alert.symbol) else { return false }
            return alert.above ? price >= alert.target : price <= alert.target
        }
        guard !fired.isEmpty else { return }
        let firedIDs = Set(fired.map(\.id))
        priceAlerts.removeAll { firedIDs.contains($0.id) }
        save()
        for alert in fired {
            let dir = alert.above ? "above" : "below"
            lastAlert = "🔔 \(alert.symbol) is \(dir) $\(alert.target.money())"
            if notificationsEnabled && stockAlertsEnabled {
                NotificationManager.shared.send(
                    title: "🔔 Price alert: \(alert.symbol)",
                    body: "\(alert.symbol) moved \(dir) your $\(alert.target.money()) target."
                )
            }
        }
    }

    func resetPortfolio() {
        portfolio.reset()
        gamification.bonusXP = 0   // today's awarded set is kept so challenges can't be re-farmed
        tradeConfirmation = nil
        lastAlert         = nil
        save()
    }

    private func afterTrade(levelBefore: Int) {
        gamification.awardCompletedChallenges(for: portfolio)
        notifyIfLeveledUp(from: levelBefore)
        save()
    }

    private func pricesDidChange(fromLiveFeed: Bool) {
        checkAndTriggerSLTP()
        checkPriceAlerts()
        if !fromLiveFeed { maybeSendBigMoveAlerts() }
    }

    // MARK: Onboarding & account

    func completeOnboarding(_ data: OnboardingData) {
        let trimmed = data.name.trimmingCharacters(in: .whitespaces)
        userName          = trimmed.isEmpty ? "Trader" : trimmed
        experience        = data.experience ?? .beginner
        goal              = data.goal ?? .learn
        frequency         = data.frequency ?? .active
        risk              = data.risk ?? .balanced
        customStopLossPct = nil
        weeklyDigestEnabled = true
        lastNewsRefresh   = nil
        preferredSectors  = data.sectors
        joinDate          = Date()

        let capital = data.capital.map { Decimal($0.amount) } ?? portfolio.startingCapital
        portfolio.reset(startingCapital: capital)
        gamification = Gamification()
        priceAlerts.removeAll()

        onboarded = true
        if experience != .pro { showTutorial = true }
        save()
    }

    func signOut() {
        onboarded = false
        activeTab = .trade
        save()
    }

    func updateRisk(_ newRisk: RiskLevel) {
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

    func updateStockAlertsEnabled(_ isEnabled: Bool) {
        stockAlertsEnabled = isEnabled
        save()
    }

    func updateXPMilestonesEnabled(_ isEnabled: Bool) {
        xpMilestonesEnabled = isEnabled
        save()
    }

    // MARK: Notifications

    /// Master toggle. Turning on requests OS permission and only stays on if granted.
    func setNotificationsEnabled(_ isEnabled: Bool) async {
        notificationsEnabled = isEnabled ? await NotificationManager.shared.requestAuthorization() : false
        save()
    }

    /// Re-syncs the master toggle with the OS setting (e.g. permission revoked in Settings).
    func syncNotificationAuthorization() async {
        guard notificationsEnabled else { return }
        notificationsEnabled = await NotificationManager.shared.isAuthorized()
        save()
    }

    private func notifyIfLeveledUp(from oldLevel: Int) {
        guard notificationsEnabled, xpMilestonesEnabled, level > oldLevel else { return }
        NotificationManager.shared.send(
            title: "🎉 Level Up! You reached Level \(level)",
            body: "Nice work, \(userName). Keep trading to climb the Practice League."
        )
    }

    /// Notifies about held stocks that moved 5%+ today (at most once per symbol every 30 minutes).
    private func maybeSendBigMoveAlerts() {
        guard notificationsEnabled, stockAlertsEnabled else { return }
        let now = Date()
        for symbol in portfolio.positions.keys {
            guard let stock = market.stock(for: symbol), abs(stock.pct) >= Self.bigMoveThresholdPct else { continue }
            if let last = lastBigMoveAlert[symbol], now.timeIntervalSince(last) < 1_800 { continue }
            lastBigMoveAlert[symbol] = now
            let dir = stock.pct >= 0 ? "up" : "down"
            NotificationManager.shared.send(
                title: "\(symbol) is \(dir) \(abs(stock.pct).money(1))% today",
                body: "\(stock.name) is trading at $\(stock.price.money())."
            )
        }
    }

    // MARK: Watchlist

    func isStarred(_ symbol: String) -> Bool { starredSymbols.contains(symbol) }

    func toggleStar(_ symbol: String) {
        if let i = starredSymbols.firstIndex(of: symbol) {
            starredSymbols.remove(at: i)
        } else {
            starredSymbols.append(symbol)
        }
        save()
        if watchlistSyncEnabled { CloudWatchlist.push(starredSymbols) }
    }

    func setWatchlistSyncEnabled(_ isEnabled: Bool) {
        watchlistSyncEnabled = isEnabled
        save()
        guard isEnabled else { return }
        // Merge rather than overwrite, so stars from either device aren't lost
        mergeCloudWatchlist()
        CloudWatchlist.push(starredSymbols)
    }

    /// Listens for iCloud changes pushed from the user's other devices. Call from a long-lived Task.
    func observeCloudWatchlist() async {
        let changes = CloudWatchlist.externalChanges()
        if watchlistSyncEnabled { mergeCloudWatchlist() }
        for await _ in changes {
            // The cloud is the source of truth for remote changes (including un-starring elsewhere)
            guard watchlistSyncEnabled else { continue }
            let cloud = CloudWatchlist.fetch()
            if cloud != starredSymbols {
                starredSymbols = cloud
                save()
            }
        }
    }

    private func mergeCloudWatchlist() {
        let merged = starredSymbols + CloudWatchlist.fetch().filter { !starredSymbols.contains($0) }
        guard merged != starredSymbols else { return }
        starredSymbols = merged
        save()
    }

    // MARK: Persistence

    func save() {
        store.save(PersistedState(
            onboarded:            onboarded,
            userName:             userName,
            balance:              portfolio.cash,
            startingCapital:      portfolio.startingCapital,
            orders:               portfolio.orders,
            joinDate:             joinDate,
            experience:           experience.rawValue,
            goal:                 goal.rawValue,
            frequency:            frequency.rawValue,
            risk:                 risk.rawValue,
            customStopLossPct:    customStopLossPct,
            weeklyDigestEnabled:  weeklyDigestEnabled,
            notificationsEnabled: notificationsEnabled,
            stockAlertsEnabled:   stockAlertsEnabled,
            xpMilestonesEnabled:  xpMilestonesEnabled,
            lastNewsRefresh:      lastNewsRefresh,
            preferredSectors:     preferredSectors,
            realizedPnL:          portfolio.realizedPnL,
            winCount:             portfolio.winCount,
            closedTradeCount:     portfolio.closedTradeCount,
            closedTrades:         portfolio.closedTrades,
            priceAlerts:          priceAlerts,
            bonusXP:              gamification.bonusXP,
            challengeDay:         gamification.challengeDay,
            awardedChallenges:    Array(gamification.awardedChallenges),
            starredSymbols:       starredSymbols,
            watchlistSyncEnabled: watchlistSyncEnabled
        ))
    }

    private func load() {
        guard let state = store.load() else { return }
        onboarded         = state.onboarded
        userName          = state.userName
        joinDate          = state.joinDate
        // Unknown or empty values (very old saves) fall back to defaults
        experience        = ExperienceLevel(rawValue: state.experience) ?? .beginner
        goal              = TradingGoal(rawValue: state.goal) ?? .learn
        frequency         = TradingFrequency(rawValue: state.frequency) ?? .active
        risk              = RiskLevel(rawValue: state.risk) ?? .balanced
        customStopLossPct = state.customStopLossPct
        preferredSectors  = state.preferredSectors
        weeklyDigestEnabled  = state.weeklyDigestEnabled ?? true
        notificationsEnabled = state.notificationsEnabled ?? false
        stockAlertsEnabled   = state.stockAlertsEnabled ?? true
        xpMilestonesEnabled  = state.xpMilestonesEnabled ?? true
        lastNewsRefresh      = state.lastNewsRefresh
        priceAlerts          = state.priceAlerts ?? []
        starredSymbols       = state.starredSymbols ?? []
        watchlistSyncEnabled = state.watchlistSyncEnabled ?? true

        portfolio = PortfolioEngine(
            startingCapital:  state.startingCapital,
            cash:             state.balance,
            orders:           state.orders,
            closedTrades:     state.closedTrades,
            realizedPnL:      state.realizedPnL,
            winCount:         state.winCount,
            closedTradeCount: state.closedTradeCount
        )
        gamification = Gamification(
            bonusXP:           state.bonusXP ?? 0,
            challengeDay:      state.challengeDay ?? "",
            awardedChallenges: Set(state.awardedChallenges ?? [])
        )
    }
}
