//
//  PredictionsView.swift
//  Fortune
//
// Will Delete soon Since it is no longer being used.
//
//  Remove `.predict` from AppTab.barTabs to hide it.
//

import SwiftUI

struct PredictionsView: View {
    @State private var bets: [Int: PlacedBet] = Dictionary(
        uniqueKeysWithValues: MockData.predictions.compactMap { p in
            p.myBet.map { (p.id, $0) }
        }
    )

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "target").font(.system(size: 14)).foregroundStyle(Theme.accent)
                        SectionLabel(text: "Prediction Markets")
                    }
                    Text("Trade on real-world events with mock capital. No money at risk.")
                        .font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
                }
                .padding(.top, 8)

                ForEach(MockData.predictions) { prediction in
                    card(prediction)
                }
            }
            .padding(16)
        }
        .background(Theme.background)
    }

    private func card(_ p: Prediction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(p.question)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Vol").font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
                    Text(p.volume).font(.mono(12)).foregroundStyle(Theme.foreground)
                }
            }

            // Probability bar
            VStack(spacing: 4) {
                HStack {
                    Text("YES \(p.yesOdds)%").font(.mono(11)).foregroundStyle(Theme.emerald)
                    Spacer()
                    Text("NO \(p.noOdds)%").font(.mono(11)).foregroundStyle(Theme.red)
                }
                GeometryReader { geo in
                    Capsule().fill(Theme.secondary)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(LinearGradient(colors: [Color(hex: 0x10B981), Theme.emerald],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * Double(p.yesOdds) / 100)
                        }
                }
                .frame(height: 8)
            }

            // Action
            if let bet = bets[p.id] {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill").font(.system(size: 12)).foregroundStyle(Theme.primary)
                    HStack(spacing: 4) {
                        Text("Bet \(bet.side)").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.primary)
                        Text("· $\(bet.amount)").font(.mono(12)).foregroundStyle(Theme.primary)
                        Text("→").font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
                        Text("$\(bet.potential)").font(.mono(12)).foregroundStyle(Theme.accent)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.primary.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.primary.opacity(0.20)))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                HStack(spacing: 8) {
                    betButton("YES", odds: p.yesOdds, tint: Theme.emerald, prediction: p)
                    betButton("NO", odds: p.noOdds, tint: Theme.red, prediction: p)
                }
            }

            Text("Closes \(p.closes)").font(.system(size: 11)).foregroundStyle(Theme.mutedForeground)
        }
        .padding(16)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func betButton(_ label: String, odds: Int, tint: Color, prediction: Prediction) -> some View {
        Button {
            let potential = Int((100.0 * 100.0 / Double(odds)).rounded())
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                bets[prediction.id] = PlacedBet(side: label, amount: 100, potential: potential)
            }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.3)))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

#Preview {
    PredictionsView()
}
