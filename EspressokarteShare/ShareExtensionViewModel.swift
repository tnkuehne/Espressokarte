//
//  ShareExtensionViewModel.swift
//  EspressokarteShare
//
//  Created by Claude on 10.01.26.
//

import CloudKit
import Combine
import Foundation
import MapKit
import Security
import UIKit

/// Represents the current state of the share extension flow
enum ShareExtensionState: Equatable {
    case loading
    case notSignedIn
    case parsingURL
    case fetchingImage
    case extractingPrice
    case selectingCafe
    case ready
    case saving
    case success
    case error(String)

    static func == (lhs: ShareExtensionState, rhs: ShareExtensionState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading),
            (.notSignedIn, .notSignedIn),
            (.parsingURL, .parsingURL),
            (.fetchingImage, .fetchingImage),
            (.extractingPrice, .extractingPrice),
            (.selectingCafe, .selectingCafe),
            (.ready, .ready),
            (.saving, .saving),
            (.success, .success):
            return true
        case (.error(let lhsMsg), .error(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}

/// Lightweight cafe data for the share extension
struct ShareCafeData: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// ViewModel for the share extension, orchestrating the import flow
@MainActor
final class ShareExtensionViewModel: ObservableObject {
    @Published var state: ShareExtensionState = .loading
    @Published var photoData: GoogleMapsPhotoData?
    @Published var menuImage: UIImage?
    @Published var extractedPrice: Double?
    @Published var matchingCafes: [ShareCafeData] = []
    @Published var selectedCafe: ShareCafeData?
    @Published var priceDate: Date = Date()

    private let urlParser = GoogleMapsURLParser()
    private let workerURL = URL(string: "https://espressokarte.timokuehne.com")!
    private let accessGroup = "group.com.timokuehne.Espressokarte"
    private let tokenKey = "com.espressokarte.appleIdentityToken"
    private let userIdKey = "com.espressokarte.appleUserIdentifier"
    private let userNameKey = "com.espressokarte.appleUserName"

    private var inputURL: URL?

    var canSave: Bool {
        selectedCafe != nil && extractedPrice != nil && state != .saving
    }

    // MARK: - Main Processing Flow

    func processURL(_ url: URL) async {
        inputURL = url

        // Check authentication first
        guard let token = getStoredToken() else {
            state = .notSignedIn
            return
        }

        state = .parsingURL

        do {
            // Resolve short URL if needed
            let fullURL: URL
            if urlParser.isShortURL(url) {
                fullURL = try await urlParser.resolveShortURL(url)
            } else {
                fullURL = url
            }

            // Parse Google Maps URL
            let data = try urlParser.parse(fullURL)
            photoData = data

            // Fetch the image
            state = .fetchingImage
            let image = try await fetchImage(from: data.imageURL)
            menuImage = image

            // Extract price
            state = .extractingPrice
            let price = try await extractPrice(from: image, token: token)

            guard let extractedPrice = price else {
                state = .error("Could not find an espresso price in this image.")
                return
            }
            self.extractedPrice = extractedPrice

            // Find matching Apple Maps location
            let cafes = try await findMatchingCafes(
                near: data.coordinate,
                name: data.placeName
            )
            matchingCafes = cafes

            if cafes.count == 1 {
                // Auto-select if only one match
                selectedCafe = cafes.first
                state = .ready
            } else if cafes.isEmpty {
                state = .error("Could not find \"\(data.placeName)\" in Apple Maps.")
            } else {
                state = .selectingCafe
            }

        } catch let error as GoogleMapsURLParserError {
            state = .error(error.localizedDescription)
        } catch {
            state = .error("Failed to process: \(error.localizedDescription)")
        }
    }

    func selectCafe(_ cafe: ShareCafeData) {
        selectedCafe = cafe
        state = .ready
    }

    func save() async {
        guard let cafe = selectedCafe,
            let price = extractedPrice,
            let token = getStoredToken()
        else { return }

        state = .saving

        do {
            let imageData = menuImage?.jpegData(compressionQuality: 0.7)

            try await saveCafeWithPrice(
                cafe: cafe,
                price: price,
                menuImageData: imageData
            )

            state = .success
        } catch {
            state = .error("Failed to save: \(error.localizedDescription)")
        }
    }

    func retry() async {
        guard let url = inputURL else { return }
        await processURL(url)
    }

    // MARK: - Private: Image Fetching

    private func fetchImage(from url: URL) async throws -> UIImage {
        let request = URLRequest(url: url, timeoutInterval: 15)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw NSError(
                domain: "ShareExtension", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to download image"])
        }

        guard let image = UIImage(data: data) else {
            throw NSError(
                domain: "ShareExtension", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
        }

        return image
    }

    // MARK: - Private: Price Extraction

    private func extractPrice(from image: UIImage, token: String) async throws -> Double? {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(
                domain: "ShareExtension", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to process image"])
        }

        // Compress if too large
        let compressedData = compressIfNeeded(imageData, maxBytes: 2_000_000)
        let base64Image = compressedData.base64EncodedString()

        var request = URLRequest(url: workerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "image": base64Image,
            "mediaType": "image/jpeg",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "ShareExtension", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }

        switch httpResponse.statusCode {
        case 200:
            let result = try JSONDecoder().decode(PriceResponse.self, from: data)
            return result.price
        case 401:
            throw NSError(
                domain: "ShareExtension", code: 401,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Authentication expired. Please sign in again in the app."
                ])
        case 429:
            throw NSError(
                domain: "ShareExtension", code: 429,
                userInfo: [NSLocalizedDescriptionKey: "Too many requests. Please wait a minute."])
        default:
            throw NSError(
                domain: "ShareExtension", code: httpResponse.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: "Server error: HTTP \(httpResponse.statusCode)"
                ])
        }
    }

    private func compressIfNeeded(_ data: Data, maxBytes: Int) -> Data {
        guard data.count > maxBytes else { return data }

        guard let image = UIImage(data: data) else { return data }

        var compression: CGFloat = 0.7
        var imageData = image.jpegData(compressionQuality: compression)

        while let currentData = imageData, currentData.count > maxBytes && compression > 0.1 {
            compression -= 0.1
            imageData = image.jpegData(compressionQuality: compression)
        }

        return imageData ?? data
    }

    // MARK: - Private: Apple Maps Search

    private func findMatchingCafes(
        near coordinate: CLLocationCoordinate2D,
        name: String
    ) async throws -> [ShareCafeData] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.resultTypes = .pointOfInterest

        // Small region around the Google Maps coordinates
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 200,
            longitudinalMeters: 200
        )
        request.region = region

        let search = MKLocalSearch(request: request)
        let response = try await search.start()

        return response.mapItems.compactMap { mapItem -> ShareCafeData? in
            guard let itemName = mapItem.name else { return nil }

            let location = mapItem.placemark.coordinate

            // Create unique ID from coordinates and name
            let id =
                "\(location.latitude)_\(location.longitude)_\(itemName)"
                .replacingOccurrences(of: " ", with: "_")

            // Build address
            let address = [
                mapItem.placemark.thoroughfare,
                mapItem.placemark.locality,
            ].compactMap { $0 }.joined(separator: ", ")

            return ShareCafeData(
                id: id,
                name: itemName,
                address: address.isEmpty ? "Unknown address" : address,
                latitude: location.latitude,
                longitude: location.longitude
            )
        }
    }

    // MARK: - Private: CloudKit Save

    private func saveCafeWithPrice(
        cafe: ShareCafeData,
        price: Double,
        menuImageData: Data?
    ) async throws {
        // Use the main app's CloudKit container explicitly
        let container = CKContainer(identifier: "iCloud.com.timokuehne.Espressokarte")
        let publicDatabase = container.publicCloudDatabase

        // Get or create cafe record
        let cafeRecordID = CKRecord.ID(recordName: cafe.id)
        let cafeRecord: CKRecord

        do {
            cafeRecord = try await publicDatabase.record(for: cafeRecordID)
        } catch let error as CKError where error.code == .unknownItem {
            // Cafe doesn't exist, create it
            cafeRecord = CKRecord(recordType: "Cafe", recordID: cafeRecordID)
            cafeRecord["cafeId"] = cafe.id
            cafeRecord["name"] = cafe.name
            cafeRecord["address"] = cafe.address
            cafeRecord["latitude"] = cafe.latitude
            cafeRecord["longitude"] = cafe.longitude
        }

        // Update current price
        cafeRecord["currentPrice"] = price

        // Save cafe record
        try await publicDatabase.save(cafeRecord)

        // Create price record
        let priceRecordID = CKRecord.ID(recordName: UUID().uuidString)
        let priceRecord = CKRecord(recordType: "PriceRecord", recordID: priceRecordID)
        guard let userRecordID = getUserRecordID() else {
            throw NSError(
                domain: "ShareExtension", code: 10,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "User ID not found. Please sign out and sign in again in the main app."
                ])
        }

        guard let userName = getUserName() else {
            throw NSError(
                domain: "ShareExtension", code: 11,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "User name not found. Please sign out and sign in again in the main app."
                ])
        }

        priceRecord["price"] = price
        priceRecord["date"] = priceDate
        priceRecord["addedBy"] = userRecordID
        priceRecord["addedByName"] = userName
        priceRecord["note"] = "Imported from Google Maps"
        priceRecord["cafeReference"] = CKRecord.Reference(
            recordID: cafeRecord.recordID,
            action: .deleteSelf
        )

        // Save menu image as CKAsset if provided
        if let imageData = menuImageData {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".jpg")
            try imageData.write(to: tempURL)
            priceRecord["menuImage"] = CKAsset(fileURL: tempURL)

            try await publicDatabase.save(priceRecord)

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
        } else {
            try await publicDatabase.save(priceRecord)
        }
    }

    // MARK: - Private: Keychain Access

    private func getStoredToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
            let data = result as? Data,
            let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return token
    }

    private func getUserRecordID() -> String? {
        let sharedDefaults = UserDefaults(suiteName: accessGroup)
        return sharedDefaults?.string(forKey: userIdKey)
    }

    private func getUserName() -> String? {
        let sharedDefaults = UserDefaults(suiteName: accessGroup)
        return sharedDefaults?.string(forKey: userNameKey)
    }
}

// MARK: - Response Types

private struct PriceResponse: Decodable {
    let success: Bool?
    let price: Double?
    let confidence: String?
}
