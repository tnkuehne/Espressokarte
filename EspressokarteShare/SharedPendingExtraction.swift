//
//  SharedPendingExtraction.swift
//  EspressokarteShare
//
//  Created by Claude on 15.01.26.
//

import Foundation
import UIKit

/// Status of a pending price extraction (shared with main app)
enum SharedPendingExtractionStatus: String, Codable {
    case queued
    case extracting
    case saving
    case completed
    case failed
}

/// Source of the extraction request (shared with main app)
enum SharedExtractionSource: String, Codable {
    case mainApp
    case shareExtension
}

/// Represents a pending price extraction that can be processed by the main app
/// This is a shared model between the share extension and main app
struct SharedPendingExtraction: Codable, Identifiable {
    let id: UUID
    let createdAt: Date

    // Cafe information
    let cafeId: String
    let cafeName: String
    let cafeAddress: String
    let cafeLatitude: Double
    let cafeLongitude: Double

    // Image stored as filename
    let imageFileName: String

    // Status tracking
    var status: SharedPendingExtractionStatus
    var retryCount: Int

    // Source
    let source: SharedExtractionSource

    init(
        cafeId: String,
        cafeName: String,
        cafeAddress: String,
        cafeLatitude: Double,
        cafeLongitude: Double,
        imageFileName: String
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
        self.source = .shareExtension
    }
}

/// Manages saving pending extractions to the shared app group for the main app to process
final class SharedPendingExtractionManager {
    static let shared = SharedPendingExtractionManager()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let appGroup = "group.com.timokuehne.Espressokarte"

    private var sharedContainerURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    private var pendingExtractionsURL: URL? {
        sharedContainerURL?.appendingPathComponent("pendingExtractions.json")
    }

    private var imagesDirectory: URL? {
        guard let container = sharedContainerURL else { return nil }
        let url = container.appendingPathComponent("pendingImages", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private init() {}

    /// Queues an extraction for the main app to process
    func queueExtraction(
        cafeId: String,
        cafeName: String,
        cafeAddress: String,
        cafeLatitude: Double,
        cafeLongitude: Double,
        image: UIImage
    ) -> Bool {
        // Save image
        guard let imageFileName = saveImage(image) else {
            return false
        }

        let extraction = SharedPendingExtraction(
            cafeId: cafeId,
            cafeName: cafeName,
            cafeAddress: cafeAddress,
            cafeLatitude: cafeLatitude,
            cafeLongitude: cafeLongitude,
            imageFileName: imageFileName
        )

        // Load existing extractions
        var extractions = loadExtractions()
        extractions.append(extraction)

        // Save back
        return saveExtractions(extractions)
    }

    private func saveImage(_ image: UIImage) -> String? {
        guard let imagesDir = imagesDirectory else { return nil }

        let fileName = UUID().uuidString + ".jpg"
        let url = imagesDir.appendingPathComponent(fileName)

        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }

        do {
            try data.write(to: url)
            return fileName
        } catch {
            print("Failed to save image: \(error)")
            return nil
        }
    }

    private func loadExtractions() -> [SharedPendingExtraction] {
        guard let url = pendingExtractionsURL,
              fileManager.fileExists(atPath: url.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([SharedPendingExtraction].self, from: data)
        } catch {
            return []
        }
    }

    private func saveExtractions(_ extractions: [SharedPendingExtraction]) -> Bool {
        guard let url = pendingExtractionsURL else { return false }

        do {
            let data = try encoder.encode(extractions)
            try data.write(to: url)
            return true
        } catch {
            print("Failed to save extractions: \(error)")
            return false
        }
    }
}
