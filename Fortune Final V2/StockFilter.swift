//
//  StockFilter.swift
//  Fortune
//
//  Search / sector / sort logic for the Trade screen, kept free of SwiftUI so it can be unit tested.
//

import Foundation

struct StockFilter: Equatable {
    enum Sort: String, CaseIterable {
        case standard, gainers, losers, price

        var label: String {
            switch self {
            case .standard: "Default"
            case .gainers:  "↑ Gainers"
            case .losers:   "↓ Losers"
            case .price:    "Price"
            }
        }
    }

    /// Pseudo-sector chip that shows only starred stocks.
    static let starredChip = "★ Starred"
    static let allChip     = "All"

    /// Chips in display order: All, Starred, then each sector.
    static var chips: [String] {
        [allChip, starredChip] + MarketService.sectors.filter { $0 != allChip }
    }

    var search = ""
    var sector = StockFilter.allChip
    var sort: Sort = .standard

    var isShowingStarred: Bool { sector == Self.starredChip }

    func apply(to stocks: [Stock], isStarred: (String) -> Bool) -> [Stock] {
        let matches = stocks.filter { stock in
            let sectorMatch: Bool
            switch sector {
            case Self.allChip:     sectorMatch = true
            case Self.starredChip: sectorMatch = isStarred(stock.symbol)
            default:               sectorMatch = stock.sector == sector
            }
            let searchMatch = search.isEmpty
                || stock.symbol.localizedCaseInsensitiveContains(search)
                || stock.name.localizedCaseInsensitiveContains(search)
            return sectorMatch && searchMatch
        }
        switch sort {
        case .standard: return matches
        case .gainers:  return matches.sorted { $0.pct > $1.pct }
        case .losers:   return matches.sorted { $0.pct < $1.pct }
        case .price:    return matches.sorted { $0.price > $1.price }
        }
    }

    /// Top `limit` stocks that are actually up (gainers) or down (losers) today.
    static func movers(in stocks: [Stock], gainers: Bool, limit: Int = 4) -> [Stock] {
        let moving = stocks.filter { gainers ? $0.pct > 0 : $0.pct < 0 }
        let sorted = moving.sorted { gainers ? $0.pct > $1.pct : $0.pct < $1.pct }
        return Array(sorted.prefix(limit))
    }
}
