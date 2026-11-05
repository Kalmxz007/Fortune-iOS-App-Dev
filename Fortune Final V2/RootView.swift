//
//  RootView.swift
//  Fortune
//
//  App entry point: switches between onboarding and the main tabbed shell.
//

import SwiftUI

struct RootView: View {
    @State private var model = AppModel()

    var body: some View {
        ZStack {
            if model.onboarded {
                MainShell()
            } else {
                OnboardingView { data in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        model.completeOnboarding(data)
                    }
                }
            }
        }
        .environment(model)
        .preferredColorScheme(.dark)
        .tint(Theme.primary)
        .task { await model.loadMarketData() }
        .task { await model.syncNotificationAuthorization() }
    }
}

// MARK: - Main shell

struct MainShell: View {
    @Environment(AppModel.self) private var model
    @State private var confirmVisible = false
    @State private var alertVisible   = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HeaderBar()

                Group {
                    switch model.activeTab {
                    case .trade:   TradeView()
                    case .leaders: LeaderboardView()
                    case .pnl:     PnLView()
                    case .account: AccountView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(model.activeTab)
                .transition(.opacity)

                FortuneTabBar()
            }

            // First Blood celebration: confetti + banner on first trade of the day
            if model.showFirstBloodCelebration {
                ConfettiView()
                    .zIndex(100)
                FirstBloodBanner { model.showFirstBloodCelebration = false }
                    .zIndex(101)
            }

            // Global SL/TP + price alert toast — shown on every tab, not just Portfolio
            if alertVisible, let msg = model.lastAlert {
                VStack {
                    Text(msg)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .background(msg.contains("Stop Loss") ? Theme.red.opacity(0.7) : Theme.emerald.opacity(0.7))
                        .clipShape(Capsule())
                        .shadow(radius: 8)
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(98)
            }

            // Global trade confirmation toast — sits above the tab bar
            if confirmVisible, let msg = model.tradeConfirmation {
                let isWin = msg.contains("+")
                HStack(spacing: 8) {
                    Image(systemName: msg.starts(with: "Bought") ? "arrow.up.circle.fill" : (isWin ? "checkmark.circle.fill" : "minus.circle.fill"))
                        .foregroundStyle(msg.starts(with: "Bought") ? Theme.primary : (isWin ? Theme.emerald : Theme.red))
                    Text(msg)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                }
                .padding(.horizontal, 18).padding(.vertical, 11)
                .background(.ultraThinMaterial)
                .background(Color(hex: 0x111827).opacity(0.7))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                .padding(.bottom, 80)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(99)
            }
        }
        .background(Theme.background)
        .sheet(isPresented: Binding(get: { model.showTutorial },
                                    set: { model.showTutorial = $0 })) {
            TutorialView()
        }
        // Keep live prices running across ALL tabs, not just Trade
        .task { await model.startLivePriceStream() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await model.refreshPrices()
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
        .onChange(of: model.tradeConfirmation) { _, new in
            guard new != nil else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { confirmVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                withAnimation(.easeOut(duration: 0.3)) { confirmVisible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    model.tradeConfirmation = nil
                }
            }
        }
    }
}

// MARK: - Header bar

private struct HeaderBar: View {
    @Environment(AppModel.self) private var model

    private var totalValue: Double {
        model.balance + model.holdings.reduce(0) { $0 + $1.marketValue }
    }
    private var totalChange: Double { totalValue - model.startingCapital }

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                LogoView(size: 28)
                Text("Fortune")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.brandGradient)
            }
            Spacer()

            // Portfolio value pill — updates live as prices move
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    model.activeTab = .pnl
                }
            } label: {
                HStack(spacing: 6) {
                    PulsingDot()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("$\(totalValue.money(0))")
                            .font(.mono(13, weight: .semibold))
                            .foregroundStyle(Theme.emerald)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.4), value: totalValue)
                        if !model.holdings.isEmpty {
                            Text("\(totalChange >= 0 ? "+" : "")\(totalChange.money(0))")
                                .font(.mono(9))
                                .foregroundStyle(totalChange >= 0 ? Theme.emerald.opacity(0.7) : Theme.red.opacity(0.7))
                                .contentTransition(.numericText(countsDown: totalChange < 0))
                                .animation(.spring(response: 0.4), value: totalChange)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.emerald.opacity(0.10))
                .overlay(Capsule().stroke(Theme.emerald.opacity(0.20), lineWidth: 1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }
}

// MARK: - Tab bar

private struct FortuneTabBar: View {
    @Environment(AppModel.self) private var model
    @Namespace private var dot

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.barTabs, id: \.self) { tab in
                let active = model.activeTab == tab
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        model.activeTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 18, weight: active ? .semibold : .regular))
                                .offset(y: active ? -1 : 0)

                            // Badge: open position count on Portfolio tab
                            if tab == .pnl && !model.holdings.isEmpty {
                                Text("\(model.holdings.count)")
                                    .font(.system(size: 8, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 14, minHeight: 14)
                                    .background(Theme.primary)
                                    .clipShape(Capsule())
                                    .offset(x: 8, y: -6)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        Text(tab.label)
                            .font(.system(size: 10, weight: .medium))
                        ZStack {
                            if active {
                                Circle()
                                    .fill(Theme.brandGradient)
                                    .frame(width: 4, height: 4)
                                    .matchedGeometryEffect(id: "dot", in: dot)
                            } else {
                                Circle().fill(.clear).frame(width: 4, height: 4)
                            }
                        }
                    }
                    .foregroundStyle(active ? Theme.primary : Theme.mutedForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .animation(.spring(response: 0.3), value: model.holdings.count)
            }
        }
        .background(Theme.card.opacity(0.85))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }
}

#Preview {
    RootView()
}
