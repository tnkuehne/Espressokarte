//
//  LocalCacheManager.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 07.01.26.
//

import Foundation

/// Manages local caching of cafe data for offline support
final class LocalCacheManager {
    static let shared = LocalCacheManager()

    private let cacheKey = "cachedCafes"
    private let lastSyncKey = "lastSyncDate"

    private let userDefaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - Caching

    /// Caches the list of cafes to local storage
    func cacheCafes(_ cafes: [Cafe]) {
        do {
            let data = try encoder.encode(cafes)
            userDefaults.set(data, forKey: cacheKey)
            userDefaults.set(Date(), forKey: lastSyncKey)
        } catch {
            print("Error caching cafes: \(error)")
        }
    }

    /// Loads cached cafes from local storage
    func loadCachedCafes() -> [Cafe] {
        guard let data = userDefaults.data(forKey: cacheKey) else {
            return []
        }

        do {
            return try decoder.decode([Cafe].self, from: data)
        } catch {
            print("Error loading cached cafes: \(error)")
            return []
        }
    }

    /// Returns the date of the last successful sync
    var lastSyncDate: Date? {
        userDefaults.object(forKey: lastSyncKey) as? Date
    }

    /// Returns a formatted string for the last sync time
    var lastSyncDescription: String {
        guard let date = lastSyncDate else {
            return "Never synced"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last synced \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    /// Clears the local cache
    func clearCache() {
        userDefaults.removeObject(forKey: cacheKey)
        userDefaults.removeObject(forKey: lastSyncKey)
    }
}
