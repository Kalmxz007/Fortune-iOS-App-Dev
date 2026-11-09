//
//  Money.swift
//  Fortune
//
//  The ledger (cash, order prices, cost basis, realized P&L) is stored as Decimal
//  so repeated buys and sells never accumulate floating-point drift.
//  Market quotes stay Double; values convert only at the edges:
//  quote → Decimal when an order executes, Decimal → Double for display and charts.
//

import Foundation

nonisolated extension Decimal {
    /// Rounds to whole cents, half-up, like a brokerage statement.
    func roundedToCents() -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, 2, .plain)
        return result
    }

    /// A market price converted to an exact amount of dollars and cents.
    init(price: Double) {
        // Going through the shortest decimal string avoids binary artifacts like 33.329999999…
        self = (Decimal(string: "\(price)") ?? Decimal(price)).roundedToCents()
    }

    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
