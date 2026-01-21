//
//  SwiftDataCacheManager.swift
//  Espressokarte
//
//  Manages local caching of cafe data using SwiftData for offline support
//

import Foundation
import SwiftData

/// Manages local caching of cafe data using SwiftData
@MainActor
final class SwiftDataCacheManager {
    static let shared = SwiftDataCacheManager()

    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?

    private init() {}

    // MARK: - Setup

    /// Initialize with a ModelContainer (call this from app startup)
    func configure(with container: ModelContainer) {
        self.modelContainer = container
        self.modelContext = container.mainContext
    }

    /// Create and return a ModelContainer for the app
    static func createModelContainer() -> ModelContainer {
        let schema = Schema([
            CachedCafe.self,
            CachedPriceRecord.self,
            CacheMetadata.self
        ])

        // Use .none for cloudKitDatabase to disable CloudKit sync
        // This is a local-only cache - actual CloudKit sync is handled by CloudKitManager
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If we can't load the container, delete the old database and try again
            // This handles schema migration issues for cache data (which can be safely regenerated)
            print("SwiftData container failed to load, resetting cache: \(error)")

            // Delete existing SwiftData files
            let fileManager = FileManager.default
            if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let defaultStore = appSupport.appendingPathComponent("default.store")
                try? fileManager.removeItem(at: defaultStore)
                try? fileManager.removeItem(at: defaultStore.appendingPathExtension("shm"))
                try? fileManager.removeItem(at: defaultStore.appendingPathExtension("wal"))
            }

            // Try again with fresh database
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                // Last resort: use in-memory storage
                print("SwiftData still failed, using in-memory storage: \(error)")
                let inMemoryConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                do {
                    return try ModelContainer(for: schema, configurations: [inMemoryConfig])
                } catch {
                    fatalError("Could not create ModelContainer even in-memory: \(error)")
                }
            }
        }
    }

    // MARK: - Caching

    /// Caches the list of cafes to local storage
    func cacheCafes(_ cafes: [Cafe]) {
        guard let context = modelContext else {
            print("SwiftDataCacheManager: No context available")
            return
        }

        do {
            // Get existing cached cafes for efficient update
            let existingCafes = try fetchCachedCafes()
            let existingCafeMap = Dictionary(uniqueKeysWithValues: existingCafes.map { ($0.id, $0) })

            for cafe in cafes {
                if let existingCafe = existingCafeMap[cafe.id] {
                    // Update existing cafe
                    existingCafe.update(from: cafe)
                    updatePriceRecords(for: existingCafe, from: cafe.priceHistory)
                } else {
                    // Insert new cafe
                    let cachedCafe = CachedCafe(
                        id: cafe.id,
                        name: cafe.name,
                        address: cafe.address,
                        latitude: cafe.latitude,
                        longitude: cafe.longitude,
                        currentPrice: cafe.currentPrice
                    )
                    context.insert(cachedCafe)

                    // Add price records
                    for priceRecord in cafe.priceHistory {
                        let cachedRecord = CachedPriceRecord(
                            id: priceRecord.id,
                            date: priceRecord.date,
                            addedBy: priceRecord.addedBy,
                            addedByName: priceRecord.addedByName,
                            note: priceRecord.note,
                            menuImageData: priceRecord.menuImageData,
                            drinks: priceRecord.drinks
                        )
                        cachedCafe.priceHistory.append(cachedRecord)
                    }
                }
            }

            // Remove cafes that no longer exist in CloudKit
            let newCafeIDs = Set(cafes.map { $0.id })
            for (id, cachedCafe) in existingCafeMap where !newCafeIDs.contains(id) {
                context.delete(cachedCafe)
            }

            // Update sync metadata
            updateLastSyncDate()

            try context.save()
        } catch {
            print("Error caching cafes: \(error)")
        }
    }

    /// Updates price records for a cached cafe
    private func updatePriceRecords(for cachedCafe: CachedCafe, from priceRecords: [PriceRecord]) {
        guard let context = modelContext else { return }

        let existingRecordMap = Dictionary(
            uniqueKeysWithValues: cachedCafe.priceHistory.map { ($0.id, $0) }
        )
        let newRecordIDs = Set(priceRecords.map { $0.id })

        // Add new or update existing records
        for priceRecord in priceRecords {
            if existingRecordMap[priceRecord.id] == nil {
                let cachedRecord = CachedPriceRecord(
                    id: priceRecord.id,
                    date: priceRecord.date,
                    addedBy: priceRecord.addedBy,
                    addedByName: priceRecord.addedByName,
                    note: priceRecord.note,
                    menuImageData: priceRecord.menuImageData,
                    drinks: priceRecord.drinks
                )
                cachedCafe.priceHistory.append(cachedRecord)
            }
        }

        // Remove records that no longer exist
        for (id, cachedRecord) in existingRecordMap where !newRecordIDs.contains(id) {
            context.delete(cachedRecord)
        }
    }

    /// Fetches all cached cafes
    private func fetchCachedCafes() throws -> [CachedCafe] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<CachedCafe>()
        return try context.fetch(descriptor)
    }

    /// Loads cached cafes from local storage
    func loadCachedCafes() -> [Cafe] {
        do {
            let cachedCafes = try fetchCachedCafes()
            return cachedCafes.map { $0.toCafe() }
        } catch {
            print("Error loading cached cafes: \(error)")
            return []
        }
    }

    // MARK: - Sync Metadata

    /// Updates the last sync date
    private func updateLastSyncDate() {
        guard let context = modelContext else { return }

        do {
            let descriptor = FetchDescriptor<CacheMetadata>(
                predicate: #Predicate { $0.key == "default" }
            )
            let results = try context.fetch(descriptor)

            if let metadata = results.first {
                metadata.lastSyncDate = Date()
            } else {
                let metadata = CacheMetadata(key: "default", lastSyncDate: Date())
                context.insert(metadata)
            }
        } catch {
            print("Error updating sync date: \(error)")
        }
    }

    /// Returns the date of the last successful sync
    var lastSyncDate: Date? {
        guard let context = modelContext else { return nil }

        do {
            let descriptor = FetchDescriptor<CacheMetadata>(
                predicate: #Predicate { $0.key == "default" }
            )
            let results = try context.fetch(descriptor)
            return results.first?.lastSyncDate
        } catch {
            print("Error fetching sync date: \(error)")
            return nil
        }
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
        guard let context = modelContext else { return }

        do {
            try context.delete(model: CachedCafe.self)
            try context.delete(model: CachedPriceRecord.self)
            try context.delete(model: CacheMetadata.self)
            try context.save()
        } catch {
            print("Error clearing cache: \(error)")
        }
    }
}
