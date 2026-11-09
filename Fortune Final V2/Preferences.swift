//
//  Preferences.swift
//  Fortune
//
//  Typed onboarding choices and trading preferences. Raw values match the
//  strings older versions saved, so existing saves still load.
//

import Foundation

enum ExperienceLevel: String, Codable, CaseIterable {
    case beginner, intermediate, pro
}

enum TradingGoal: String, Codable, CaseIterable {
    case learn, grow, beat, fun
}

enum TradingFrequency: String, Codable, CaseIterable {
    case active, swing, casual

    /// Chart timeframe that best fits how often the user trades.
    var defaultTimeframe: Timeframe {
        switch self {
        case .active: .day
        case .swing:  .week
        case .casual: .month
        }
    }
}

enum RiskLevel: String, Codable, CaseIterable {
    case conservative, balanced, aggressive

    var label: String { rawValue.capitalized }

    var defaultStopLossPct: Double {
        switch self {
        case .conservative: 0.02
        case .balanced:     0.03
        case .aggressive:   0.05
        }
    }

    var defaultTakeProfitPct: Double {
        switch self {
        case .conservative: 0.04
        case .balanced:     0.06
        case .aggressive:   0.10
        }
    }
}

enum StartingCapital: String, CaseIterable {
    case oneThousand = "1k", tenThousand = "10k", hundredThousand = "100k", oneMillion = "1m"

    var amount: Double {
        switch self {
        case .oneThousand:     1_000
        case .tenThousand:     10_000
        case .hundredThousand: 100_000
        case .oneMillion:      1_000_000
        }
    }
}

/// Chart range. Nonisolated because MarketService (an actor) maps it to API parameters.
nonisolated enum Timeframe: String, Codable, CaseIterable, Hashable {
    case day = "1D", week = "1W", month = "1M", threeMonths = "3M"

    var label: String { rawValue }
}

/// Trader persona shown on the profile, derived from onboarding choices.
struct Archetype {
    let label: String
    let icon:  String

    init(experience: ExperienceLevel?, risk: RiskLevel?, frequency: TradingFrequency?) {
        switch (experience, risk, frequency) {
        case (.pro, .aggressive, _):      (label, icon) = ("Power Trader",      "⚡")
        case (.pro, .balanced, _):        (label, icon) = ("Precision Trader",  "🎯")
        case (.pro, _, _):                (label, icon) = ("Strategic Pro",      "💎")
        case (.intermediate, _, .active): (label, icon) = ("Swing Trader",      "📈")
        case (.intermediate, _, _):       (label, icon) = ("Strategic Investor", "🧠")
        case (_, .aggressive, _):         (label, icon) = ("Bold Explorer",      "🚀")
        case (_, _, .active):             (label, icon) = ("Eager Learner",      "⚡")
        default:                          (label, icon) = ("Rising Trader",      "🌟")
        }
    }
}
