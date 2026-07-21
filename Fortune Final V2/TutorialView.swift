//
//  TutorialView.swift
//  Fortune
//
//  Step-by-step walkthrough of every app feature.
//

import SwiftUI

struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0

    private let steps: [TutorialStep] = [
        .init(
            icon: "chart.line.uptrend.xyaxis",
            iconColor: Color(hex: 0xB06AFF),
            title: "Welcome to Fortune",
            body: "Fortune is a stock market simulator where you trade real companies using mock capital — no real money, no real risk. Everything you do here mirrors how a real brokerage works.",
            tip: "Your trades are saved locally, so your progress is always there when you come back."
        ),
        .init(
            icon: "dollarsign.circle.fill",
            iconColor: Color(hex: 0x4ADE80),
            title: "Your Mock Capital",
            body: "You start with the capital amount you chose during setup. This is your total buying power. Spend it wisely across positions to grow your portfolio.",
            tip: "Your cash balance is shown in the top-right header bar at all times, so you always know what you have available."
        ),
        .init(
            icon: "chart.line.uptrend.xyaxis",
            iconColor: Color(hex: 0x38D4FF),
            title: "The Trade Tab",
            body: "This is your main hub. Browse 20+ live stocks, filter by sector (Tech, Finance, EV, Crypto, and more), sort by top gainers or losers, and search by name or ticker.",
            tip: "Tap the ⓘ icon on any stock row to see detailed stats — market cap, P/E ratio, 52-week range, and analyst rating — before committing to a trade."
        ),
        .init(
            icon: "waveform.path.ecg",
            iconColor: Color(hex: 0xB06AFF),
            title: "How to Buy a Stock",
            body: "1. Tap any stock row to open the order sheet.\n2. Choose BUY or SELL at the top.\n3. Set the number of shares using + / − or the quick-fill chips (25%, 50%, Max).\n4. Review your Stop Loss and Take Profit prices.\n5. Tap Place BUY to execute instantly.",
            tip: "Your balance is deducted immediately when you buy. It is returned (with gains or losses) when you sell."
        ),
        .init(
            icon: "chart.xyaxis.line",
            iconColor: Color(hex: 0x38D4FF),
            title: "Reading the Chart",
            body: "The smooth line chart at the top of the Trade tab tracks price movement for the selected stock. Green means the stock is up today; red means it is down.\n\nSwitch timeframes using the buttons below the price — 1D, 1W, 1M, or 3M.",
            tip: "The chart updates live via WebSocket. The line extends in real time as new prices arrive from the market."
        ),
        .init(
            icon: "shield.lefthalf.filled",
            iconColor: Color(hex: 0xEF4444),
            title: "Stop Loss & Take Profit",
            body: "These are automatic exit triggers set when you buy:\n\n• Stop Loss — sells your position if the price falls to a set level, limiting your downside.\n• Take Profit — sells automatically when the price hits your target gain.\n\nBoth are pre-filled based on your risk profile from onboarding.",
            tip: "You can edit the exact dollar values in the order sheet before placing. Leave them blank to disable auto-exit."
        ),
        .init(
            icon: "chart.bar.fill",
            iconColor: Color(hex: 0x4ADE80),
            title: "The Portfolio Tab",
            body: "Track everything here:\n\n• Combined P&L at a glance with a live chart\n• Open positions with unrealized gains and losses\n• Allocation donut showing how your capital is spread\n• Closed trade journal with entry, exit, and reason\n• Market news (if Weekly Digest is on)",
            tip: "Tap any open position to open the partial-sell sheet — you can sell a fraction of your shares rather than the whole position."
        ),
        .init(
            icon: "trophy.fill",
            iconColor: Color(hex: 0xF59E0B),
            title: "The Leaderboard",
            body: "See where you rank against other traders. Your position is calculated from your total P&L — realized and unrealized combined.\n\nClimb the board by making profitable trades, increasing your win rate, and growing your portfolio.",
            tip: "The leaderboard also feeds into Achievements. Reach #1 to unlock the Top Gainer badge."
        ),
        .init(
            icon: "person.crop.circle.badge.checkmark",
            iconColor: Color(hex: 0xB06AFF),
            title: "Account & Achievements",
            body: "Your Account tab shows your level, XP, trading stats, and achievements. Earn XP for every trade and win. Level up by closing profitable positions.\n\nUse the settings here to adjust your risk level, default stop loss, and notification preferences.",
            tip: "Hit Reset Mock Portfolio at any time to wipe your trades and start fresh with your original capital — your settings and name are kept."
        ),
        .init(
            icon: "flag.checkered",
            iconColor: Color(hex: 0x4ADE80),
            title: "You're Ready to Trade!",
            body: "You now know everything Fortune has to offer. Open the Trade tab, pick a stock you believe in, and place your first simulated trade.\n\nRemember — no real money is involved. This is your practice ground to learn, experiment, and build confidence.",
            tip: "You can reopen this tutorial anytime from Account → How to Use Fortune."
        ),
    ]

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: 0x060912), Color(hex: 0x0A0E1A)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Text("Tutorial")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Button("Skip") { dismiss() }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)

                // Progress dots
                HStack(spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Capsule()
                            .fill(i == step ? steps[step].iconColor : .white.opacity(0.15))
                            .frame(width: i == step ? 20 : 6, height: 6)
                            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: step)
                    }
                }
                .padding(.bottom, 32)

                // Step content
                TabView(selection: $step) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, s in
                        stepCard(s)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)

                // Navigation buttons
                HStack(spacing: 12) {
                    if step > 0 {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { step -= 1 }
                        } label: {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 52, height: 52)
                                .background(.white.opacity(0.06))
                                .overlay(Circle().stroke(.white.opacity(0.1)))
                                .clipShape(Circle())
                        }
                        .transition(.scale.combined(with: .opacity))
                    }

                    Button {
                        if step < steps.count - 1 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { step += 1 }
                        } else {
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(step < steps.count - 1 ? "Next" : "Start Trading")
                                .font(.system(size: 15, weight: .bold))
                            Image(systemName: step < steps.count - 1 ? "arrow.right" : "flag.checkered")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            LinearGradient(
                                colors: [steps[step].iconColor, steps[step].iconColor.opacity(0.7)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .animation(.spring(response: 0.3), value: step)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
    }

    private func stepCard(_ s: TutorialStep) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Icon
                ZStack {
                    Circle()
                        .fill(s.iconColor.opacity(0.12))
                        .frame(width: 96, height: 96)
                    Circle()
                        .stroke(s.iconColor.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 96, height: 96)
                    Image(systemName: s.icon)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(s.iconColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 28)

                // Title
                Text(s.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 14)

                // Body
                Text(s.body)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineSpacing(5)
                    .padding(.bottom, 24)

                // Tip box
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: 0xF59E0B))
                        .padding(.top, 1)
                    Text(s.tip)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineSpacing(4)
                }
                .padding(14)
                .background(Color(hex: 0xF59E0B).opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xF59E0B).opacity(0.2)))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Step model

private struct TutorialStep {
    let icon:      String
    let iconColor: Color
    let title:     String
    let body:      String
    let tip:       String
}

#Preview {
    TutorialView()
}
