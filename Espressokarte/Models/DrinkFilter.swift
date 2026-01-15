//
//  DrinkFilter.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 13.01.26.
//

import Combine
import Foundation
import SwiftUI

/// Price range statistics for a drink type
struct DrinkPriceStats {
    let minPrice: Double
    let maxPrice: Double
    let q1: Double  // 25th percentile
    let median: Double  // 50th percentile
    let q3: Double  // 75th percentile

    /// Get the price category (0-3) based on quartiles
    func category(for price: Double) -> Int {
        if price < q1 { return 0 }       // Cheap
        if price < median { return 1 }   // Medium
        if price < q3 { return 2 }       // Expensive
        return 3                          // Very expensive
    }
}

/// Manages the user's selected drink type filter
@MainActor
final class DrinkFilterManager: ObservableObject {
    static let shared = DrinkFilterManager()

    /// The currently selected drink name to display on the map
    @AppStorage("selectedDrinkFilter") var selectedDrink: String = "Espresso"

    /// All available drink types found across all cafes
    @Published private(set) var availableDrinks: [String] = ["Espresso"]

    /// Price statistics per drink type
    @Published private(set) var drinkPriceStats: [String: DrinkPriceStats] = [:]

    private init() {}

    /// Updates available drinks and price stats from the current cafe data
    func updateAvailableDrinks(from cafes: [Cafe]) {
        var drinkSet = Set<String>()
        var pricesByDrink: [String: [Double]] = [:]

        for cafe in cafes {
            for record in cafe.priceHistory {
                for drink in record.drinks {
                    drinkSet.insert(drink.name)
                    pricesByDrink[drink.name, default: []].append(drink.price)
                }
            }
        }

        // Sort alphabetically but keep Espresso first
        var sorted = drinkSet.sorted()
        if let espressoIndex = sorted.firstIndex(of: "Espresso") {
            sorted.remove(at: espressoIndex)
            sorted.insert("Espresso", at: 0)
        }

        availableDrinks = sorted.isEmpty ? ["Espresso"] : sorted

        // Calculate price stats for each drink
        var stats: [String: DrinkPriceStats] = [:]
        for (drinkName, prices) in pricesByDrink {
            if let drinkStats = calculateStats(for: prices) {
                stats[drinkName] = drinkStats
            }
        }
        drinkPriceStats = stats

        // Reset to Espresso if selected drink is no longer available
        if !availableDrinks.contains(selectedDrink) {
            selectedDrink = "Espresso"
        }
    }

    /// Calculate quartile statistics for a set of prices
    private func calculateStats(for prices: [Double]) -> DrinkPriceStats? {
        guard !prices.isEmpty else { return nil }

        let sorted = prices.sorted()
        let count = sorted.count

        let minPrice = sorted.first!
        let maxPrice = sorted.last!

        // Need at least 4 distinct values for meaningful quartiles
        // If all values are identical or too few, return nil to use fallback ranges
        guard count >= 4 && minPrice < maxPrice else { return nil }

        let q1Index = count / 4
        let medianIndex = count / 2
        let q3Index = (count * 3) / 4

        let q1 = sorted[q1Index]
        let median = sorted[medianIndex]
        let q3 = sorted[q3Index]

        // If quartiles are all equal, return nil to use fallback ranges
        guard q1 < q3 else { return nil }

        return DrinkPriceStats(minPrice: minPrice, maxPrice: maxPrice, q1: q1, median: median, q3: q3)
    }

    /// Get price stats for the currently selected drink
    var currentDrinkStats: DrinkPriceStats? {
        drinkPriceStats[selectedDrink]
    }
}

// MARK: - Cafe Extension for filtered prices

extension Cafe {
    /// Gets the current price for a specific drink type
    func price(for drinkName: String) -> Double? {
        guard let latestRecord = latestPriceRecord else { return nil }
        
        // Exact match first
        if let drink = latestRecord.drinks.first(where: { $0.name.lowercased() == drinkName.lowercased() }) {
            return drink.price
        }
        
        // Partial match
        if let drink = latestRecord.drinks.first(where: { $0.name.lowercased().contains(drinkName.lowercased()) }) {
            return drink.price
        }
        
        return nil
    }
    
    /// Formatted price for a specific drink
    func formattedPrice(for drinkName: String) -> String? {
        guard let price = price(for: drinkName) else { return nil }
        return String(format: "€%.2f", price)
    }
}
