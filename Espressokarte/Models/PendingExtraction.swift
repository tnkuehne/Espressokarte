//
//  PendingExtraction.swift
//  Espressokarte
//
//  Created by Claude on 15.01.26.
//

import Foundation

/// Status of a pending price extraction
enum PendingExtractionStatus: String, Codable {
    case queued          // Waiting to start
    case extracting      // Currently extracting prices from image
    case saving          // Extracted, now saving to CloudKit
    case completed       // Successfully saved
    case failed          // Failed after retries
}

/// Represents a pending price extraction that can be processed in the background
struct PendingExtraction: Codable, Identifiable {
    let id: UUID
    let createdAt: Date

    // Cafe information
    let cafeId: String
    let cafeName: String
    let cafeAddress: String
    let cafeLatitude: Double
    let cafeLongitude: Double

    // Image stored as filename (saved separately to disk)
    let imageFileName: String

    // Extraction results (populated after extraction completes)
    var extractedDrinks: [DrinkPrice]?

    // Status tracking
    var status: PendingExtractionStatus
    var lastError: String?
    var retryCount: Int
    var lastAttempt: Date?

    // Source of the extraction
    let source: ExtractionSource

    init(
        cafeId: String,
        cafeName: String,
        cafeAddress: String,
        cafeLatitude: Double,
        cafeLongitude: Double,
        imageFileName: String,
        source: ExtractionSource = .mainApp
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.cafeId = cafeId
        self.cafeName = cafeName
        self.cafeAddress = cafeAddress
        self.cafeLatitude = cafeLatitude
        self.cafeLongitude = cafeLongitude
        self.imageFileName = imageFileName
        self.status = .queued
        self.retryCount = 0
        self.source = source
    }

    /// Maximum number of retry attempts
    static let maxRetries = 3

    /// Whether this extraction can be retried
    var canRetry: Bool {
        status == .failed && retryCount < Self.maxRetries
    }
}

/// Source of the extraction request
enum ExtractionSource: String, Codable {
    case mainApp
    case shareExtension
}
