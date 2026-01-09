//
//  LocationManager.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 07.01.26.
//

import Combine
import CoreLocation
import Foundation

/// Manages user location services
@MainActor
final class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()

    private let locationManager = CLLocationManager()

    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var error: Error?

    /// Default location (Munich city center) when location is unavailable
    static let defaultLocation = CLLocationCoordinate2D(latitude: 48.1351, longitude: 11.5820)

    /// Current coordinate or default
    var currentCoordinate: CLLocationCoordinate2D {
        currentLocation?.coordinate ?? Self.defaultLocation
    }

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
    }

    /// Requests location permission
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Starts updating location
    func startUpdating() {
        locationManager.startUpdatingLocation()
    }

    /// Stops updating location
    func stopUpdating() {
        locationManager.stopUpdatingLocation()
    }

    /// Requests a single location update
    func requestLocation() {
        locationManager.requestLocation()
    }

    /// Calculates distance from current location to a coordinate
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard let currentLocation = currentLocation else { return nil }
        let targetLocation = CLLocation(
            latitude: coordinate.latitude, longitude: coordinate.longitude)
        return currentLocation.distance(from: targetLocation)
    }

    /// Formats distance for display
    func formattedDistance(to coordinate: CLLocationCoordinate2D) -> String? {
        guard let distance = distance(to: coordinate) else { return nil }

        if distance < 1000 {
            return String(format: "%.0f m", distance)
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }

    /// Maximum distance (in meters) to allow adding/updating prices
    /// Allows for GPS inaccuracy margin
    static let maxPriceUpdateDistance: CLLocationDistance = 100

    /// Checks if user is within range to update a cafe's price
    func isWithinPriceUpdateRange(of coordinate: CLLocationCoordinate2D) -> Bool {
        guard let distance = distance(to: coordinate) else { return false }
        return distance <= Self.maxPriceUpdateDistance
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            self.currentLocation = locations.last
            self.error = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.error = error
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus

            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.startUpdatingLocation()
            case .denied, .restricted:
                self.error = LocationError.permissionDenied
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Location Errors

enum LocationError: LocalizedError {
    case permissionDenied
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location permission denied. Please enable in Settings."
        case .locationUnavailable:
            return "Unable to determine current location."
        }
    }
}
