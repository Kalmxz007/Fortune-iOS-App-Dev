//
//  PnLView.swift
//  Fortune
//
//  Portfolio screen: live PnL, candlestick chart, performance stats.
//

import SwiftUI
import Charts

struct PnLView: View {
    @Environment(AppModel.self) private var model

    private let allocColors: [UInt] = [0x38D4FF, 0x6D74FF, 0xB06AFF, 0x4ADE80]
    @State private var closingSymbol:   String?  = nil
    @State private var sellTarget:      Holding? = nil
    @State private var showSellSheet             = false
    @State private var alertVisible              = false

    private var yScale: ClosedRange<Double> {
        let values = model.pnlCandles.flatMap { [$0.high, $0.low] }
        guard !values.isEmpty else { return -1000...2000 }
        let lo  = values.min()!
        let hi  = values.max()!
        let pad = (hi - lo) * 0.2
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ImmersiveBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow.padding(.top, 18).padding(.bottom, 16)
                    hero
                    chart.frame(height: 150).padding(.top, 16)
                    GradientDivider().padding(.vertical, 14)
                    statsRow
                    performanceSection.padding(.top, 18)
                    allocationSection.padding(.top, 18)
                    holdingsSection.padding(.top, 20)
                    tradeJournalSection.padding(.top, 20)
                    if model.weeklyDigestEnabled {
                        newsSection.padding(.top, 20)
                    }
                    FortuneFooter().padding(.top, 20)
                }
                .padding(.horizontal, 22).padding(.bottom, 20)
            }

            // SL/TP alert toast
            if alertVisible, let msg = model.lastAlert {
                Text(msg)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .background(msg.contains("Stop Loss") ? Theme.red.opacity(0.7) : Theme.emerald.opacity(0.7))
                    .clipShape(Capsule())
                    .shadow(radius: 8)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .onChange(of: model.lastAlert) { _, new in
            guard new != nil else { return }
            withAnimation(.spring(response: 0.4)) { alertVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation { alertVisible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.lastAlert = nil }
            }
        }
        .sheet(isPresented: $showSellSheet) {
            if let h = sellTarget {
                PartialSellSheet(holding: h) { shares in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        model.partialSell(holding: h, shares: shares)
                    }
                }
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
                .presentationCornerRadius(24)
            }
        }
        // Keep unrealized PnL current while this tab is visible
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await model.refreshQuotes()
            }
        }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack {
            HStack(spacing: 10) {
                LogoView(size: 30)
                Text("FORTUNE").font(.system(size: 15, weight: .bold)).tracking(3).foregroundStyle(.white.opacity(0.92))
            }
            Spacer()
            Text("LIVE").font(.mono(10)).tracking(0.6).foregroundStyle(.white.opacity(0.28))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(.white.opacity(0.03)).overlay(Capsule().stroke(.white.opacity(0.08))).clipShape(Capsule())
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("COMBINED PNL").font(.system(size: 11, weight: .medium)).tracking(0.6)
                .foregroundStyle(.white.opacity(0.35)).padding(.bottom, 6)
            let pnl = model.totalPnL
            Text("\(pnl >= 0 ? "+" : "")$\(abs(pnl).money())")
                .font(.mono(42, weight: .bold)).foregroundStyle(pnl >= 0 ? Theme.green : Theme.red)
                .contentTransition(.numericText(countsDown: pnl < 0))
                .animation(.spring(response: 0.4), value: pnl)
            let pct = model.startingCapital > 0 ? (pnl / model.startingCapital * 100) : 0
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Image(systemName: pnl >= 0 ? "arrow.up.right" : "arrow.down.right").font(.system(size: 11, weight: .bold))
                    Text("\(pct >= 0 ? "+" : "")\(String(format: "%.2f", pct))%").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(pnl >= 0 ? Theme.green : Theme.red)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background((pnl >= 0 ? Theme.green : Theme.red).opacity(0.12))
                .overlay(Capsule().stroke((pnl >= 0 ? Theme.green : Theme.red).opacity(0.20))).clipShape(Capsule())
                Text("All time").font(.system(size: 12)).foregroundStyle(.white.opacity(0.30))
                Text("·").foregroundStyle(.white.opacity(0.15))
                Text("Cash: $\(model.balance.money(0))").font(.system(size: 11)).foregroundStyle(.white.opacity(0.22))
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Candlestick chart

    private var chart: some View {
        Group {
            if model.pnlCandles.isEmpty {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.04))
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "chart.bar").font(.system(size: 20)).foregroundStyle(.white.opacity(0.2))
                            Text("Place trades to see your P&L chart")
                                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.25))
                        }
                    }
            } else {
                let lineColor = model.totalPnL >= 0 ? Theme.green : Theme.red
                Chart {
                    ForEach(model.pnlCandles) { candle in
                        AreaMark(
                            x: .value("Day", candle.day),
                            y: .value("PnL", candle.close)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [lineColor.opacity(0.25), lineColor.opacity(0.0)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("Day", candle.day),
                            y: .value("PnL", candle.close)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(lineColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(.white.opacity(0.08))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    RuleMark(y: .value("Current", model.totalPnL))
                        .foregroundStyle(Theme.primary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .annotation(position: .trailing, alignment: .leading) {
                            Text(model.totalPnL >= 0 ? "+\(Int(model.totalPnL / 1000))k" : "\(Int(model.totalPnL / 1000))k")
                                .font(.mono(8)).foregroundStyle(Theme.primary)
                        }
                }
                .chartYScale(domain: yScale)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel().font(.mono(8)).foregroundStyle(.white.opacity(0.22))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                            .foregroundStyle(.white.opacity(0.05))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v == 0 ? "0" : "\(v > 0 ? "+" : "")\(Int(v / 1000))k")
                                    .font(.mono(8)).foregroundStyle(.white.opacity(0.25))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Stats row

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell("Realized",     "\(model.realizedPnL >= 0 ? "+" : "")$\(abs(model.realizedPnL).money(0))", model.realizedPnL >= 0 ? Theme.green : Theme.red, first: true)
            divider
            statCell("Unrealized",   "\(model.unrealizedPnL >= 0 ? "+" : "")$\(abs(model.unrealizedPnL).money(0))", model.unrealizedPnL >= 0 ? Theme.green : Theme.red)
            divider
            statCell("Win Rate",     model.closedTradeCount > 0 ? "\(String(format: "%.1f", model.winRate * 100))%" : "—", .white.opacity(0.95))
            divider
            statCell("Trades",       "\(model.orders.count)", .white.opacity(0.95))
            divider
            let pf: String = {
                guard model.closedTradeCount > 0 && model.realizedPnL != 0 else { return "—" }
                return String(format: "%.2f×", abs(model.realizedPnL / max(1, Double(model.closedTradeCount))))
            }()
            statCell("Avg Trade",    pf, Theme.accent)
        }
    }

    private var divider: some View { Rectangle().fill(.white.opacity(0.07)).frame(width: 1, height: 28) }

    private func statCell(_ label: String, _ value: String, _ color: Color, first: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.mono(12, weight: .semibold)).foregroundStyle(color)
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.26))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, first ? 0 : 6)
    }

    // MARK: Performance

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Performance")
            if model.holdings.isEmpty && model.orders.isEmpty {
                Text("No trades yet — performance data will appear here.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.3))
            } else {
                let best  = model.holdings.max(by: { $0.pnl < $1.pnl })
                let worst = model.holdings.min(by: { $0.pnl < $1.pnl })
                HStack(spacing: 8) {
                    perfCell("Best Position",
                             best.map { h in "\(h.pnl >= 0 ? "+" : "")$\(abs(h.pnl).money(0))" } ?? "—",
                             best?.symbol ?? "—", Theme.green)
                    perfCell("Worst Position",
                             worst.map { h in "\(h.pnl >= 0 ? "+" : "")$\(abs(h.pnl).money(0))" } ?? "—",
                             worst?.symbol ?? "—", Theme.red)
                    perfCell("Win Streak", "\(model.winCount) 🔥", "All time", Color(hex: 0xF59E0B))
                }
            }
        }
    }

    private func perfCell(_ label: String, _ value: String, _ sub: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.mono(13, weight: .bold)).foregroundStyle(color)
            Text(label).font(.system(size: 9)).foregroundStyle(.white.opacity(0.30))
            Text(sub).font(.system(size: 9)).foregroundStyle(.white.opacity(0.20))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
        .background(.white.opacity(0.04)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.07)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Allocation donut

    private var allocationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Allocation")
            if model.holdings.isEmpty {
                Text("No open positions.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.3))
            } else {
                HStack(spacing: 16) {
                    DonutChart(slices: slices).frame(width: 80, height: 80)
                    VStack(spacing: 6) {
                        ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                            HStack(spacing: 8) {
                                Circle().fill(slice.color).frame(width: 8, height: 8)
                                Text(slice.symbol).font(.mono(11, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                                Spacer()
                                Text("\(slice.pct.money(1))%").font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
                            }
                        }
                    }
                }
            }
        }
    }

    private var slices: [DonutChart.Slice] {
        let total = model.holdings.reduce(0.0) { $0 + $1.marketValue }
        guard total > 0 else { return [] }
        return model.holdings.enumerated().map { i, h in
            .init(symbol: h.symbol, pct: h.marketValue / total * 100,
                  color: Color(hex: allocColors[i % allocColors.count]))
        }
    }

    // MARK: Holdings

    private var holdingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Open Positions")
                Spacer()
                Text("\(model.holdings.count) positions").font(.mono(10)).foregroundStyle(.white.opacity(0.25))
            }
            if model.holdings.isEmpty {
                Text("No open positions — buy a stock on the Trade tab.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.3))
            } else {
                VStack(spacing: 8) {
                    ForEach(model.holdings) { h in
                        Button {
                            sellTarget  = h
                            showSellSheet = true
                        } label: {
                            HStack(spacing: 12) {
                                // Icon + live status dot
                                ZStack(alignment: .bottomTrailing) {
                                    Text(String(h.symbol.prefix(4)))
                                        .font(.mono(9, weight: .bold)).foregroundStyle(Theme.primary)
                                        .frame(width: 36, height: 36)
                                        .background(Theme.primary.opacity(0.1))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.primary.opacity(0.2)))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    Circle().fill(h.pnl >= 0 ? Theme.green : Theme.red).frame(width: 8, height: 8)
                                        .offset(x: 2, y: 2)
                                }
                                VStack(spacing: 4) {
                                    HStack {
                                        Text(h.symbol).font(.mono(13, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                                        Text("\(h.shares) sh").font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
                                        Spacer()
                                        Text("\(h.pnl >= 0 ? "+" : "-")$\(abs(h.pnl).money(0))")
                                            .font(.mono(13, weight: .bold)).foregroundStyle(h.pnl >= 0 ? Theme.green : Theme.red)
                                            .contentTransition(.numericText(countsDown: h.pnl < 0))
                                            .animation(.spring(response: 0.4), value: h.pnl)
                                    }
                                    HStack {
                                        // Mini progress bar: entry → current
                                        GeometryReader { geo in
                                            Capsule().fill(.white.opacity(0.06))
                                                .overlay(alignment: .leading) {
                                                    let frac = min(max((h.current - h.avgCost * 0.9) / (h.avgCost * 0.2), 0), 1)
                                                    Capsule()
                                                        .fill(h.pnl >= 0 ? Theme.green : Theme.red)
                                                        .frame(width: geo.size.width * frac)
                                                }
                                        }
                                        .frame(height: 3)
                                        Text("\(h.pct.signPrefix)\(String(format: "%.2f", h.pct))%")
                                            .font(.mono(10)).foregroundStyle(h.pnl >= 0 ? Theme.green : Theme.red)
                                    }
                                    HStack {
                                        Text("avg $\(h.avgCost.money()) · now $\(h.current.money())")
                                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
                                        Spacer()
                                        Text("Tap to sell").font(.system(size: 9)).foregroundStyle(.white.opacity(0.2))
                                    }
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 12)
                            .background(.white.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                                h.pnl >= 0 ? Theme.green.opacity(0.2) : Theme.red.opacity(0.2)
                            ))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Trade journal

    private var tradeJournalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Trade Journal")
                Spacer()
                if !model.closedTrades.isEmpty {
                    Text("\(model.closedTrades.count) closed").font(.mono(10)).foregroundStyle(.white.opacity(0.25))
                }
            }
            if model.closedTrades.isEmpty {
                Text("No closed trades yet. Buy then sell a position to build your journal.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.3))
            } else {
                VStack(spacing: 6) {
                    ForEach(model.closedTrades.prefix(15)) { trade in
                        HStack(spacing: 10) {
                            Text(trade.exitReason.icon).font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(trade.symbol).font(.mono(12, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                                    Text("\(trade.shares) sh").font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
                                    Text(trade.exitReason.rawValue)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(.white.opacity(0.06))
                                        .foregroundStyle(.white.opacity(0.4))
                                        .clipShape(Capsule())
                                }
                                Text("$\(trade.entryPrice.money()) → $\(trade.exitPrice.money())")
                                    .font(.mono(10)).foregroundStyle(.white.opacity(0.3))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(trade.isWin ? "+" : "-")$\(abs(trade.pnl).money(0))")
                                    .font(.mono(12, weight: .bold))
                                    .foregroundStyle(trade.isWin ? Theme.green : Theme.red)
                                Text("\(trade.pct >= 0 ? "+" : "")\(String(format: "%.1f", trade.pct))%")
                                    .font(.system(size: 10))
                                    .foregroundStyle(trade.isWin ? Theme.green.opacity(0.7) : Theme.red.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(trade.isWin ? Theme.green.opacity(0.05) : Theme.red.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                            trade.isWin ? Theme.green.opacity(0.15) : Theme.red.opacity(0.15)
                        ))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    // MARK: News

    private var newsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "newspaper").font(.system(size: 12)).foregroundStyle(.white.opacity(0.35))
                sectionTitle("Market News")
            }
            if model.news.isEmpty {
                Text("Loading market news…").font(.system(size: 11)).foregroundStyle(.white.opacity(0.3))
            } else {
                VStack(spacing: 10) {
                    ForEach(model.news) { n in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(n.tag).font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background((n.bullish ? Theme.green : Theme.red).opacity(0.15))
                                    .foregroundStyle(n.bullish ? Theme.green : Theme.red)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                Text(n.source).font(.mono(10)).foregroundStyle(.white.opacity(0.25))
                                Spacer()
                                Text(n.time).font(.system(size: 10)).foregroundStyle(.white.opacity(0.18))
                            }
                            Text(n.headline).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(.white.opacity(0.03)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.06)))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(.white.opacity(0.35))
    }
}

// MARK: - Donut chart

struct DonutChart: View {
    struct Slice { let symbol: String; let pct: Double; let color: Color }
    let slices: [Slice]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer  = min(size.width, size.height) / 2
            let inner  = outer * 0.58
            var start  = Angle.degrees(-90)
            for slice in slices {
                let sweep = Angle.degrees(slice.pct / 100 * 360)
                let end   = start + sweep - .degrees(1.5)
                var path  = Path()
                path.addArc(center: center, radius: outer, startAngle: start, endAngle: end,   clockwise: false)
                path.addArc(center: center, radius: inner, startAngle: end,   endAngle: start, clockwise: true)
                path.closeSubpath()
                context.fill(path, with: .color(slice.color))
                start = start + sweep
            }
        }
    }
}

// MARK: - Partial sell sheet

private struct PartialSellSheet: View {
    let holding: Holding
    let onSell:  (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var qty: Int

    init(holding: Holding, onSell: @escaping (Int) -> Void) {
        self.holding = holding
        self.onSell  = onSell
        _qty = State(initialValue: holding.shares)
    }

    private var proceeds:    Double { Double(qty) * holding.current }
    private var estimatedPnL: Double { (holding.current - holding.avgCost) * Double(qty) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sell \(holding.symbol)").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    Text("\(holding.shares) shares · avg cost $\(holding.avgCost.money())").font(.mono(12)).foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(.white.opacity(0.4))
                        .frame(width: 32, height: 32).background(.white.opacity(0.06))
                        .overlay(Circle().stroke(.white.opacity(0.1))).clipShape(Circle())
                }
            }
            .padding(.bottom, 20)

            // Qty stepper
            VStack(alignment: .leading, spacing: 8) {
                Text("SHARES TO SELL").font(.system(size: 10)).tracking(1.5).foregroundStyle(.white.opacity(0.3))
                HStack(spacing: 0) {
                    Button { qty = max(1, qty - 1) } label: {
                        Image(systemName: "minus").font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5)).frame(width: 52, height: 52)
                    }
                    Text("\(qty)").font(.mono(28, weight: .heavy))
                        .foregroundStyle(.white).frame(maxWidth: .infinity)
                    Button { qty = min(qty + 1, holding.shares) } label: {
                        Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5)).frame(width: 52, height: 52)
                    }
                }
                .background(.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08)))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // Quick fractions
                HStack(spacing: 6) {
                    ForEach([("¼", 0.25), ("½", 0.50), ("¾", 0.75), ("All", 1.0)], id: \.0) { label, frac in
                        let q = max(1, Int(Double(holding.shares) * frac))
                        Button { qty = q } label: {
                            Text(label).font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(qty == q ? Theme.red : .white.opacity(0.3))
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                                .background(qty == q ? Theme.red.opacity(0.15) : .white.opacity(0.04))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(qty == q ? Theme.red.opacity(0.4) : .white.opacity(0.08)))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(.bottom, 20)

            // Summary
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Proceeds").font(.system(size: 11)).foregroundStyle(.white.opacity(0.3))
                    Text("$\(proceeds.money())").font(.mono(15, weight: .bold)).foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Est. P&L").font(.system(size: 11)).foregroundStyle(.white.opacity(0.3))
                    Text("\(estimatedPnL >= 0 ? "+" : "-")$\(abs(estimatedPnL).money())")
                        .font(.mono(15, weight: .bold))
                        .foregroundStyle(estimatedPnL >= 0 ? Theme.green : Theme.red)
                }
            }
            .padding(14)
            .background(.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 16)

            Button {
                onSell(qty)
                dismiss()
            } label: {
                Label("Sell \(qty) × \(holding.symbol) @ $\(holding.current.money())", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Theme.sellGradient).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, 20).padding(.top, 20)
    }
}

#Preview {
    PnLView().environment(AppModel())
}
