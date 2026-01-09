//
//  PriceRecord.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 07.01.26.
//

import Foundation

/// Price validation error
enum PriceValidationError: LocalizedError {
    case tooLow
    case tooHigh
    case invalid

    var errorDescription: String? {
        switch self {
        case .tooLow:
            return "Price seems too low. Espresso prices are typically at least €0.50."
        case .tooHigh:
            return "Price seems too high. Please check the price and try again."
        case .invalid:
            return "Please enter a valid price."
        }
    }
}

/// A single price entry for a cafe
struct PriceRecord: Identifiable, Codable, Hashable {

    /// Valid price range for espresso (in euros)
    static let minimumPrice: Double = 0.50
    static let maximumPrice: Double = 15.00

    /// Validates a price and returns an error if invalid
    static func validate(price: Double) -> PriceValidationError? {
        guard price.isFinite && !price.isNaN else {
            return .invalid
        }

        if price < minimumPrice {
            return .tooLow
        }

        if price > maximumPrice {
            return .tooHigh
        }

        return nil
    }

    /// Returns true if the price is within valid range
    static func isValid(price: Double) -> Bool {
        validate(price: price) == nil
    }
    /// Unique identifier for this price record
    let id: String

    /// The espresso price in euros
    let price: Double

    /// When this price was recorded
    let date: Date

    /// CloudKit user record name who added this price
    let addedBy: String

    /// Display name of the user who added this price
    let addedByName: String

    /// Optional note about this price
    let note: String?

    /// Optional menu image data (JPEG compressed)
    let menuImageData: Data?

    /// Formatted price string
    var formattedPrice: String {
        String(format: "€%.2f", price)
    }

    /// Formatted date string
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Relative date string (e.g., "2 days ago")
    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    init(
        id: String = UUID().uuidString,
        price: Double,
        date: Date = Date(),
        addedBy: String,
        addedByName: String,
        note: String? = nil,
        menuImageData: Data? = nil
    ) {
        self.id = id
        self.price = price
        self.date = date
        self.addedBy = addedBy
        self.addedByName = addedByName
        self.note = note
        self.menuImageData = menuImageData
    }
}
