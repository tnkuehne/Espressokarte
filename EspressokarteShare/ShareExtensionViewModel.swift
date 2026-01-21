//
//  ShareExtensionViewModel.swift
//  EspressokarteShare
//
//  Created by Claude on 10.01.26.
//

import AuthenticationServices
import CloudKit
import Combine
import Foundation
import MapKit
import Security
import UIKit

/// Drink price extracted from menu
struct DrinkPrice: Codable {
    let name: String
    let price: Double
}

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
    @Published var extractedDrinks: [DrinkPrice] = []
    @Published var extractedPrice: Double?
    @Published var matchingCafes: [ShareCafeData] = []
    @Published var selectedCafe: ShareCafeData?
    @Published var priceDate: Date = Date()

    private let urlParser = GoogleMapsURLParser()
    private let workerURL = URL(string: "https://espressokarte.timokuehne.com")!
    private let signInManager = ShareExtensionSignInManager()

    private var inputURL: URL?
    private weak var presentingWindow: UIWindow?

    var canSave: Bool {
        selectedCafe != nil && extractedPrice != nil && state != .saving
    }

    /// Set the window for presenting sign-in UI
    func setPresentingWindow(_ window: UIWindow?) {
        self.presentingWindow = window
    }

    /// Attempt to sign in with Apple from the share extension
    func signIn() async {
        do {
            _ = try await signInManager.signIn(presentingFrom: presentingWindow)
            // After successful sign-in, retry processing if we have a URL
            if let url = inputURL {
                await processURL(url)
            } else {
                state = .loading
            }
        } catch let error as ASAuthorizationError where error.code == .canceled {
            // User cancelled, stay on not signed in screen
            state = .notSignedIn
        } catch {
            state = .error("Sign in failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Main Processing Flow

    func processURL(_ url: URL) async {
        inputURL = url

        // Check authentication first - need both token AND user ID
        guard let token = getStoredToken(),
            getUserRecordID() != nil
        else {
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

            // Extract prices
            state = .extractingPrice
            let result = try await extractPrices(from: image, token: token)

            guard let espressoPrice = result.espressoPrice else {
                state = .error("Could not find an espresso price in this image.")
                return
            }
            self.extractedDrinks = result.drinks
            self.extractedPrice = espressoPrice

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
            !extractedDrinks.isEmpty
        else { return }

        state = .saving

        do {
            let imageData = menuImage?.jpegData(compressionQuality: 0.7)

            try await saveCafeWithPrice(
                cafe: cafe,
                espressoPrice: price,
                drinks: extractedDrinks,
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

    private func extractPrices(from image: UIImage, token: String) async throws -> PriceExtractionResult {
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
        request.timeoutInterval = 90

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
            return PriceExtractionResult(drinks: result.drinks ?? [])
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
        espressoPrice: Double,
        drinks: [DrinkPrice],
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

        // Update current price (espresso price for map display)
        cafeRecord["currentPrice"] = espressoPrice

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

        priceRecord["date"] = priceDate
        priceRecord["addedBy"] = userRecordID
        priceRecord["addedByName"] = userName
        priceRecord["note"] = "Imported from Google Maps"
        priceRecord["cafeReference"] = CKRecord.Reference(
            recordID: cafeRecord.recordID,
            action: .deleteSelf
        )

        // Save drinks as JSON string (same format as main app)
        if let drinksData = try? JSONEncoder().encode(drinks),
           let drinksJSON = String(data: drinksData, encoding: .utf8) {
            priceRecord["drinksJSON"] = drinksJSON
        }

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

    // MARK: - Private: Auth Helpers

    private func getStoredToken() -> String? {
        return signInManager.getStoredToken()
    }

    private func getUserRecordID() -> String? {
        return signInManager.getUserId()
    }

    private func getUserName() -> String? {
        return signInManager.getUserName()
    }
}

// MARK: - Response Types

private struct PriceExtractionResult {
    let drinks: [DrinkPrice]

    /// Find espresso price from the drinks array
    var espressoPrice: Double? {
        // Look for exact "Espresso" first
        if let espresso = drinks.first(where: { $0.name.lowercased() == "espresso" }) {
            return espresso.price
        }
        // Fallback: find any drink containing "espresso" but not "double" or "doppio"
        if let espresso = drinks.first(where: {
            let name = $0.name.lowercased()
            return name.contains("espresso") && !name.contains("double") && !name.contains("doppio")
        }) {
            return espresso.price
        }
        return nil
    }
}

private struct PriceResponse: Decodable {
    let success: Bool?
    let drinks: [DrinkPrice]?
}
