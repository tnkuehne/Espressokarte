//
//  DrinkFilter.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 13.01.26.
//

import Combine
import Foundation
import SwiftUI

/// Manages the user's selected drink type filter
@MainActor
final class DrinkFilterManager: ObservableObject {
    static let shared = DrinkFilterManager()
    
    /// The currently selected drink name to display on the map
    @AppStorage("selectedDrinkFilter") var selectedDrink: String = "Espresso"
    
    /// All available drink types found across all cafes
    @Published private(set) var availableDrinks: [String] = ["Espresso"]
    
    private init() {}
    
    /// Updates available drinks from the current cafe data
    func updateAvailableDrinks(from cafes: [Cafe]) {
        var drinkSet = Set<String>()
        
        for cafe in cafes {
            for record in cafe.priceHistory {
                for drink in record.drinks {
                    drinkSet.insert(drink.name)
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
        
        // Reset to Espresso if selected drink is no longer available
        if !availableDrinks.contains(selectedDrink) {
            selectedDrink = "Espresso"
        }
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
