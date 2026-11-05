//
//  LeaderboardView.swift
//  Fortune
//

import SwiftUI

struct LeaderboardView: View {
    @Environment(AppModel.self) private var model

    enum Timeframe: String, CaseIterable {
        case allTime = "All Time"
        case thisWeek = "This Week"
    }

    @State private var timeframe: Timeframe = .thisWeek

    private let cols: [CGFloat] = [28, 0, 92, 60, 46]

    /// Time remaining until local midnight, when daily challenges reset.
    private var resetCountdown: String {
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        let mins = max(0, Int(midnight.timeIntervalSince(now) / 60))
        return "Resets in \(mins / 60)h \(mins % 60)m"
    }

    var body: some View {
        ZStack {
            ImmersiveBackground()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("🌐").font(.system(size: 18))
                    Text("Global Leaderboard")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                    Spacer()
                }
                .padding(.top, 18).padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        dailyChallenges.padding(.bottom, 16)
                        timeframeToggle.padding(.bottom, 20)
                        columnHeader.padding(.bottom, 6)
                        Rectangle().fill(.white.opacity(0.07)).frame(height: 1).padding(.bottom, 6)
                        VStack(spacing: 4) {
                            ForEach(timeframe == .allTime ? model.leaderboard : model.weeklyLeaderboard) { entry in
                                row(entry)
                            }
                        }
                    }
                }

                GradientDivider().padding(.vertical, 12)
                FortuneFooter().padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
        }
        .task {
            // Re-evaluate bot PnLs every 60 seconds so values change while the view is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                model.leaderboardRefreshTick += 1
            }
        }
    }

    // MARK: Daily challenges

    private var dailyChallenges: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DAILY CHALLENGES").font(.system(size: 11, weight: .bold)).tracking(0.6)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text(resetCountdown).font(.mono(10)).foregroundStyle(Color(hex: 0xF59E0B))
            }
            ForEach(model.dailyChallenges) { c in
                HStack(spacing: 12) {
                    Text(c.icon).font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(c.title).font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(c.done ? Theme.green : .white.opacity(0.85))
                            Spacer()
                            Text("+\(c.xp) XP").font(.mono(10, weight: .bold)).foregroundStyle(Color(hex: 0xF59E0B))
                        }
                        HStack(spacing: 8) {
                            GeometryReader { geo in
                                Capsule().fill(.white.opacity(0.08))
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(c.done
                                                  ? AnyShapeStyle(Theme.green)
                                                  : AnyShapeStyle(LinearGradient(colors: [Theme.primary, Theme.indigo], startPoint: .leading, endPoint: .trailing)))
                                            .frame(width: geo.size.width * min(Double(c.progress) / Double(c.total), 1))
                                    }
                            }
                            .frame(height: 4)
                            Text("\(c.progress)/\(c.total)").font(.mono(9)).foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    if c.done { Text("✓").font(.system(size: 14)) }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(c.done ? Theme.green.opacity(0.08) : .white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(c.done ? Theme.green.opacity(0.25) : .white.opacity(0.07)))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var timeframeToggle: some View {
        HStack(spacing: 4) {
            ForEach(Timeframe.allCases, id: \.self) { tf in
                let on = timeframe == tf
                Button { timeframe = tf } label: {
                    Text(tf.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(on ? Color(hex: 0x0A0D1A) : .white.opacity(0.45))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background { if on { RoundedRectangle(cornerRadius: 10).fill(.white) } }
                }
            }
        }
        .padding(4)
        .background(.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("RANK").frame(width: cols[0])
            Text("TRADER").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8)
            Text("PNL").frame(width: cols[2], alignment: .trailing)
            Text("WIN RATE").frame(width: cols[3], alignment: .trailing)
            Text("TRADES").frame(width: cols[4], alignment: .trailing)
        }
        .font(.mono(9, weight: .semibold)).tracking(0.6)
        .foregroundStyle(.white.opacity(0.28))
    }

    private func row(_ e: LeaderboardEntry) -> some View {
        HStack(spacing: 0) {
            ZStack {
                Circle().fill(rankColor(e.rank))
                    .overlay(Circle().stroke(e.rank > 3 ? .white.opacity(0.10) : .clear))
                    .frame(width: 20, height: 20)
                Text("\(e.rank)")
                    .font(.mono(9, weight: .bold))
                    .foregroundStyle(e.rank <= 3 ? .white : .white.opacity(0.4))
            }
            .frame(width: cols[0])

            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(RadialGradient(
                        colors: [e.color.opacity(0.33), e.color.opacity(0.13)],
                        center: UnitPoint(x: 0.35, y: 0.35), startRadius: 0, endRadius: 16))
                        .overlay(Circle().stroke(e.color.opacity(0.33)))
                        .frame(width: 28, height: 28)
                    Text(e.symbol).font(.system(size: 11)).foregroundStyle(e.color)
                }
                Text(e.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(e.isMe ? 0.95 : 0.80))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8)

            Text("\(e.pnl >= 0 ? "+" : "-")$\(abs(e.pnl).money())")
                .font(.mono(12, weight: .semibold)).foregroundStyle(e.pnl >= 0 ? Theme.green : Theme.red)
                .frame(width: cols[2], alignment: .trailing)
            Text(e.winRate > 0 ? "\(e.winRate.money(1))%" : "—")
                .font(.mono(12)).foregroundStyle(.white.opacity(0.70))
                .frame(width: cols[3], alignment: .trailing)
            Text("\(e.trades)")
                .font(.mono(12)).foregroundStyle(.white.opacity(0.50))
                .frame(width: cols[4], alignment: .trailing)
        }
        .padding(.vertical, 10).padding(.horizontal, 6)
        .background {
            if e.isMe {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Theme.indigo.opacity(0.18), Theme.accent.opacity(0.10)],
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.indigo.opacity(0.35)))
                    .shadow(color: Theme.indigo.opacity(0.20), radius: 10)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.025))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.04)))
            }
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: Color(hex: 0xF59E0B)
        case 2: Color(hex: 0x9CA3AF)
        case 3: Color(hex: 0xF97316)
        default: Color.white.opacity(0.06)
        }
    }
}

#Preview {
    LeaderboardView().environment(AppModel())
}
