//
//  PriceAlertsSheet.swift
//  Fortune
//
//  Create and remove price alerts. Each alert fires once when its target is crossed.
//

import SwiftUI

struct PriceAlertsSheet: View {
    @Binding var alerts: [PriceAlert]
    let stocks: [Stock]
    @Environment(\.dismiss) private var dismiss

    @State private var symbol = MarketService.watchlist[0]
    @State private var target = ""
    @State private var above  = true

    private var targetValue: Double? {
        guard let value = Double(target), value > 0 else { return nil }
        return value
    }

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
                .accessibilityLabel("Close")
            }
            .padding(.bottom, 16)

            newAlertForm.padding(.bottom, 16)

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
                        ForEach(alerts) { alert in alertRow(alert) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 20)
    }

    private var newAlertForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEW ALERT").font(.system(size: 10)).tracking(1.5).foregroundStyle(Theme.mutedForeground)
            HStack(spacing: 8) {
                Picker("Stock", selection: $symbol) {
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
                    guard let value = targetValue else { return }
                    withAnimation { alerts.append(PriceAlert(symbol: symbol, target: value, above: above)) }
                    target = ""
                } label: {
                    Text("Add").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(LinearGradient(colors: [Theme.primary, Theme.indigo], startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(targetValue == nil).opacity(targetValue == nil ? 0.3 : 1)
            }
        }
        .padding(12).background(Theme.card).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func alertRow(_ alert: PriceAlert) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(alert.symbol).font(.mono(12, weight: .bold)).foregroundStyle(Theme.foreground)
                    Text("\(alert.above ? "↑ Above" : "↓ Below") $\(alert.target.money())")
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
            .accessibilityLabel("Remove \(alert.symbol) alert")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.card).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func dirButton(_ isAbove: Bool, _ glyph: String, _ tint: Color) -> some View {
        Button { above = isAbove } label: {
            Text(glyph).font(.system(size: 12, weight: .bold))
                .foregroundStyle(above == isAbove ? .white : .white.opacity(0.4))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(above == isAbove ? tint : .clear)
        }
        .accessibilityLabel(isAbove ? "Alert when above" : "Alert when below")
    }
}
