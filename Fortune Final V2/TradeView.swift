//
//  TradeView.swift
//  Fortune
//
//  Trading screen container: owns the screen's state (selected stock, timeframe,
//  filters, which sheet is open) and composes the sections in TradeSections.swift.
//

import SwiftUI

struct TradeView: View {
    @Environment(AppModel.self) private var model

    @State private var selectedSymbol = MarketService.watchlist[0]
    @State private var timeframe:     Timeframe = .day
    @State private var filter         = StockFilter()
    @State private var appliedPrefs   = false

    @State private var showOrderSheet  = false
    @State private var showDetailSheet = false
    @State private var showAlertsSheet = false

    private var selected: Stock {
        model.stock(for: selectedSymbol)
            ?? Stock(symbol: selectedSymbol, name: selectedSymbol, price: 0,
                     change: 0, pct: 0, volume: "—", high52: 1, low52: 0,
                     pe: 0, mktCap: "—", rating: "—", ratingHex: 0x6B7280, sector: "—")
    }

    /// Historical candles with the last bar updated live from the latest price.
    private var liveCandles: [Candle] {
        var candles = model.chartData[AppModel.chartKey(selectedSymbol, timeframe)] ?? []
        guard let last = candles.last, selected.price > 0 else { return candles }
        candles[candles.count - 1] = Candle(
            day:   last.day,
            open:  last.open,
            high:  max(last.high, selected.price),
            low:   min(last.low,  selected.price),
            close: selected.price
        )
        return candles
    }

    var body: some View {
        // Computed once per render and shared by every section below
        let holdings = model.holdings
        let filtered = filter.apply(to: model.stocks, isStarred: model.isStarred)

        VStack(spacing: 0) {
            TradeChartHeader(
                stock: selected,
                candles: liveCandles,
                direction: model.priceDirection(for: selected.symbol, current: selected.price),
                isLoading: model.isLoading,
                isRefreshing: model.isRefreshingPrices,
                hasStocks: !model.stocks.isEmpty,
                alertCount: model.priceAlerts.count,
                timeframe: $timeframe,
                onShowAlerts: { showAlertsSheet = true }
            )
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if !holdings.isEmpty {
                        OpenPositionsSection(holdings: holdings, unrealizedPnL: model.unrealizedPnL) { h in
                            model.closePosition(h)
                        }
                    }
                    MarketMoversStrip(stocks: model.stocks, onSelect: openOrder)
                    StockFilterBar(filter: $filter, resultCount: filtered.count)
                    stockList(filtered: filtered, ownedSymbols: Set(holdings.map(\.symbol)))
                    Color.clear.frame(height: 16)
                }
            }
        }
        .background(Theme.background)
        .task { await setUp() }
        // Refresh chart bars every 60 s — restarts automatically on symbol/timeframe change
        .task(id: AppModel.chartKey(selectedSymbol, timeframe)) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await model.refreshChart(symbol: selectedSymbol, timeframe: timeframe)
            }
        }
        .onChange(of: timeframe) { _, new in
            if appliedPrefs { model.tradeTimeframe = new }
            Task { await model.loadChartData(symbol: selectedSymbol, timeframe: new) }
        }
        .onChange(of: filter.sector) { _, new in
            if appliedPrefs { model.tradeSector = new }
        }
        .onChange(of: selectedSymbol) { _, new in
            Task { await model.loadChartData(symbol: new, timeframe: timeframe) }
        }
        .sheet(isPresented: $showOrderSheet) { orderSheet }
        .sheet(isPresented: $showDetailSheet) { detailSheet }
        .sheet(isPresented: $showAlertsSheet) { alertsSheet }
    }

    // MARK: Stock list

    @ViewBuilder
    private func stockList(filtered: [Stock], ownedSymbols: Set<String>) -> some View {
        let focusStocks = model.stocks.filter { model.preferredSectors.contains($0.sector) }
        if !focusStocks.isEmpty && filter.search.isEmpty && filter.sector == StockFilter.allChip {
            ForYouStrip(stocks: focusStocks, onSelect: openOrder)
        }

        if model.isLoading && model.stocks.isEmpty {
            emptyState(icon: nil, message: "Loading live data…")
        } else if model.stocks.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 20)).foregroundStyle(.white.opacity(0.25))
                Text("Couldn't load market data").font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
                Button("Retry") { Task { await model.loadMarketData() } }
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.primary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 40)
        } else if filtered.isEmpty {
            emptyState(icon: "magnifyingglass",
                       message: filter.isShowingStarred && filter.search.isEmpty
                           ? "No starred stocks yet — tap ☆ on any stock"
                           : "No results for \"\(filter.search)\"")
        } else {
            ForEach(filtered) { stock in
                StockRow(
                    stock: stock,
                    isOwned: ownedSymbols.contains(stock.symbol),
                    isStarred: model.isStarred(stock.symbol),
                    direction: model.priceDirection(for: stock.symbol, current: stock.price),
                    onTrade: { openOrder(stock) },
                    onToggleStar: { model.toggleStar(stock.symbol) },
                    onInfo: {
                        selectedSymbol  = stock.symbol
                        showDetailSheet = true
                    }
                )
            }
        }
    }

    private func emptyState(icon: String?, message: String) -> some View {
        VStack(spacing: 8) {
            if let icon {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(.white.opacity(0.25))
            } else {
                ProgressView().tint(Theme.primary)
            }
            Text(message).font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    // MARK: Sheets

    private var orderSheet: some View {
        OrderSheet(stock: selected,
                   balance: model.balance,
                   currentShares: model.holdings.first(where: { $0.symbol == selected.symbol })?.shares ?? 0,
                   stopLossPct: model.defaultStopLossPct,
                   takeProfitPct: model.defaultTakeProfitPct) { order in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                model.placeOrder(order)
            }
        }
        .presentationDetents([.height(540)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .presentationCornerRadius(24)
    }

    private var detailSheet: some View {
        StockDetailSheet(stock: selected) {
            showDetailSheet = false
            showOrderSheet  = true
        }
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .presentationCornerRadius(24)
    }

    private var alertsSheet: some View {
        PriceAlertsSheet(alerts: Binding(get: { model.priceAlerts },
                                         set: { model.priceAlerts = $0; model.save() }),
                         stocks: model.stocks)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.background)
            .presentationCornerRadius(24)
    }

    // MARK: Actions

    private func openOrder(_ stock: Stock) {
        selectedSymbol = stock.symbol
        showOrderSheet = true
    }

    /// Restores filters from earlier in this session, or applies onboarding preferences the first time.
    private func setUp() async {
        if model.stocks.isEmpty { await model.loadMarketData() }
        if !appliedPrefs {
            if let savedSector = model.tradeSector, let savedTimeframe = model.tradeTimeframe {
                filter.sector = savedSector
                timeframe     = savedTimeframe
            } else {
                timeframe = model.defaultTimeframe
                if let match = MarketService.sectors.first(where: { model.preferredSectors.contains($0) }) {
                    filter.sector = match
                }
                model.tradeSector    = filter.sector
                model.tradeTimeframe = timeframe
            }
            if model.prefersGainersSort { filter.sort = .gainers }
            appliedPrefs = true
        }
        await model.loadChartData(symbol: selectedSymbol, timeframe: timeframe)
    }
}

#Preview {
    TradeView().environment(AppModel())
}
