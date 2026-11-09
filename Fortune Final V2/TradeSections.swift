//
//  TradeSections.swift
//  Fortune
//
//  Building blocks of the Trade screen's scrolling list: open positions,
//  market movers, search/filter/sort bar, "For You" strip, and stock rows.
//  Each takes plain values + callbacks, so a price tick only redraws what changed.
//

import SwiftUI

// MARK: - Open positions

struct OpenPositionsSection: View {
    let holdings:      [Holding]
    let unrealizedPnL: Double
    let onSell:        (Holding) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "My Positions")
                Spacer()
                Text(unrealizedPnL.signedMoney(0))
                    .font(.mono(11, weight: .semibold))
                    .foregroundStyle(unrealizedPnL >= 0 ? Theme.emerald : Theme.red)
                    .contentTransition(.numericText(countsDown: unrealizedPnL < 0))
                    .animation(.spring(response: 0.4), value: unrealizedPnL)
            }
            ForEach(holdings) { h in
                PositionRow(holding: h) { onSell(h) }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: holdings.map(\.symbol))
    }
}

private struct PositionRow: View {
    let holding: Holding
    let onSell:  () -> Void

    var body: some View {
        let h = holding
        HStack(spacing: 12) {
            Text(String(h.symbol.prefix(4)))
                .font(.mono(9, weight: .bold)).foregroundStyle(Theme.primary)
                .frame(width: 36, height: 36)
                .background(Theme.primary.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.primary.opacity(0.2)))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(h.symbol).font(.mono(12, weight: .semibold)).foregroundStyle(Theme.foreground)
                    Text("×\(h.shares)").font(.system(size: 10)).foregroundStyle(Theme.mutedForeground)
                }
                HStack(spacing: 8) {
                    Label("$\(h.avgCost.money())", systemImage: "arrow.right.circle")
                        .font(.mono(10)).foregroundStyle(Theme.mutedForeground)
                    Text("$\(h.current.money())")
                        .font(.mono(10, weight: .semibold))
                        .foregroundStyle(h.pnl >= 0 ? Theme.emerald : Theme.red)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3), value: h.current)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(h.pnl.signedMoney(0))
                    .font(.mono(12, weight: .bold))
                    .foregroundStyle(h.pnl >= 0 ? Theme.emerald : Theme.red)
                    .contentTransition(.numericText(countsDown: h.pnl < 0))
                    .animation(.spring(response: 0.4), value: h.pnl)
                Text(h.pct.signedPercent())
                    .font(.system(size: 10))
                    .foregroundStyle(h.pnl >= 0 ? Theme.emerald.opacity(0.7) : Theme.red.opacity(0.7))
            }

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { onSell() }
            } label: {
                Text("SELL")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.red)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Theme.red.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.red.opacity(0.3)))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("Sell all \(h.symbol)")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
            h.pnl >= 0 ? Theme.emerald.opacity(0.25) : Theme.red.opacity(0.25)
        ))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Market movers

struct MarketMoversStrip: View {
    let stocks:   [Stock]
    let onSelect: (Stock) -> Void
    @State private var showGainers = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                tabButton(gainers: true,  "↑ Gainers", Theme.green)
                tabButton(gainers: false, "↓ Losers",  Theme.red)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StockFilter.movers(in: stocks, gainers: showGainers)) { stock in
                        Button { onSelect(stock) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stock.symbol).font(.mono(12, weight: .bold)).foregroundStyle(Theme.foreground)
                                Text(stock.pct.signedPercent())
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

    private func tabButton(gainers: Bool, _ label: String, _ tint: Color) -> some View {
        let on = showGainers == gainers
        return Button { showGainers = gainers } label: {
            Text(label)
                .font(.system(size: 10, weight: .bold)).tracking(0.5)
                .foregroundStyle(on ? tint : .white.opacity(0.3))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(on ? tint.opacity(0.15) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Search, sector chips, sort

struct StockFilterBar: View {
    @Binding var filter: StockFilter
    let resultCount: Int

    var body: some View {
        VStack(spacing: 0) {
            searchField
            sectorChips
            sortControls
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Theme.mutedForeground)
            TextField("", text: $filter.search, prompt: Text("Search stocks…").foregroundColor(Theme.mutedForeground))
                .font(.system(size: 13)).foregroundStyle(Theme.foreground)
            if !filter.search.isEmpty {
                Button { filter.search = "" } label: {
                    Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(Theme.mutedForeground)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
    }

    private var sectorChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(StockFilter.chips, id: \.self) { chip in
                    let on = filter.sector == chip
                    Button { filter.sector = chip } label: {
                        Text(chip)
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

    private var sortControls: some View {
        HStack(spacing: 6) {
            Text("Sort:").font(.system(size: 10)).foregroundStyle(Theme.mutedForeground)
            ForEach(StockFilter.Sort.allCases, id: \.self) { option in
                let on = filter.sort == option
                Button { filter.sort = option } label: {
                    Text(option.label)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(on ? Color(hex: 0xA5B4FC) : .white.opacity(0.3))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(on ? Theme.indigo.opacity(0.2) : .clear)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Theme.indigo.opacity(0.35) : .clear))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            Spacer()
            Text("\(resultCount) stocks").font(.system(size: 10)).foregroundStyle(Theme.mutedForeground)
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
    }
}

// MARK: - For You strip

struct ForYouStrip: View {
    let stocks:   [Stock]
    let onSelect: (Stock) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Theme.accent)
                Text("FOR YOU").font(.mono(10)).tracking(1.5).foregroundStyle(Theme.mutedForeground)
            }
            .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(stocks) { stock in
                        Button { onSelect(stock) } label: {
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

// MARK: - Stock row

struct StockRow: View {
    let stock:        Stock
    let isOwned:      Bool
    let isStarred:    Bool
    let direction:    Int
    let onTrade:      () -> Void
    let onToggleStar: () -> Void
    let onInfo:       () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTrade) {
                HStack(spacing: 12) {
                    symbolBadge
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
                            if stock.volume != "—" {
                                Text(stock.volume).font(.mono(10)).foregroundStyle(Theme.mutedForeground)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    priceColumn
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.3)) { onToggleStar() }
            } label: {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .font(.system(size: 15))
                    .foregroundStyle(isStarred ? Color(hex: 0xF59E0B) : .white.opacity(0.4))
                    .padding(.leading, 10)
            }
            .accessibilityLabel(isStarred ? "Unstar \(stock.symbol)" : "Star \(stock.symbol)")

            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.leading, 10)
            }
            .accessibilityLabel("\(stock.symbol) details")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background {
            if direction > 0 { Theme.emerald.opacity(0.05) }
            else if direction < 0 { Theme.red.opacity(0.05) }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private var symbolBadge: some View {
        ZStack(alignment: .topTrailing) {
            Text(stock.symbol)
                .font(.mono(12, weight: .semibold))
                .foregroundStyle(isOwned ? Theme.emerald : Theme.primary)
                .frame(width: 44, height: 36)
                .background(isOwned ? Theme.emerald.opacity(0.12) : Theme.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            if isOwned {
                Circle()
                    .fill(Theme.emerald)
                    .frame(width: 7, height: 7)
                    .offset(x: 3, y: -3)
            }
        }
    }

    private var priceColumn: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 3) {
                if direction != 0 {
                    Image(systemName: direction > 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(direction > 0 ? Theme.emerald : Theme.red)
                        .transition(.scale.combined(with: .opacity))
                }
                Text("$\(stock.price.money())")
                    .font(.mono(14, weight: .medium))
                    .foregroundStyle(direction > 0 ? Theme.emerald : direction < 0 ? Theme.red : Theme.foreground)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: stock.price)
            }
            .animation(.spring(response: 0.3), value: direction)
            PnlBadge(change: stock.change, pct: stock.pct)
        }
    }
}
