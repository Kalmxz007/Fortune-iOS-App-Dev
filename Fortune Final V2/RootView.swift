//
//  RootView.swift
//  Fortune
//
//  App entry point: switches between onboarding and the main tabbed shell.
//  This is the first screen that appears when opening the app.
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
    }
}

// MARK: - Main shell

struct MainShell: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if model.activeTab != .account {
                HeaderBar()
            }

            Group {
                switch model.activeTab {
                case .trade:   TradeView()
                case .predict: PredictionsView()
                case .leaders: LeaderboardView()
                case .pnl:     PnLView()
                case .account: AccountView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(model.activeTab)
            .transition(.opacity)

            if model.activeTab != .account {
                FortuneTabBar()
            }
        }
        .background(Theme.background)
    }
}

// MARK: - Header

private struct HeaderBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                LogoView(size: 28)
                Text("Fortune")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.brandGradient)
            }
            Spacer()
            HStack(spacing: 6) {
                PulsingDot()
                Text("$\(model.balance.money(0))")
                    .font(.mono(12, weight: .medium))
                    .foregroundStyle(Theme.emerald)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.emerald.opacity(0.10))
            .overlay(Capsule().stroke(Theme.emerald.opacity(0.20), lineWidth: 1))
            .clipShape(Capsule())
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
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: active ? .semibold : .regular))
                            .offset(y: active ? -1 : 0)
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
