//
//  StockDetailSheet.swift
//  Fortune
//
//  Fundamentals for one stock: analyst rating, 52-week range, market cap, P/E.
//

import SwiftUI

struct StockDetailSheet: View {
    let stock:   Stock
    let onTrade: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.bottom, 12)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("$\(stock.price.money())").font(.mono(24, weight: .bold)).foregroundStyle(Theme.foreground)
                PnlBadge(change: stock.change, pct: stock.pct)
            }
            .padding(.bottom, 16)

            range52.padding(.bottom, 16)

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

    private var header: some View {
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
            let starred = model.isStarred(stock.symbol)
            Button { model.toggleStar(stock.symbol) } label: {
                Image(systemName: starred ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundStyle(starred ? Color(hex: 0xF59E0B) : Theme.mutedForeground)
                    .frame(width: 32, height: 32).background(Theme.card)
                    .overlay(Circle().stroke(Theme.border)).clipShape(Circle())
            }
            .accessibilityLabel(starred ? "Unstar" : "Star")
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(Theme.mutedForeground)
                    .frame(width: 32, height: 32).background(Theme.card)
                    .overlay(Circle().stroke(Theme.border)).clipShape(Circle())
            }
            .accessibilityLabel("Close")
        }
    }

    private var range52: some View {
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
