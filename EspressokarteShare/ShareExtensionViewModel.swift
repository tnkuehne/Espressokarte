//
//  ShareExtensionViewModel.swift
//  EspressokarteShare
//
//  Created by Claude on 10.01.26.
//

import AuthenticationServices
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
    case selectingCafe
    case queuing
    case queued
    case error(String)

    static func == (lhs: ShareExtensionState, rhs: ShareExtensionState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading),
            (.notSignedIn, .notSignedIn),
            (.parsingURL, .parsingURL),
            (.fetchingImage, .fetchingImage),
            (.selectingCafe, .selectingCafe),
            (.queuing, .queuing),
            (.queued, .queued):
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
    @Published var matchingCafes: [ShareCafeData] = []
    @Published var selectedCafe: ShareCafeData?

    private let urlParser = GoogleMapsURLParser()
    // App group for UserDefaults sharing
    private let appGroup = "group.com.timokuehne.Espressokarte"
    // Keychain access group for token sharing
    private var keychainAccessGroup: String {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String
        else {
            fatalError("KeychainAccessGroup not found in Info.plist")
        }
        return group
    }
    private let tokenKey = "com.espressokarte.appleIdentityToken"
    private let userIdKey = "com.espressokarte.appleUserIdentifier"

    private var inputURL: URL?
    private weak var presentingWindow: UIWindow?
    private let signInManager = ShareExtensionSignInManager()


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
        guard getStoredToken() != nil,
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

            // Find matching Apple Maps location
            let cafes = try await findMatchingCafes(
                near: data.coordinate,
                name: data.placeName
            )
            matchingCafes = cafes

            if cafes.count == 1 {
                // Auto-select and queue immediately
                selectedCafe = cafes.first
                queueAndFinish()
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
        queueAndFinish()
    }

    func retry() async {
        guard let url = inputURL else { return }
        await processURL(url)
    }

    /// Queue extraction for background processing by the main app
    private func queueAndFinish() {
        guard let cafe = selectedCafe,
              let image = menuImage else { return }

        state = .queuing

        let success = SharedPendingExtractionManager.shared.queueExtraction(
            cafeId: cafe.id,
            cafeName: cafe.name,
            cafeAddress: cafe.address,
            cafeLatitude: cafe.latitude,
            cafeLongitude: cafe.longitude,
            image: image
        )

        if success {
            state = .queued
        } else {
            state = .error("Failed to queue. Please try again.")
        }
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

    // MARK: - Private: Keychain Access

    private func getStoredToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecAttrAccessGroup as String: keychainAccessGroup,
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
        let sharedDefaults = UserDefaults(suiteName: appGroup)
        return sharedDefaults?.string(forKey: userIdKey)
    }
}
