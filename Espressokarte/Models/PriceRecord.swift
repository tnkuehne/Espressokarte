//
//  PriceRecord.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 07.01.26.
//

import Foundation

/// A single price entry for a cafe
struct PriceRecord: Identifiable, Codable, Hashable {
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
