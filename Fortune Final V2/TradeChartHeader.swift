//
//  TradeChartHeader.swift
//  Fortune
//
//  Top of the Trade screen: live price, daily change, alerts bell,
//  timeframe picker, and the candlestick chart.
//

import SwiftUI
import Charts

struct TradeChartHeader: View {
    let stock:         Stock
    let candles:       [Candle]
    let direction:     Int        // +1 up, -1 down, 0 unchanged since last tick
    let isLoading:     Bool
    let isRefreshing:  Bool
    let hasStocks:     Bool
    let alertCount:    Int
    @Binding var timeframe: Timeframe
    let onShowAlerts:  () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                priceBlock
                Spacer()
                if hasStocks { changeBlock }
            }
            timeframePicker
            chart
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
        .background(Theme.card)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private var priceBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(stock.symbol).font(.mono(11)).tracking(2).foregroundStyle(Theme.mutedForeground)
                PulsingDot()
                Text("LIVE").font(.system(size: 11)).foregroundStyle(Theme.emerald)
                if isRefreshing {
                    ProgressView().scaleEffect(0.5).tint(Theme.emerald)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isRefreshing)
            if isLoading && !hasStocks {
                ProgressView().tint(Theme.primary).scaleEffect(0.7)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("$\(stock.price.money())")
                        .font(.mono(24, weight: .semibold))
                        .foregroundStyle(direction > 0 ? Theme.emerald : direction < 0 ? Theme.red : Theme.foreground)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: stock.price)
                    if direction != 0 {
                        Image(systemName: direction > 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(direction > 0 ? Theme.emerald : Theme.red)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3), value: direction)
            }
        }
    }

    private var changeBlock: some View {
        VStack(alignment: .trailing, spacing: 4) {
            PnlBadge(change: stock.change, pct: stock.pct)
            HStack(spacing: 8) {
                Text("\(stock.change.signPrefix)\(stock.change.money())")
                    .font(.mono(11)).foregroundStyle(Theme.mutedForeground)
                Button(action: onShowAlerts) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                            .font(.system(size: 14))
                            .foregroundStyle(alertCount == 0 ? Color.white.opacity(0.3) : Theme.primary)
                            .padding(2)
                        if alertCount > 0 {
                            Text("\(alertCount)")
                                .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 14, height: 14)
                                .background(Theme.primary).clipShape(Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
                }
                .accessibilityLabel("Price alerts")
            }
        }
    }

    private var timeframePicker: some View {
        HStack(spacing: 4) {
            ForEach(Timeframe.allCases, id: \.self) { tf in
                let on = timeframe == tf
                Button { timeframe = tf } label: {
                    Text(tf.label)
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
    }

    @ViewBuilder
    private var chart: some View {
        if candles.isEmpty {
            RoundedRectangle(cornerRadius: 4)
                .fill(.white.opacity(0.05))
                .frame(height: 160)
                .overlay {
                    if isLoading { ProgressView().tint(Theme.primary) }
                }
        } else {
            Chart(candles) { candle in
                let color: Color = candle.isUp ? Theme.emerald : Theme.red
                // Wick: full high-to-low range
                RuleMark(
                    x: .value("t", candle.day),
                    yStart: .value("Low",  candle.low),
                    yEnd:   .value("High", candle.high)
                )
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(color.opacity(0.8))
                // Body: open-to-close range
                RectangleMark(
                    x:      .value("t",     candle.day),
                    yStart: .value("Open",  min(candle.open, candle.close)),
                    yEnd:   .value("Close", max(candle.open, candle.close)),
                    width:  .ratio(0.6)
                )
                .foregroundStyle(color)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: yDomain)
            .frame(height: 160)
            .animation(.easeInOut(duration: 0.25), value: stock.price)
        }
    }

    private var yDomain: ClosedRange<Double> {
        let lo = candles.map(\.low).min()  ?? 0
        let hi = candles.map(\.high).max() ?? 1
        let pad = (hi - lo) * 0.08
        return (lo - pad)...(hi + pad)
    }
}
