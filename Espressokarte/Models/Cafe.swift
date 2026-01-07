//
//  Cafe.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 07.01.26.
//

import Foundation
import CoreLocation

/// Represents a cafe with espresso price information
struct Cafe: Identifiable, Codable, Hashable {
    /// Unique identifier - uses MapKit POI identifier when available
    let id: String

    /// Name of the cafe from MapKit
    let name: String

    /// Address of the cafe
    let address: String

    /// Latitude coordinate
    let latitude: Double

    /// Longitude coordinate
    let longitude: Double

    /// Current espresso price in euros
    var currentPrice: Double?

    /// Price history for this cafe
    var priceHistory: [PriceRecord]

    /// Convenience property for CLLocationCoordinate2D
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Formatted price string
    var formattedPrice: String? {
        guard let price = currentPrice else { return nil }
        return String(format: "€%.2f", price)
    }

    /// Most recent price record
    var latestPriceRecord: PriceRecord? {
        priceHistory.max(by: { $0.date < $1.date })
    }

    init(
        id: String,
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        currentPrice: Double? = nil,
        priceHistory: [PriceRecord] = []
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.currentPrice = currentPrice
        self.priceHistory = priceHistory
    }

    /// Creates a Cafe from a MapKit search result
    static func from(mapItem: MapItemData) -> Cafe {
        Cafe(
            id: mapItem.id,
            name: mapItem.name,
            address: mapItem.address,
            latitude: mapItem.latitude,
            longitude: mapItem.longitude
        )
    }
}

/// Lightweight representation of MapKit MKMapItem data
struct MapItemData: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
