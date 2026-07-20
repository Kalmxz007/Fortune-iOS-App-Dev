//
//  TradeView.swift
//  Fortune
//
//  Trading screen: live chart with timeframe selector, market movers,
//  search + sector filters + sort, stock list, and three bottom sheets
//  (order, stock detail, price alerts).
//

import SwiftUI
import Charts

struct TradeView: View {
    @Environment(AppModel.self) private var model

    @State private var selectedSymbol    = MarketService.watchlist[0]
    @State private var timeframe         = "1D"
    @State private var search            = ""
    @State private var sector            = "All"
    @State private var sortBy:           SortOption = .default_
    @State private var moversTab:        MoversTab  = .gainers
    @State private var alerts:           [PriceAlert] = []
    @State private var appliedPrefs      = false

    @State private var showOrderSheet  = false
    @State private var showDetailSheet = false
    @State private var showAlertsSheet = false

    enum SortOption: String, CaseIterable {
        case default_, gainers, losers, price
        var label: String {
            switch self {
            case .default_: "Default"
            case .gainers:  "↑ Top Gainers"
            case .losers:   "↓ Top Losers"
            case .price:    "Price"
            }
        }
    }
    enum MoversTab { case gainers, losers }

    private var selected: Stock {
        model.stocks.first { $0.symbol == selectedSymbol }
            ?? Stock(symbol: selectedSymbol, name: selectedSymbol, price: 0,
                     change: 0, pct: 0, volume: "—", high52: 1, low52: 0,
                     pe: 0, mktCap: "—", rating: "—", ratingHex: 0x6B7280, sector: "—")
    }

    private var chartPoints: [PricePoint] {
        model.chartData["\(selectedSymbol)_\(timeframe)"] ?? []
    }

    private var filtered: [Stock] {
        model.stocks
            .filter { sector == "All" || $0.sector == sector }
            .filter {
                search.isEmpty
                    || $0.symbol.localizedCaseInsensitiveContains(search)
                    || $0.name.localizedCaseInsensitiveContains(search)
            }
            .sorted { a, b in
                switch sortBy {
                case .gainers:  a.pct > b.pct
                case .losers:   a.pct < b.pct
                case .price:    a.price > b.price
                case .default_: false
                }
            }
    }

    private var movers: [Stock] {
        let sorted = model.stocks.sorted {
            moversTab == .gainers ? $0.pct > $1.pct : $0.pct < $1.pct
        }
        return Array(sorted.prefix(4))
    }

    var body: some View {
        VStack(spacing: 0) {
            chartHeader
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if !model.holdings.isEmpty { openPositions }
                    marketMovers
                    searchBar
                    sectorFilters
                    sortControls
                    stockList
                    Color.clear.frame(height: 16)
                }
            }
        }
        .background(Theme.background)
        .task {
            if model.stocks.isEmpty { await model.loadMarketData() }
            // Apply onboarding preferences once on first load
            if !appliedPrefs {
                timeframe = model.defaultTimeframe
                if let match = MarketService.sectors.first(where: { model.preferredSectors.contains($0) }) {
                    sector = match
                }
                if model.defaultSortLabel == "gainers" { sortBy = .gainers }
                appliedPrefs = true
            }
            await model.loadChartData(symbol: selectedSymbol, timeframe: timeframe)
        }
        // WebSocket: real-time prices pushed by Finnhub (no rate-limit cost)
        .task { await model.startLivePriceStream() }
        // REST fallback every 60 s — keeps change/pct accurate if WS is quiet
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await model.refreshPrices()
            }
        }
        // Refresh chart every 2 minutes (Finnhub 1D uses 5-min bars)
        .task(id: "\(selectedSymbol)_\(timeframe)") {
            try? await Task.sleep(for: .seconds(120))
            await model.refreshChart(symbol: selectedSymbol, timeframe: timeframe)
        }
        .onChange(of: timeframe) { _, new in
            Task { await model.loadChartData(symbol: selectedSymbol, timeframe: new) }
        }
        .onChange(of: selectedSymbol) { _, new in
            Task { await model.loadChartData(symbol: new, timeframe: timeframe) }
        }
        .sheet(isPresented: $showOrderSheet) {
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
        .sheet(isPresented: $showDetailSheet) {
            StockDetailSheet(stock: selected) {
                showDetailSheet = false
                showOrderSheet  = true
            }
            .presentationDetents([.height(440)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.background)
            .presentationCornerRadius(24)
        }
        .sheet(isPresented: $showAlertsSheet) {
            PriceAlertsSheet(alerts: $alerts, stocks: model.stocks)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
                .presentationCornerRadius(24)
        }
    }

    // MARK: Chart header

    private var chartHeader: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(selected.symbol).font(.mono(11)).tracking(2).foregroundStyle(Theme.mutedForeground)
                        PulsingDot()
                        Text("LIVE").font(.system(size: 11)).foregroundStyle(Theme.emerald)
                        if model.isRefreshingPrices {
                            ProgressView().scaleEffect(0.5).tint(Theme.emerald)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: model.isRefreshingPrices)
                    if model.isLoading && model.stocks.isEmpty {
                        ProgressView().tint(Theme.primary).scaleEffect(0.7)
                    } else {
                        let dir = model.priceDirection(for: selected.symbol, current: selected.price)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("$\(selected.price.money())")
                                .font(.mono(24, weight: .semibold))
                                .foregroundStyle(dir > 0 ? Theme.emerald : dir < 0 ? Theme.red : Theme.foreground)
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected.price)
                            if dir != 0 {
                                Image(systemName: dir > 0 ? "arrow.up" : "arrow.down")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(dir > 0 ? Theme.emerald : Theme.red)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .animation(.spring(response: 0.3), value: dir)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if !model.stocks.isEmpty {
                        PnlBadge(change: selected.change, pct: selected.pct)
                        HStack(spacing: 8) {
                            Text("\(selected.change.signPrefix)\(selected.change.money())")
                                .font(.mono(11)).foregroundStyle(Theme.mutedForeground)
                            Button { showAlertsSheet = true } label: {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "bell")
                                        .font(.system(size: 14))
                                        .foregroundStyle(alerts.isEmpty ? Color.white.opacity(0.3) : Theme.primary)
                                        .padding(2)
                                    if !alerts.isEmpty {
                                        Text("\(alerts.count)")
                                            .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                                            .frame(width: 14, height: 14)
                                            .background(Theme.primary).clipShape(Circle())
                                            .offset(x: 4, y: -4)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Timeframe selector
            HStack(spacing: 4) {
                ForEach(MarketService.timeframes, id: \.self) { tf in
                    let on = timeframe == tf
                    Button { timeframe = tf } label: {
                        Text(tf)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(on ? .white : .white.opacity(0.35))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background {
                                if on {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [Theme.primary, Theme.indigo],
                                                             startPoint: .leading, endPoint: .trailing))
                                } else {
                                    RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05))
                                }
                            }
                    }
                }
                Spacer()
            }

            if chartPoints.isEmpty {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.05))
                    .frame(height: 80)
                    .overlay {
                        if model.isLoading {
                            ProgressView().tint(Theme.primary)
                        }
                    }
            } else {
                Chart(chartPoints) { point in
                    AreaMark(x: .value("t", point.time), y: .value("price", point.price))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(
                            colors: [Theme.primary.opacity(0.22), Theme.primary.opacity(0)],
                            startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("t", point.time), y: .value("price", point.price))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.primary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: chartDomain)
                .frame(height: 80)
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
        .background(Theme.card)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private var chartDomain: ClosedRange<Double> {
        let prices = chartPoints.map(\.price)
        let lo = prices.min() ?? 0, hi = prices.max() ?? 1
        let pad = (hi - lo) * 0.15
        return (lo - pad)...(hi + pad)
    }

    // MARK: Open positions (live P&L, reactive to WebSocket prices)

    private var openPositions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "My Positions")
                Spacer()
                let totalUnrealized = model.unrealizedPnL
                Text("\(totalUnrealized >= 0 ? "+" : "")$\(abs(totalUnrealized).money(0))")
                    .font(.mono(11, weight: .semibold))
                    .foregroundStyle(totalUnrealized >= 0 ? Theme.emerald : Theme.red)
                    .contentTransition(.numericText(countsDown: totalUnrealized < 0))
                    .animation(.spring(response: 0.4), value: totalUnrealized)
            }
            ForEach(model.holdings) { h in
                HStack(spacing: 12) {
                    // Symbol
                    Text(String(h.symbol.prefix(4)))
                        .font(.mono(9, weight: .bold)).foregroundStyle(Theme.primary)
                        .frame(width: 36, height: 36)
                        .background(Theme.primary.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.primary.opacity(0.2)))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Details
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(h.symbol).font(.mono(12, weight: .semibold)).foregroundStyle(Theme.foreground)
                            Text("×\(h.shares)").font(.system(size: 10)).foregroundStyle(Theme.mutedForeground)
                        }
                        HStack(spacing: 8) {
                            Label("$\(h.avgCost.money())", systemImage: "arrow.right.circle")
                                .font(.mono(10)).foregroundStyle(Theme.mutedForeground)
                            // Live current price
                            Text("$\(h.current.money())")
                                .font(.mono(10, weight: .semibold))
                                .foregroundStyle(h.pnl >= 0 ? Theme.emerald : Theme.red)
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.3), value: h.current)
                        }
                    }

                    Spacer()

                    // Live P&L
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(h.pnl >= 0 ? "+" : "-")$\(abs(h.pnl).money(0))")
                            .font(.mono(12, weight: .bold))
                            .foregroundStyle(h.pnl >= 0 ? Theme.emerald : Theme.red)
                            .contentTransition(.numericText(countsDown: h.pnl < 0))
                            .animation(.spring(response: 0.4), value: h.pnl)
                        Text("\(h.pct >= 0 ? "+" : "")\(String(format: "%.2f", h.pct))%")
                            .font(.system(size: 10))
                            .foregroundStyle(h.pnl >= 0 ? Theme.emerald.opacity(0.7) : Theme.red.opacity(0.7))
                    }

                    // Sell button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            model.closePosition(h)
                        }
                    } label: {
                        Text("SELL")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.red)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Theme.red.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.red.opacity(0.3)))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                    h.pnl >= 0 ? Theme.emerald.opacity(0.25) : Theme.red.opacity(0.25)
                ))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.holdings.map(\.symbol))
    }

    // MARK: Market movers

    private var marketMovers: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                moverTabButton(.gainers, "↑ Gainers", Theme.green)
                moverTabButton(.losers,  "↓ Losers",  Theme.red)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(movers) { stock in
                        Button {
                            selectedSymbol = stock.symbol
                            showOrderSheet = true
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stock.symbol).font(.mono(12, weight: .bold)).foregroundStyle(Theme.foreground)
                                Text("\(stock.pct.signPrefix)\(stock.pct.money())%")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(stock.pct >= 0 ? Theme.emerald : Theme.red)
                                    .contentTransition(.numericText())
                                    .animation(.spring(response: 0.35), value: stock.pct)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Theme.card)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
    }

    private func moverTabButton(_ tab: MoversTab, _ label: String, _ tint: Color) -> some View {
        let on = moversTab == tab
        return Button { moversTab = tab } label: {
            Text(label)
                .font(.system(size: 10, weight: .bold)).tracking(0.5)
                .foregroundStyle(on ? tint : .white.opacity(0.3))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(on ? tint.opacity(0.15) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Theme.mutedForeground)
            TextField("", text: $search, prompt: Text("Search stocks…").foregroundColor(Theme.mutedForeground))
                .font(.system(size: 13)).foregroundStyle(Theme.foreground)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(Theme.mutedForeground)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
    }

    // MARK: Sector filters

    private var sectorFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MarketService.sectors, id: \.self) { s in
                    let on = sector == s
                    Button { sector = s } label: {
                        Text(s)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(on ? Theme.primary : .white.opacity(0.4))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(on ? Theme.primary.opacity(0.15) : .white.opacity(0.04))
                            .overlay(Capsule().stroke(on ? Theme.primary.opacity(0.5) : .white.opacity(0.08)))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    // MARK: Sort controls

    private var sortControls: some View {
        HStack(spacing: 6) {
            Text("Sort:").font(.system(size: 10)).foregroundStyle(Theme.mutedForeground)
            ForEach(SortOption.allCases, id: \.self) { opt in
                let on = sortBy == opt
                Button { sortBy = opt } label: {
                    Text(opt.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(on ? Color(hex: 0xA5B4FC) : .white.opacity(0.3))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(on ? Theme.indigo.opacity(0.2) : .clear)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Theme.indigo.opacity(0.35) : .clear))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            Spacer()
            Text("\(filtered.count) stocks").font(.system(size: 10)).foregroundStyle(Theme.mutedForeground)
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    // MARK: For You strip

    @ViewBuilder
    private var forYouStrip: some View {
        let focusStocks = model.stocks.filter { model.preferredSectors.contains($0.sector) }
        if !focusStocks.isEmpty && search.isEmpty && sector == "All" {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Theme.accent)
                    Text("FOR YOU").font(.mono(10)).tracking(1.5).foregroundStyle(Theme.mutedForeground)
                }
                .padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(focusStocks) { stock in
                            Button {
                                selectedSymbol = stock.symbol
                                showOrderSheet = true
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(stock.symbol).font(.mono(12, weight: .bold)).foregroundStyle(Theme.primary)
                                        Spacer()
                                        PnlBadge(change: stock.change, pct: stock.pct)
                                    }
                                    Text("$\(stock.price.money())").font(.mono(13, weight: .semibold)).foregroundStyle(Theme.foreground)
                                    Text(stock.name).font(.system(size: 10)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .frame(width: 140)
                                .background(Theme.card)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.primary.opacity(0.25)))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 12).padding(.bottom, 4)
        }
    }

    // MARK: Stock list

    @ViewBuilder
    private var stockList: some View {
        forYouStrip
        if model.isLoading && model.stocks.isEmpty {
            VStack(spacing: 8) {
                ProgressView().tint(Theme.primary)
                Text("Loading live data…").font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 40)
        } else if filtered.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(.white.opacity(0.25))
                Text("No results for \"\(search)\"").font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 40)
        } else {
            ForEach(filtered) { stock in
                HStack(spacing: 0) {
                    Button {
                        selectedSymbol = stock.symbol
                        showOrderSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            let owned = model.holdings.first(where: { $0.symbol == stock.symbol }) != nil
                            ZStack(alignment: .topTrailing) {
                                Text(stock.symbol)
                                    .font(.mono(12, weight: .semibold))
                                    .foregroundStyle(owned ? Theme.emerald : Theme.primary)
                                    .frame(width: 44, height: 36)
                                    .background(owned ? Theme.emerald.opacity(0.12) : Theme.secondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                if owned {
                                    Circle()
                                        .fill(Theme.emerald)
                                        .frame(width: 7, height: 7)
                                        .offset(x: 3, y: -3)
                                }
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(stock.name).font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Theme.foreground).lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(stock.sector)
                                        .font(.system(size: 10)).foregroundStyle(Theme.mutedForeground)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(.white.opacity(0.05))
                                        .overlay(Capsule().stroke(.white.opacity(0.08)))
                                        .clipShape(Capsule())
                                    Text(stock.volume).font(.mono(10)).foregroundStyle(Theme.mutedForeground)
                                }
                            }
                            Spacer(minLength: 8)
                            let dir = model.priceDirection(for: stock.symbol, current: stock.price)
                            VStack(alignment: .trailing, spacing: 4) {
                                HStack(spacing: 3) {
                                    if dir != 0 {
                                        Image(systemName: dir > 0 ? "arrow.up" : "arrow.down")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(dir > 0 ? Theme.emerald : Theme.red)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                    Text("$\(stock.price.money())")
                                        .font(.mono(14, weight: .medium))
                                        .foregroundStyle(dir > 0 ? Theme.emerald : dir < 0 ? Theme.red : Theme.foreground)
                                        .contentTransition(.numericText())
                                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: stock.price)
                                }
                                .animation(.spring(response: 0.3), value: dir)
                                PnlBadge(change: stock.change, pct: stock.pct)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedSymbol  = stock.symbol
                        showDetailSheet = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.leading, 10)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background {
                    let d = model.priceDirection(for: stock.symbol, current: stock.price)
                    if d > 0 { Theme.emerald.opacity(0.05) }
                    else if d < 0 { Theme.red.opacity(0.05) }
                }
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
            }
        }
    }
}

// MARK: - Order sheet

private struct OrderSheet: View {
    let stock:         Stock
    let balance:       Double
    let currentShares: Int
    let onPlace:       (TradeOrder) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var side:       OrderSide = .buy
    @State private var qty:        Int       = 1
    @State private var stopLoss:   String
    @State private var takeProfit: String

    init(stock: Stock, balance: Double, currentShares: Int,
         stopLossPct: Double = 0.03, takeProfitPct: Double = 0.06,
         onPlace: @escaping (TradeOrder) -> Void) {
        self.stock         = stock
        self.balance       = balance
        self.currentShares = currentShares
        self.onPlace       = onPlace
        _stopLoss   = State(initialValue: String(format: "%.2f", stock.price * (1 - stopLossPct)))
        _takeProfit = State(initialValue: String(format: "%.2f", stock.price * (1 + takeProfitPct)))
    }

    private var totalCost: Double  { Double(qty) * stock.price }
    private var canAfford: Bool    { side == .sell || balance >= totalCost }
    private var maxBuyQty: Int     { stock.price > 0 ? max(1, Int(balance / stock.price)) : 1 }
    private var sellableQty: Int   { currentShares }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stock.symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.foreground)
                    Text("$\(stock.price.money()) · Live price").font(.mono(12)).foregroundStyle(Theme.mutedForeground)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(Theme.mutedForeground)
                        .frame(width: 32, height: 32).background(Theme.card)
                        .overlay(Circle().stroke(Theme.border)).clipShape(Circle())
                }
            }
            .padding(.bottom, 12)

            // Context row: balance + current position
            HStack(spacing: 0) {
                contextStat("Available", "$\(balance.money(0))", Theme.emerald)
                Divider().frame(height: 28).background(Theme.border).padding(.horizontal, 8)
                contextStat("You Own", "\(currentShares) sh", currentShares > 0 ? Theme.primary : Theme.mutedForeground)
                Divider().frame(height: 28).background(Theme.border).padding(.horizontal, 8)
                contextStat("Entry", "$\(stock.price.money())", Theme.foreground)
            }
            .padding(10)
            .background(Theme.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 12)

            // BUY / SELL toggle
            HStack(spacing: 4) {
                ForEach(OrderSide.allCases, id: \.self) { s in
                    Button { side = s; qty = 1 } label: {
                        Text(s.rawValue).font(.system(size: 12, weight: .bold))
                            .foregroundStyle(side == s ? .white : .white.opacity(0.4))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background {
                                if side == s {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(s == .buy ? Color(hex: 0x16A34A) : Color(hex: 0xDC2626))
                                }
                            }
                    }
                    .disabled(s == .sell && currentShares == 0)
                    .opacity(s == .sell && currentShares == 0 ? 0.35 : 1)
                }
            }
            .padding(4).background(Theme.secondary).clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 12)

            // Quantity
            VStack(alignment: .leading, spacing: 6) {
                Text("SHARES").font(.system(size: 10)).tracking(1.5).foregroundStyle(Theme.mutedForeground)
                HStack {
                    Button { qty = max(1, qty - 1) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.mutedForeground)
                            .frame(width: 36, height: 36).background(Theme.secondary).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Text("\(qty)")
                        .font(.mono(18, weight: .heavy)).foregroundStyle(canAfford ? Theme.foreground : Theme.red)
                        .frame(maxWidth: .infinity)
                    Button { qty = min(qty + 1, side == .buy ? maxBuyQty : sellableQty) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.mutedForeground)
                            .frame(width: 36, height: 36).background(Theme.secondary).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.card).overlay(RoundedRectangle(cornerRadius: 12).stroke(canAfford ? Theme.border : Theme.red.opacity(0.5)))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Quick-qty chips
                if side == .buy {
                    HStack(spacing: 6) {
                        ForEach([("25%", 0.25), ("50%", 0.50), ("Max", 1.0)], id: \.0) { label, frac in
                            let q = max(1, Int(Double(maxBuyQty) * frac))
                            Button { qty = q } label: {
                                Text(label)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(qty == q ? Theme.primary : .white.opacity(0.35))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(qty == q ? Theme.primary.opacity(0.15) : .white.opacity(0.04))
                                    .overlay(Capsule().stroke(qty == q ? Theme.primary.opacity(0.5) : .white.opacity(0.08)))
                                    .clipShape(Capsule())
                            }
                        }
                        Spacer()
                        Text("Total: $\(totalCost.money())")
                            .font(.mono(11)).foregroundStyle(canAfford ? Theme.mutedForeground : Theme.red)
                    }
                } else {
                    HStack(spacing: 6) {
                        ForEach([("¼", 0.25), ("½", 0.50), ("All", 1.0)], id: \.0) { label, frac in
                            let q = max(1, Int(Double(sellableQty) * frac))
                            Button { qty = q } label: {
                                Text(label)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(qty == q ? Theme.red : .white.opacity(0.35))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(qty == q ? Theme.red.opacity(0.15) : .white.opacity(0.04))
                                    .overlay(Capsule().stroke(qty == q ? Theme.red.opacity(0.5) : .white.opacity(0.08)))
                                    .clipShape(Capsule())
                            }
                        }
                        Spacer()
                        let gain = (stock.price - (stock.price * 0.97)) * Double(qty) // rough estimate
                        Text("Est. proceeds: $\((Double(qty) * stock.price).money())")
                            .font(.mono(11)).foregroundStyle(Theme.mutedForeground)
                    }
                }
            }
            .padding(.bottom, 12)

            // SL / TP (buy only)
            if side == .buy {
                HStack(spacing: 12) {
                    priceField(title: "Stop Loss",   icon: "shield.lefthalf.filled", tint: Theme.red,     text: $stopLoss)
                    priceField(title: "Take Profit", icon: "dollarsign.circle",      tint: Theme.emerald,  text: $takeProfit)
                }
                .padding(.bottom, 12)
            }

            // Insufficient funds warning
            if !canAfford {
                Label("Insufficient balance for this order", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
            }

            // Place button
            Button {
                onPlace(TradeOrder(symbol: stock.symbol, name: stock.name, side: side,
                                   qty: qty, entryPrice: stock.price,
                                   stopLoss: side == .buy ? stopLoss : "",
                                   takeProfit: side == .buy ? takeProfit : ""))
                dismiss()
            } label: {
                Label("Place \(side.rawValue) — \(qty) × \(stock.symbol)", systemImage: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(side == .buy ? Theme.buyGradient : Theme.sellGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!canAfford)
            .opacity(!canAfford ? 0.4 : 1)
        }
        .padding(.horizontal, 20).padding(.top, 20)
    }

    private func contextStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.mono(12, weight: .semibold)).foregroundStyle(color)
            Text(label).font(.system(size: 9)).foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }

    private func priceField(title: String, icon: String, tint: Color, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title.uppercased(), systemImage: icon).font(.system(size: 10)).tracking(1).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    Text("$").font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
                    TextField("", text: text).keyboardType(.decimalPad)
                        .font(.mono(14, weight: .semibold)).foregroundStyle(tint)
                }
                Text(pctString(for: text.wrappedValue)).font(.mono(10)).foregroundStyle(Theme.mutedForeground)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card).overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.25)))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func pctString(for value: String) -> String {
        guard let v = Double(value) else { return "—" }
        let pct = (v - stock.price) / stock.price * 100
        return String(format: "%@%.1f%%", pct >= 0 ? "+" : "", pct)
    }
}

// MARK: - Stock detail sheet

private struct StockDetailSheet: View {
    let stock:   Stock
    let onTrade: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(stock.symbol).font(.mono(18, weight: .bold)).foregroundStyle(Theme.foreground)
                        Text(stock.rating)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(stock.ratingColor.opacity(0.12))
                            .foregroundStyle(stock.ratingColor)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    Text(stock.name).font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(Theme.mutedForeground)
                        .frame(width: 32, height: 32).background(Theme.card)
                        .overlay(Circle().stroke(Theme.border)).clipShape(Circle())
                }
            }
            .padding(.bottom, 12)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("$\(stock.price.money())").font(.mono(24, weight: .bold)).foregroundStyle(Theme.foreground)
                PnlBadge(change: stock.change, pct: stock.pct)
            }
            .padding(.bottom, 16)

            VStack(spacing: 6) {
                HStack {
                    Text("52W Low $\(stock.low52.money())").font(.system(size: 10)).foregroundStyle(Theme.mutedForeground)
                    Spacer()
                    Text("52W High $\(stock.high52.money())").font(.system(size: 10)).foregroundStyle(Theme.mutedForeground)
                }
                GeometryReader { geo in
                    Capsule().fill(Theme.secondary)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.primary, Theme.indigo], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * stock.range52Fraction)
                        }
                }
                .frame(height: 6)
                Text("\(Int(stock.range52Fraction * 100))% of 52w range")
                    .font(.system(size: 10)).foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.bottom, 16)

            HStack(spacing: 10) {
                detailStat("Market Cap", stock.mktCap)
                detailStat("P/E Ratio",  stock.pe.money(1))
                detailStat("Volume",     stock.volume)
            }
            .padding(.bottom, 20)

            Button(action: onTrade) {
                Label("Trade \(stock.symbol)", systemImage: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Theme.brandGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, 20).padding(.top, 20)
    }

    private func detailStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.foreground)
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.mutedForeground)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(Theme.card).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Price alerts sheet

private struct PriceAlertsSheet: View {
    @Binding var alerts: [PriceAlert]
    let stocks: [Stock]
    @Environment(\.dismiss) private var dismiss

    @State private var symbol = MarketService.watchlist[0]
    @State private var target = ""
    @State private var above  = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Price Alerts", systemImage: "bell").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(Theme.mutedForeground)
                        .frame(width: 28, height: 28).background(Theme.card)
                        .overlay(Circle().stroke(Theme.border)).clipShape(Circle())
                }
            }
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 10) {
                Text("NEW ALERT").font(.system(size: 10)).tracking(1.5).foregroundStyle(Theme.mutedForeground)
                HStack(spacing: 8) {
                    Picker("", selection: $symbol) {
                        ForEach(stocks.isEmpty ? MarketService.watchlist : stocks.map(\.symbol), id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .pickerStyle(.menu).tint(Theme.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.secondary).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 0) {
                        dirButton(true,  "↑", Color(hex: 0x16A34A))
                        dirButton(false, "↓", Color(hex: 0xDC2626))
                    }
                    .background(Theme.secondary).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("$").font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
                        TextField("", text: $target, prompt: Text("Target price").foregroundColor(Theme.mutedForeground))
                            .keyboardType(.decimalPad).font(.mono(12)).foregroundStyle(Theme.foreground)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Theme.secondary).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    Button {
                        guard !target.isEmpty else { return }
                        withAnimation { alerts.append(PriceAlert(symbol: symbol, target: target, above: above)) }
                        target = ""
                    } label: {
                        Text("Add").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(LinearGradient(colors: [Theme.primary, Theme.indigo], startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(target.isEmpty).opacity(target.isEmpty ? 0.3 : 1)
                }
            }
            .padding(12).background(Theme.card).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 16)

            if alerts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell").font(.system(size: 20)).foregroundStyle(.white.opacity(0.25))
                    Text("No alerts set yet").font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                Text("ACTIVE (\(alerts.count))").font(.system(size: 10)).tracking(1.5).foregroundStyle(Theme.mutedForeground)
                    .padding(.bottom, 8)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(alerts) { alert in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(alert.symbol).font(.mono(12, weight: .bold)).foregroundStyle(Theme.foreground)
                                        Text("\(alert.above ? "↑ Above" : "↓ Below") $\(alert.target)")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(alert.above ? Theme.emerald : Theme.red)
                                    }
                                    if let s = stocks.first(where: { $0.symbol == alert.symbol }) {
                                        Text("Current: $\(s.price.money())").font(.system(size: 10)).foregroundStyle(Theme.mutedForeground)
                                    }
                                }
                                Spacer()
                                Button {
                                    withAnimation { alerts.removeAll { $0.id == alert.id } }
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(Theme.card).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 20)
    }

    private func dirButton(_ isAbove: Bool, _ glyph: String, _ tint: Color) -> some View {
        Button { above = isAbove } label: {
            Text(glyph).font(.system(size: 12, weight: .bold))
                .foregroundStyle(above == isAbove ? .white : .white.opacity(0.4))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(above == isAbove ? tint : .clear)
        }
    }
}

#Preview {
    TradeView().environment(AppModel())
}
