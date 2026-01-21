//
//  PriceExtractionService.swift
//  Espressokarte
//
//  Created by Claude on 07.01.26.
//

import Combine
import Foundation
import UIKit

/// Service for extracting espresso prices from menu images via Cloudflare Worker
@MainActor
final class PriceExtractionService: ObservableObject {
    static let shared = PriceExtractionService()

    @Published private(set) var isProcessing = false

    private let workerURL = URL(string: "https://espressokarte.timokuehne.com")!
    private let appleSignInManager = AppleSignInManager.shared

    private init() {}

    /// Extract espresso price from a menu image
    /// - Returns: The extracted price, or nil if no price was found
    func extractPrice(from image: UIImage) async throws -> Double? {
        let result = try await extractPrices(from: image)
        return result.espressoPrice
    }

    /// Extract all drink prices from a menu image
    /// - Returns: Full extraction result with espresso price and all drinks found
    func extractPrices(from image: UIImage) async throws -> PriceExtractionResult {
        isProcessing = true
        defer { isProcessing = false }

        // Get auth token
        let token = try await appleSignInManager.getValidToken()

        // Convert image to JPEG data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw PriceExtractionError.imageConversionFailed
        }

        // Compress if too large (target ~2MB max)
        let compressedData = compressImageIfNeeded(image, maxBytes: 2_000_000) ?? imageData

        // Base64 encode
        let base64Image = compressedData.base64EncodedString()

        // Build request
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

        // Send request on background thread to avoid main thread interference
        let (data, response) = try await Task.detached(priority: .userInitiated) {
            try await URLSession.shared.data(for: request)
        }.value

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PriceExtractionError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            // Token expired or invalid - clear and require re-auth
            appleSignInManager.signOut()
            throw PriceExtractionError.authenticationFailed
        case 429:
            // Rate limit exceeded
            throw PriceExtractionError.rateLimitExceeded
        default:
            // Try to parse error message
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw PriceExtractionError.serverError(errorResponse.error ?? "Unknown error")
            }
            throw PriceExtractionError.serverError("HTTP \(httpResponse.statusCode)")
        }

        // Parse successful response
        let result = try JSONDecoder().decode(PriceResponse.self, from: data)

        return PriceExtractionResult(
            drinks: result.drinks ?? []
        )
    }

    // MARK: - Private Helpers

    private func compressImageIfNeeded(_ image: UIImage, maxBytes: Int) -> Data? {
        var compression: CGFloat = 0.8
        var imageData = image.jpegData(compressionQuality: compression)

        while let data = imageData, data.count > maxBytes && compression > 0.1 {
            compression -= 0.1
            imageData = image.jpegData(compressionQuality: compression)
        }

        return imageData
    }
}

// MARK: - Response Types

struct DrinkPrice: Codable, Sendable, Hashable {
    let name: String
    let price: Double
}

struct PriceExtractionResult: Sendable {
    let drinks: [DrinkPrice]

    /// Find espresso price from the drinks array
    var espressoPrice: Double? {
        // Look for exact "Espresso" first, then partial matches
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
    let price: Double?
    let confidence: String?
    let drinks: [DrinkPrice]?
}

private struct ErrorResponse: Decodable {
    let error: String?
    let message: String?
}

// MARK: - Errors

enum PriceExtractionError: LocalizedError {
    case imageConversionFailed
    case invalidResponse
    case authenticationFailed
    case rateLimitExceeded
    case serverError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to process the image."
        case .invalidResponse:
            return "Received invalid response from server."
        case .authenticationFailed:
            return "Authentication failed. Please sign in again."
        case .rateLimitExceeded:
            return "Too many requests. Please wait a minute before trying again."
        case .serverError(let message):
            return message
        case .networkError(let error):
            return error.localizedDescription
        }
    }
}
