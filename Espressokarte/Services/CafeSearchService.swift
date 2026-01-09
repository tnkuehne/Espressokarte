//
//  CafeSearchService.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 07.01.26.
//

import Combine
import Foundation
import MapKit

/// Service for searching cafes using MapKit
@MainActor
final class CafeSearchService: ObservableObject {
    static let shared = CafeSearchService()

    @Published private(set) var nearbyCafes: [MapItemData] = []
    @Published private(set) var isSearching = false
    @Published private(set) var error: Error?

    private init() {}

    /// Searches for nearby cafes at the given location
    func searchNearbyCafes(at coordinate: CLLocationCoordinate2D, radius: CLLocationDistance = 200)
        async
    {
        isSearching = true
        error = nil

        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "cafe"
            request.resultTypes = .pointOfInterest

            // Create a region around the coordinate
            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: radius * 2,
                longitudinalMeters: radius * 2
            )
            request.region = region

            let search = MKLocalSearch(request: request)
            let response = try await search.start()

            // Convert to MapItemData and sort by distance
            let cafes = response.mapItems.compactMap { mapItem -> MapItemData? in
                guard let name = mapItem.name else {
                    return nil
                }

                let location = mapItem.location

                // Create unique ID from coordinates and name
                let id = "\(location.coordinate.latitude)_\(location.coordinate.longitude)_\(name)"
                    .replacingOccurrences(of: " ", with: "_")

                return MapItemData(
                    id: id,
                    name: name,
                    address: mapItem.addressRepresentations!.fullAddress(
                        includingRegion: false, singleLine: true)!,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
            }

            // Sort by distance from search location
            let searchLocation = CLLocation(
                latitude: coordinate.latitude, longitude: coordinate.longitude)
            let sortedCafes = cafes.sorted { cafe1, cafe2 in
                let loc1 = CLLocation(latitude: cafe1.latitude, longitude: cafe1.longitude)
                let loc2 = CLLocation(latitude: cafe2.latitude, longitude: cafe2.longitude)
                return searchLocation.distance(from: loc1) < searchLocation.distance(from: loc2)
            }

            self.nearbyCafes = sortedCafes

        } catch {
            self.error = error
            self.nearbyCafes = []
        }

        isSearching = false
    }

    /// Searches for cafes matching a query string
    func searchCafes(query: String, near coordinate: CLLocationCoordinate2D) async {
        guard !query.isEmpty else {
            await searchNearbyCafes(at: coordinate)
            return
        }

        isSearching = true
        error = nil

        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "\(query) cafe"
            request.resultTypes = .pointOfInterest

            // Search in a larger region for query-based search
            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 5000,
                longitudinalMeters: 5000
            )
            request.region = region

            let search = MKLocalSearch(request: request)
            let response = try await search.start()

            let cafes = response.mapItems.compactMap { mapItem -> MapItemData? in
                guard let name = mapItem.name else {
                    return nil
                }

                let location = mapItem.location

                let id = "\(location.coordinate.latitude)_\(location.coordinate.longitude)_\(name)"
                    .replacingOccurrences(of: " ", with: "_")

                return MapItemData(
                    id: id,
                    name: name,
                    address: mapItem.addressRepresentations!.fullAddress(
                        includingRegion: false, singleLine: true)!,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
            }

            self.nearbyCafes = cafes

        } catch {
            self.error = error
        }

        isSearching = false
    }

    /// Returns the closest cafe to the given coordinate
    func closestCafe(to coordinate: CLLocationCoordinate2D) -> MapItemData? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        return nearbyCafes.min { cafe1, cafe2 in
            let loc1 = CLLocation(latitude: cafe1.latitude, longitude: cafe1.longitude)
            let loc2 = CLLocation(latitude: cafe2.latitude, longitude: cafe2.longitude)
            return location.distance(from: loc1) < location.distance(from: loc2)
        }
    }

    /// Calculates distance between two coordinates
    func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation)
    }
}
