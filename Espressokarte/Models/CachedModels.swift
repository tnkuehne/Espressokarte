//
//  CachedModels.swift
//  Espressokarte
//
//  SwiftData models for local caching of CloudKit data
//

import Foundation
import SwiftData

/// Cached version of a cafe for local persistence
@Model
final class CachedCafe {
    /// Unique identifier - matches CloudKit record ID
    @Attribute(.unique) var id: String

    /// Name of the cafe
    var name: String

    /// Address of the cafe
    var address: String

    /// Latitude coordinate
    var latitude: Double

    /// Longitude coordinate
    var longitude: Double

    /// Current espresso price in euros
    var currentPrice: Double?

    /// Price history for this cafe
    @Relationship(deleteRule: .cascade, inverse: \CachedPriceRecord.cafe)
    var priceHistory: [CachedPriceRecord]

    init(
        id: String,
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        currentPrice: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.currentPrice = currentPrice
        self.priceHistory = []
    }

    /// Convert to domain model
    func toCafe() -> Cafe {
        Cafe(
            id: id,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            currentPrice: currentPrice,
            priceHistory: priceHistory.map { $0.toPriceRecord() }
        )
    }

    /// Update from domain model
    func update(from cafe: Cafe) {
        self.name = cafe.name
        self.address = cafe.address
        self.latitude = cafe.latitude
        self.longitude = cafe.longitude
        self.currentPrice = cafe.currentPrice
    }
}

/// Cached version of a price record
@Model
final class CachedPriceRecord {
    /// Unique identifier - matches CloudKit record ID
    @Attribute(.unique) var id: String

    /// When this price was recorded
    var date: Date

    /// CloudKit user record name who added this price
    var addedBy: String

    /// Display name of the user who added this price
    var addedByName: String

    /// Optional note about this price
    var note: String?

    /// Optional menu image data (JPEG compressed)
    @Attribute(.externalStorage)
    var menuImageData: Data?

    /// Drinks stored as JSON for simplicity
    var drinksJSON: Data?

    /// Reference to parent cafe
    var cafe: CachedCafe?

    init(
        id: String,
        date: Date,
        addedBy: String,
        addedByName: String,
        note: String? = nil,
        menuImageData: Data? = nil,
        drinks: [DrinkPrice] = []
    ) {
        self.id = id
        self.date = date
        self.addedBy = addedBy
        self.addedByName = addedByName
        self.note = note
        self.menuImageData = menuImageData
        self.drinksJSON = try? JSONEncoder().encode(drinks)
    }

    /// Decoded drinks array
    var drinks: [DrinkPrice] {
        guard let data = drinksJSON else { return [] }
        return (try? JSONDecoder().decode([DrinkPrice].self, from: data)) ?? []
    }

    /// Convert to domain model
    func toPriceRecord() -> PriceRecord {
        PriceRecord(
            id: id,
            date: date,
            addedBy: addedBy,
            addedByName: addedByName,
            note: note,
            menuImageData: menuImageData,
            drinks: drinks
        )
    }
}

/// Metadata for cache sync status
@Model
final class CacheMetadata {
    @Attribute(.unique) var key: String
    var lastSyncDate: Date?

    init(key: String = "default", lastSyncDate: Date? = nil) {
        self.key = key
        self.lastSyncDate = lastSyncDate
    }
}
