//
//  AccountView.swift
//  Fortune
//
//  Account & settings: profile hero with level/XP, trading stats grid,
//  achievements grid, settings sections, and an iOS action-sheet sign-out.
//

import SwiftUI

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false
    @State private var confirmResetPortfolio = false
    @State private var showRiskOptions = false
    @State private var showStopLossOptions = false
    @State private var showPrivacyPolicy = false

    private var initials: String {
        let letters = model.userName.split(separator: " ").compactMap(\.first)
        return letters.isEmpty ? "ME" : String(letters.prefix(2)).uppercased()
    }

    private var earnedCount: Int { model.achievements.filter(\.earned).count }

    private var joinedLabel: String {
        let df = DateFormatter(); df.dateFormat = "MMM yyyy"
        return "Joined \(df.string(from: model.joinDate))"
    }

    private var portfolioGain: Double {
        let currentValue = model.balance + model.holdings.reduce(0) { $0 + $1.marketValue }
        return currentValue - model.startingCapital
    }

    private var myLeaderboardRank: Int? {
        model.leaderboard.first(where: { $0.isMe })?.rank
    }

    private var portfolioGainPct: Double {
        guard model.startingCapital > 0 else { return 0 }
        return portfolioGain / model.startingCapital * 100
    }

    private var portfolioGainFormatted: String {
        "\(portfolioGain.signedMoney()) (\(portfolioGainPct.signedPercent(1)))"
    }

    private var bestHolding: Holding? {
        model.holdings.max(by: { $0.pnl < $1.pnl })
    }

    private var stopLossLabel: String {
        "−\(Int((model.defaultStopLossPct * 100).rounded()))% from entry price"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                profileHero.padding(.horizontal, 16).padding(.bottom, 16)
                capitalCard.padding(.horizontal, 16).padding(.bottom, 20)
                statsGrid.padding(.horizontal, 16).padding(.bottom, 20)
                achievementsGrid.padding(.horizontal, 16).padding(.bottom, 20)

                tradingSection
                notificationsSection
                appSection

                actions.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 32)
            }
        }
        .background(Theme.background)
        .alert("Reset Mock Portfolio?", isPresented: $confirmResetPortfolio) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    model.resetPortfolio()
                }
            }
        } message: {
            Text("This will clear your portfolio, trades, P&L, and mock funds back to normal. Your personalizations and settings will stay saved.")
        }
        .alert("Sign Out of Fortune?", isPresented: $confirmSignOut) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    model.signOut()
                }
            }
        } message: {
            Text("You'll return to onboarding. Your current portfolio and progress will be cleared and a new account will be created.")
        }
        .alert("Choose Risk Level", isPresented: $showRiskOptions) {
            ForEach(RiskLevel.allCases, id: \.self) { level in
                Button(level.label) { model.updateRisk(level) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This updates your trading profile and risk-based suggestions.")
        }
        .alert("Choose Default Stop Loss", isPresented: $showStopLossOptions) {
            Button("2%") { model.updateDefaultStopLossPct(0.02) }
            Button("3%") { model.updateDefaultStopLossPct(0.03) }
            Button("5%") { model.updateDefaultStopLossPct(0.05) }
            Button("10%") { model.updateDefaultStopLossPct(0.10) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("New buy orders will prefill stop loss using this percentage below the entry price.")
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Account").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.foreground)
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
    }

    // MARK: Profile hero

    private var profileHero: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(RadialGradient(colors: [Theme.primary.opacity(0.12), .clear], center: .topTrailing, startRadius: 0, endRadius: 130))
                .frame(width: 130, height: 130).offset(x: 30, y: -30)

            HStack(spacing: 16) {
                Text(initials)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(LinearGradient(colors: [Theme.primary, Theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                    .background(LinearGradient(colors: [Theme.primary.opacity(0.25), Theme.accent.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.indigo.opacity(0.4), lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(model.userName).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.foreground)
                        Text("Lv.\(model.level)").font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Theme.indigo.opacity(0.2))
                            .foregroundStyle(Color(hex: 0xA5B4FC))
                            .overlay(Capsule().stroke(Theme.indigo.opacity(0.3)))
                            .clipShape(Capsule())
                    }
                    Text("\(model.archetype.icon) \(model.archetype.label) · \(joinedLabel)").font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
                    VStack(spacing: 5) {
                        HStack {
                            Text("\(model.xpInCurrentLevel.formatted()) XP").font(.mono(10)).foregroundStyle(.white.opacity(0.35))
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.4), value: model.xpInCurrentLevel)
                            Spacer()
                            Text("Lv.\(model.level + 1): \(1_000.formatted())").font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
                        }
                        GeometryReader { geo in
                            Capsule().fill(.white.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Theme.brandGradient)
                                        .frame(width: geo.size.width * model.xpProgress)
                                        .animation(.spring(response: 0.6), value: model.xpProgress)
                                }
                        }
                        .frame(height: 6)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .background(LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x0E0C2E)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.primary.opacity(0.15)))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: Capital

    private var capitalCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Portfolio Value").font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
                Text("$\(model.totalPortfolioValue.money())").font(.mono(24, weight: .bold)).foregroundStyle(Theme.foreground)
                Text("Cash $\(model.balance.money())").font(.mono(11)).foregroundStyle(Theme.mutedForeground)
                HStack(spacing: 6) {
                    Text(portfolioGainFormatted)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(portfolioGain >= 0 ? Theme.emerald : Theme.destructive)
                    Text("from $\(model.startingCapital.money(0))").font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
                }
                .padding(.top, 2)
            }
            Spacer()
            Image(systemName: "dollarsign").font(.system(size: 20)).foregroundStyle(Theme.indigo)
                .frame(width: 48, height: 48)
                .background(LinearGradient(colors: [Theme.primary.opacity(0.15), Theme.accent.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().stroke(Theme.indigo.opacity(0.3))).clipShape(Circle())
        }
        .padding(16)
        .background(Theme.card).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Stats grid

    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Trading Stats")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                let pnl = model.totalPnL
                statCard("Total P&L", pnl.signedMoney(), "All time", pnl >= 0 ? Theme.green : Theme.destructive)

                let wr = model.winRate
                let wrStr = model.closedTradeCount > 0 ? String(format: "%.1f%%", wr * 100) : "—"
                let wrSub = model.closedTradeCount > 0 ? "\(model.closedTradeCount) closed trades" : "No closed trades yet"
                statCard("Win Rate", wrStr, wrSub, Theme.primary)

                let bestStr = bestHolding.map { $0.pnl.signedMoney() } ?? "—"
                let bestSub = bestHolding?.symbol ?? "No positions"
                statCard("Best Position", bestStr, bestSub, Theme.accent)

                let rankStr = myLeaderboardRank.map { "#\($0)" } ?? "—"
                statCard("Practice League", rankStr, "Rank by % return", Color(hex: 0xF59E0B))
            }
        }
    }

    private func statCard(_ label: String, _ value: String, _ sub: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.mono(18, weight: .heavy)).foregroundStyle(color)
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.foreground)
            Text(sub).font(.system(size: 10)).foregroundStyle(Theme.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Theme.card).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Achievements

    private var achievementsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Achievements")
                Spacer()
                Text("\(earnedCount) / 6").font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(model.achievements) { a in
                    VStack(spacing: 4) {
                        Text(a.icon).font(.system(size: 24)).grayscale(a.earned ? 0 : 1)
                        Text(a.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.foreground)
                            .multilineTextAlignment(.center)
                        Text(a.detail).font(.system(size: 9)).foregroundStyle(Theme.mutedForeground)
                            .multilineTextAlignment(.center)
                        if a.earned {
                            Text("✓ Earned").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.emerald)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12).padding(.horizontal, 6)
                    .background(.white.opacity(a.earned ? 0.05 : 0.02))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(a.earned ? 0.1 : 0.05)))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(a.earned ? 1 : 0.45)
                }
            }
        }
    }

    // MARK: Settings sections

    private var tradingSection: some View {
        section("Trading") {
            ToggleRow(
                icon: "chart.line.uptrend.xyaxis",
                label: "Stock Alerts",
                detail: "Notify on big moves & stop-loss hits",
                isOn: Binding(
                    get: { model.stockAlertsEnabled },
                    set: { model.updateStockAlertsEnabled($0) }
                )
            )
            rowDivider
            ToggleRow(
                icon: "star",
                label: "Watchlist Sync",
                detail: "Sync starred stocks via iCloud",
                isOn: Binding(
                    get: { model.watchlistSyncEnabled },
                    set: { model.setWatchlistSyncEnabled($0) }
                )
            )
            rowDivider
            Button { showRiskOptions = true } label: {
                NavRow(icon: "waveform.path.ecg", label: "Risk Level", detail: model.risk.label)
            }
            .buttonStyle(.plain)
            rowDivider
            Button { showStopLossOptions = true } label: {
                NavRow(icon: "shield.lefthalf.filled", label: "Default Stop Loss", detail: stopLossLabel)
            }
            .buttonStyle(.plain)
        }
    }

    private var notificationsSection: some View {
        section("Notifications") {
            ToggleRow(
                icon: "bell",
                label: "Push Notifications",
                detail: "Alerts and market updates",
                isOn: Binding(
                    get: { model.notificationsEnabled },
                    set: { newValue in Task { await model.setNotificationsEnabled(newValue) } }
                )
            )
            rowDivider
            ToggleRow(
                icon: "newspaper",
                label: "Weekly Digest",
                detail: "Show market news on Portfolio",
                isOn: Binding(
                    get: { model.weeklyDigestEnabled },
                    set: { model.updateWeeklyDigestEnabled($0) }
                )
            )
            rowDivider
            ToggleRow(
                icon: "bolt",
                label: "XP Milestones",
                detail: "Notify when you level up",
                isOn: Binding(
                    get: { model.xpMilestonesEnabled },
                    set: { model.updateXPMilestonesEnabled($0) }
                )
            )
        }
    }

    private var appSection: some View {
        section("App") {
            SettingRow(icon: "internaldrive", label: "Data Storage", detail: "Progress saved locally on device") {
                Text("Saved").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.emerald)
            }
            rowDivider
            NavRow(icon: "trophy", label: "Practice League", detail: "Simulated opponents · Rank \(myLeaderboardRank.map { "#\($0)" } ?? "—")")
            rowDivider
            Button { showPrivacyPolicy = true } label: {
                NavRow(icon: "lock", label: "Privacy", detail: "Manage your data")
            }
            .buttonStyle(.plain)
            rowDivider
            NavRow(icon: "info.circle", label: "About Fortune", detail: "v2.0 · Stock Simulator")
            rowDivider
            Button { model.showTutorial = true } label: {
                NavRow(icon: "questionmark.circle", label: "How to Use Fortune", detail: "Step-by-step tutorial")
            }
            .buttonStyle(.plain)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title)
            VStack(spacing: 0) { content() }
                .background(Theme.card).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
    }

    private var rowDivider: some View { Rectangle().fill(Theme.border).frame(height: 1) }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 12) {
            Button { confirmResetPortfolio = true } label: {
                Text("Reset Mock Portfolio").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.destructive.opacity(0.3)))
            }
            Button { confirmSignOut = true } label: {
                Label("Sign Out", systemImage: "person").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.10)))
            }
            Text("Fortune v2.0 · No real money involved").font(.system(size: 11)).foregroundStyle(Theme.mutedForeground)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Rows

private struct IconBox: View {
    let icon: String
    var body: some View {
        Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Theme.primary)
            .frame(width: 32, height: 32).background(Theme.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct SettingRow<Trailing: View>: View {
    let icon: String
    let label: String
    let detail: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            IconBox(icon: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.foreground)
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }
}

private struct ToggleRow: View {
    let icon: String
    let label: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(icon: icon, label: label, detail: detail) {
            Toggle("", isOn: $isOn).labelsHidden().tint(Theme.primary)
        }
    }
}

private struct NavRow: View {
    let icon: String
    let label: String
    let detail: String

    var body: some View {
        SettingRow(icon: icon, label: label, detail: detail) {
            Image(systemName: "chevron.right").font(.system(size: 14)).foregroundStyle(Theme.mutedForeground)
        }
    }
}


// MARK: - Privacy Policy

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Section {
        let title: String
        let body: String
    }

    private let sections: [Section] = [
        .init(title: "Overview",
              body: "Fortune is a stock market simulator for educational and entertainment purposes only. No real money is ever involved, and no real trades are placed. This policy explains what data the app handles and how."),
        .init(title: "Data We Store",
              body: "Your profile, portfolio, trade history, XP, achievements, and app preferences are saved locally on your device only. Fortune does not maintain user accounts on a server, and this data never leaves your device unless you back it up through iCloud yourself."),
        .init(title: "Market Data",
              body: "Live prices, quotes, company fundamentals, and news are fetched from third-party providers (Finnhub and Yahoo Finance) to power charts and stock information. The app only requests public market data — it does not share any of your personal or portfolio information with these providers."),
        .init(title: "Analytics & Tracking",
              body: "Fortune does not include advertising, and does not sell or share your data with advertisers. The app does not track you across other apps or websites."),
        .init(title: "Notifications",
              body: "If you enable notifications, they are used only to deliver in-app alerts such as price movements, market updates, and XP milestones. You can turn these off at any time in Settings."),
        .init(title: "Your Control",
              body: "Because all of your data lives on your device, you can erase it at any time by resetting your mock portfolio, signing out, or deleting the app. Signing out generates a fresh account and clears your current progress."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 48, height: 48)
                            .background(LinearGradient(colors: [Theme.primary.opacity(0.18), Theme.accent.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.indigo.opacity(0.3)))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Privacy Policy").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.foreground)
                            Text("Last updated July 2026").font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
                        }
                    }
                    .padding(.top, 8)

                    ForEach(sections, id: \.title) { s in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(s.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.foreground)
                            Text(s.body).font(.system(size: 13)).foregroundStyle(Theme.mutedForeground)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Theme.card).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Text("Fortune · No real money involved").font(.system(size: 11)).foregroundStyle(Theme.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4).padding(.bottom, 24)
                }
                .padding(.horizontal, 16)
            }
            .background(Theme.background)
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.primary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    AccountView().environment(AppModel())
}
