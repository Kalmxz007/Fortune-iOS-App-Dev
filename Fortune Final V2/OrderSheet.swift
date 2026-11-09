//
//  OrderSheet.swift
//  Fortune
//
//  Buy / sell order entry with quantity chips and stop-loss / take-profit levels.
//

import SwiftUI

struct OrderSheet: View {
    let stock:         Stock
    let balance:       Double
    let currentShares: Int
    let onPlace:       (TradeOrder) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var side:       OrderSide = .buy
    @State private var qty:        Int       = 1
    // Text fields edit strings; they're parsed into numbers only when the order is placed
    @State private var stopLoss:   String
    @State private var takeProfit: String

    init(stock: Stock, balance: Double, currentShares: Int,
         stopLossPct: Double, takeProfitPct: Double,
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
            header.padding(.bottom, 12)
            contextRow.padding(.bottom, 12)
            sidePicker.padding(.bottom, 12)
            quantity.padding(.bottom, 12)

            if side == .buy {
                HStack(spacing: 12) {
                    priceField(title: "Stop Loss",   icon: "shield.lefthalf.filled", tint: Theme.red,     text: $stopLoss)
                    priceField(title: "Take Profit", icon: "dollarsign.circle",      tint: Theme.emerald, text: $takeProfit)
                }
                .padding(.bottom, 12)
            }

            if !canAfford {
                Label("Insufficient balance for this order", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
            }

            placeButton
        }
        .padding(.horizontal, 20).padding(.top, 20)
    }

    // MARK: Sections

    private var header: some View {
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
            .accessibilityLabel("Close")
        }
    }

    private var contextRow: some View {
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
    }

    private var sidePicker: some View {
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
    }

    private var quantity: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SHARES").font(.system(size: 10)).tracking(1.5).foregroundStyle(Theme.mutedForeground)
            HStack {
                Button { qty = max(1, qty - 1) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.mutedForeground)
                        .frame(width: 36, height: 36).background(Theme.secondary).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel("Decrease shares")
                Text("\(qty)")
                    .font(.mono(18, weight: .heavy)).foregroundStyle(canAfford ? Theme.foreground : Theme.red)
                    .frame(maxWidth: .infinity)
                Button { qty = min(qty + 1, side == .buy ? maxBuyQty : sellableQty) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.mutedForeground)
                        .frame(width: 36, height: 36).background(Theme.secondary).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel("Increase shares")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.card).overlay(RoundedRectangle(cornerRadius: 12).stroke(canAfford ? Theme.border : Theme.red.opacity(0.5)))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if side == .buy {
                HStack(spacing: 6) {
                    quickChips([("25%", 0.25), ("50%", 0.50), ("Max", 1.0)], of: maxBuyQty, tint: Theme.primary)
                    Spacer()
                    Text("Total: $\(totalCost.money())")
                        .font(.mono(11)).foregroundStyle(canAfford ? Theme.mutedForeground : Theme.red)
                }
            } else {
                HStack(spacing: 6) {
                    quickChips([("¼", 0.25), ("½", 0.50), ("All", 1.0)], of: sellableQty, tint: Theme.red)
                    Spacer()
                    Text("Est. proceeds: $\((Double(qty) * stock.price).money())")
                        .font(.mono(11)).foregroundStyle(Theme.mutedForeground)
                }
            }
        }
    }

    private var placeButton: some View {
        Button {
            onPlace(TradeOrder(symbol: stock.symbol, name: stock.name, side: side,
                               qty: qty, entryPrice: stock.price,
                               stopLoss:   side == .buy ? Double(stopLoss)   : nil,
                               takeProfit: side == .buy ? Double(takeProfit) : nil))
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

    // MARK: Helpers

    private func quickChips(_ options: [(String, Double)], of maximum: Int, tint: Color) -> some View {
        ForEach(options, id: \.0) { label, fraction in
            let q = max(1, Int(Double(maximum) * fraction))
            Button { qty = q } label: {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(qty == q ? tint : .white.opacity(0.35))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(qty == q ? tint.opacity(0.15) : .white.opacity(0.04))
                    .overlay(Capsule().stroke(qty == q ? tint.opacity(0.5) : .white.opacity(0.08)))
                    .clipShape(Capsule())
            }
        }
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
                        .accessibilityLabel(title)
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
        guard let v = Double(value), stock.price > 0 else { return "—" }
        return ((v - stock.price) / stock.price * 100).signedPercent(1)
    }
}
