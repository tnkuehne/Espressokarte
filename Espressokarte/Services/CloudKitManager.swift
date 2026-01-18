//
//  CloudKitManager.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 07.01.26.
//

import CloudKit
import Combine
import Foundation

/// CloudKit-specific errors
enum CloudKitError: LocalizedError {
    case notSignedIn
    case noUserName
    case invalidPrice(PriceValidationError)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return
                "You must be signed into iCloud to add prices. Please sign in via Settings > Apple Account > iCloud."
        case .noUserName:
            return
                "Could not get your name. Please go to Settings > Apple Account > Sign-In & Security > Sign in with Apple > Espressokarte > Stop Using Apple ID, then sign in again in the app."
        case .invalidPrice(let validationError):
            return validationError.errorDescription
        }
    }
}

/// Manages CloudKit operations for syncing cafe and price data
@MainActor
final class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()

    private let container: CKContainer
    private let publicDatabase: CKDatabase

    // Record type names
    private let cafeRecordType = "Cafe"
    private let priceRecordType = "PriceRecord"

    // Published properties
    @Published private(set) var cafes: [Cafe] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published private(set) var currentUserName: String = "Unknown"
    @Published private(set) var currentUserRecordID: String = ""

    private var subscriptionID = "cafe-changes"
    private var hasCreatedSchema = false

    private init() {
        self.container = CKContainer.default()
        self.publicDatabase = container.publicCloudDatabase

        // Load cached cafes immediately for instant display
        self.cafes = LocalCacheManager.shared.loadCachedCafes()
        if !self.cafes.isEmpty {
            self.hasCreatedSchema = true
        }
    }

    // MARK: - User Identity

    /// Fetches the current user's identity
    func fetchUserIdentity() async {
        do {
            let userRecordID = try await container.userRecordID()
            currentUserRecordID = userRecordID.recordName

            if let userName = AppleSignInManager.shared.userName {
                currentUserName = userName
            }
        } catch {
            self.error = error
            print("ERROR: Failed to get user identity. Is iCloud signed in? Error: \(error)")
            currentUserRecordID = ""
        }
    }

    /// Fetches the user's name from their existing price records in CloudKit
    /// This is a fallback when Apple Sign In doesn't provide the name (e.g., after app reinstall)
    func fetchUserNameFromExistingRecords() async -> String? {
        guard !currentUserRecordID.isEmpty else {
            return nil
        }

        do {
            // Query for any price record added by this user
            let predicate = NSPredicate(format: "addedBy == %@", currentUserRecordID)
            let query = CKQuery(recordType: priceRecordType, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

            let (results, _) = try await publicDatabase.records(matching: query, resultsLimit: 1)

            for (_, result) in results {
                switch result {
                case .success(let record):
                    if let name = record["addedByName"] as? String, !name.isEmpty {
                        return name
                    }
                case .failure:
                    continue
                }
            }
        } catch {
            print("Error fetching user name from CloudKit: \(error)")
        }

        return nil
    }

    // MARK: - Fetching Data

    /// Fetches all cafes with their price records from CloudKit
    func fetchAllCafes() async {
        // Only show loading indicator if we have no cached data
        let hasCachedData = !cafes.isEmpty
        if !hasCachedData {
            isLoading = true
        }
        error = nil

        do {
            // Fetch all cafe records (no server-side sorting to avoid index requirements)
            let cafeQuery = CKQuery(recordType: cafeRecordType, predicate: NSPredicate(value: true))

            let (cafeResults, _) = try await publicDatabase.records(matching: cafeQuery)

            var fetchedCafes: [Cafe] = []

            for (_, result) in cafeResults {
                switch result {
                case .success(let record):
                    if let cafe = await cafeFrom(record: record) {
                        fetchedCafes.append(cafe)
                    }
                case .failure(let error):
                    print("Error fetching cafe record: \(error)")
                }
            }

            self.cafes = fetchedCafes

            // Mark that schema exists if we got results
            if !fetchedCafes.isEmpty {
                hasCreatedSchema = true
            }

            // Cache to local storage
            LocalCacheManager.shared.cacheCafes(fetchedCafes)

        } catch let ckError as CKError {
            // "Unknown Item" means no records exist yet - this is normal for a fresh database
            if ckError.code == .unknownItem {
                print("No cafes in CloudKit yet. Add your first cafe!")
                // Only clear cafes if we don't have cached data
                if !hasCachedData {
                    self.cafes = []
                }
            } else {
                // Real CloudKit error - surface it, but keep cached data
                self.error = ckError
                print("CloudKit error: \(ckError)")
            }
        } catch {
            self.error = error
            print("Network error, using cached data: \(error)")
            // Keep existing cached data on network failure
        }

        isLoading = false
    }

    /// Fetches price records for a specific cafe
    private func fetchPriceRecords(for cafeRecordID: CKRecord.ID) async -> [PriceRecord] {
        do {
            let reference = CKRecord.Reference(recordID: cafeRecordID, action: .none)
            let predicate = NSPredicate(format: "cafeReference == %@", reference)
            let query = CKQuery(recordType: priceRecordType, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

            let (results, _) = try await publicDatabase.records(matching: query)

            var priceRecords: [PriceRecord] = []
            for (_, result) in results {
                switch result {
                case .success(let record):
                    if let priceRecord = priceRecordFrom(record: record) {
                        priceRecords.append(priceRecord)
                    }
                case .failure(let error):
                    print("Error fetching price record: \(error)")
                }
            }

            return priceRecords
        } catch {
            print("Error fetching price records: \(error)")
            return []
        }
    }

    // MARK: - Adding/Updating Data

    /// Adds a new cafe or updates an existing one with drink prices
    func addOrUpdateCafe(_ cafe: Cafe, drinks: [DrinkPrice], note: String?, menuImageData: Data? = nil)
        async throws -> Cafe
    {
        // Derive espresso price from drinks for validation and storage
        guard let espressoPrice = Self.findEspressoPrice(in: drinks) else {
            throw CloudKitError.invalidPrice(.invalid)
        }
        
        // Validate espresso price before proceeding
        if let validationError = PriceRecord.validate(price: espressoPrice) {
            throw CloudKitError.invalidPrice(validationError)
        }

        // Ensure we have a user ID
        if currentUserRecordID.isEmpty {
            await fetchUserIdentity()
        }

        // Fail if we still don't have a valid user ID (not signed into iCloud)
        guard !currentUserRecordID.isEmpty else {
            throw CloudKitError.notSignedIn
        }

        // Get the user name from Apple Sign In, with CloudKit fallback
        var userName = AppleSignInManager.shared.userName

        // If name not available locally, try to recover from CloudKit (user's existing records)
        if userName == nil {
            if let cloudKitName = await fetchUserNameFromExistingRecords() {
                // Store recovered name for future use
                await AppleSignInManager.shared.setRecoveredUserName(cloudKitName)
                userName = cloudKitName
            }
        }

        guard let userName else {
            throw CloudKitError.noUserName
        }
        currentUserName = userName

        // Check if cafe already exists
        let existingRecord = try? await fetchCafeRecord(id: cafe.id)

        let cafeRecord: CKRecord
        if let existing = existingRecord {
            cafeRecord = existing
        } else {
            // Create new cafe record
            cafeRecord = CKRecord(
                recordType: cafeRecordType, recordID: CKRecord.ID(recordName: cafe.id))
            cafeRecord["cafeId"] = cafe.id
            cafeRecord["name"] = cafe.name
            cafeRecord["address"] = cafe.address
            cafeRecord["latitude"] = cafe.latitude
            cafeRecord["longitude"] = cafe.longitude
        }

        // Update current price (espresso price for map display)
        cafeRecord["currentPrice"] = espressoPrice

        // Save cafe record
        try await publicDatabase.save(cafeRecord)

        // Create price record
        let priceRecordID = CKRecord.ID(recordName: UUID().uuidString)
        let priceRecord = CKRecord(recordType: priceRecordType, recordID: priceRecordID)
        priceRecord["date"] = Date()
        priceRecord["addedBy"] = currentUserRecordID
        priceRecord["addedByName"] = currentUserName
        priceRecord["note"] = note
        priceRecord["cafeReference"] = CKRecord.Reference(
            recordID: cafeRecord.recordID, action: .deleteSelf)

        // Save drinks as JSON string
        if let drinksData = try? JSONEncoder().encode(drinks),
           let drinksJSON = String(data: drinksData, encoding: .utf8) {
            priceRecord["drinksJSON"] = drinksJSON
        }

        // Save menu image as CKAsset if provided
        if let imageData = menuImageData {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString + ".jpg")
            try imageData.write(to: tempURL)
            priceRecord["menuImage"] = CKAsset(fileURL: tempURL)

            try await publicDatabase.save(priceRecord)

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
        } else {
            try await publicDatabase.save(priceRecord)
        }

        // Schema is now created, set up subscription
        if !hasCreatedSchema {
            hasCreatedSchema = true
            await setupSubscription()
        }

        // Refresh the cafes list
        await fetchAllCafes()

        // Return updated cafe
        if let updatedCafe = cafes.first(where: { $0.id == cafe.id }) {
            return updatedCafe
        }

        return cafe
    }

    /// Fetches a specific cafe record by ID
    private func fetchCafeRecord(id: String) async throws -> CKRecord? {
        let recordID = CKRecord.ID(recordName: id)
        do {
            return try await publicDatabase.record(for: recordID)
        } catch let ckError as CKError {
            if ckError.code == .unknownItem {
                return nil
            }
            throw ckError
        }
    }

    // MARK: - Record Conversion

    /// Converts a CKRecord to a Cafe model
    private func cafeFrom(record: CKRecord) async -> Cafe? {
        guard let cafeId = record["cafeId"] as? String,
            let name = record["name"] as? String,
            let address = record["address"] as? String,
            let latitude = record["latitude"] as? Double,
            let longitude = record["longitude"] as? Double
        else {
            return nil
        }

        let currentPrice = record["currentPrice"] as? Double
        let priceHistory = await fetchPriceRecords(for: record.recordID)

        return Cafe(
            id: cafeId,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            currentPrice: currentPrice,
            priceHistory: priceHistory
        )
    }

    /// Converts a CKRecord to a PriceRecord model
    private func priceRecordFrom(record: CKRecord) -> PriceRecord? {
        guard let date = record["date"] as? Date,
            let addedBy = record["addedBy"] as? String,
            let addedByName = record["addedByName"] as? String
        else {
            return nil
        }

        let note = record["note"] as? String

        // Load menu image data from CKAsset if present
        var menuImageData: Data?
        if let asset = record["menuImage"] as? CKAsset,
            let fileURL = asset.fileURL
        {
            menuImageData = try? Data(contentsOf: fileURL)
        }

        // Load drinks from JSON string
        var drinks: [DrinkPrice] = []
        if let drinksJSON = record["drinksJSON"] as? String,
           let drinksData = drinksJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([DrinkPrice].self, from: drinksData) {
            drinks = decoded
        } else if let legacyPrice = record["price"] as? Double {
            // Backward compatibility: convert legacy price-only records to drinks array
            drinks = [DrinkPrice(name: "Espresso", price: legacyPrice)]
        }

        return PriceRecord(
            id: record.recordID.recordName,
            date: date,
            addedBy: addedBy,
            addedByName: addedByName,
            note: note,
            menuImageData: menuImageData,
            drinks: drinks
        )
    }
    
    /// Helper to find espresso price from drinks array
    static func findEspressoPrice(in drinks: [DrinkPrice]) -> Double? {
        if let espresso = drinks.first(where: { $0.name.lowercased() == "espresso" }) {
            return espresso.price
        }
        if let espresso = drinks.first(where: { 
            let name = $0.name.lowercased()
            return name.contains("espresso") && !name.contains("double") && !name.contains("doppio")
        }) {
            return espresso.price
        }
        return nil
    }

    // MARK: - Subscriptions

    /// Sets up CloudKit subscription for real-time updates
    func setupSubscription() async {
        // Only set up subscription if schema has been created
        guard hasCreatedSchema else {
            return
        }

        do {
            // Check if subscription already exists
            let existingSubscriptions = try await publicDatabase.allSubscriptions()
            if existingSubscriptions.contains(where: { $0.subscriptionID == subscriptionID }) {
                return
            }

            // Create subscription for cafe changes
            let subscription = CKQuerySubscription(
                recordType: cafeRecordType,
                predicate: NSPredicate(value: true),
                subscriptionID: subscriptionID,
                options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
            )

            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.shouldSendContentAvailable = true
            subscription.notificationInfo = notificationInfo

            try await publicDatabase.save(subscription)
            print("CloudKit subscription set up successfully")
        } catch {
            print("Error setting up subscription: \(error)")
        }
    }

    /// Handles incoming push notifications for CloudKit changes
    func handleNotification() async {
        await fetchAllCafes()
    }

    /// Updates a single cafe in the local array without refetching
    func updateLocalCafe(_ cafe: Cafe) {
        if let index = cafes.firstIndex(where: { $0.id == cafe.id }) {
            cafes[index] = cafe
        }
    }
}
