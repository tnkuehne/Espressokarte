//
//  PendingExtractionManager.swift
//  Espressokarte
//
//  Created by Claude on 15.01.26.
//

import Combine
import Foundation
import UIKit

/// Manages the queue of pending price extractions
/// Handles persistence, image storage, and status updates
@MainActor
final class PendingExtractionManager: ObservableObject {
    static let shared = PendingExtractionManager()

    @Published private(set) var pendingExtractions: [PendingExtraction] = []
    @Published private(set) var activeExtraction: PendingExtraction?

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // Storage paths
    private var pendingExtractionsURL: URL {
        getDocumentsDirectory().appendingPathComponent("pendingExtractions.json")
    }

    private var imagesDirectory: URL {
        let url = getDocumentsDirectory().appendingPathComponent("pendingImages", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // App group for sharing with share extension
    private let appGroup = "group.com.timokuehne.Espressokarte"

    private var sharedContainerURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    private var sharedPendingExtractionsURL: URL? {
        sharedContainerURL?.appendingPathComponent("pendingExtractions.json")
    }

    private var sharedImagesDirectory: URL? {
        guard let container = sharedContainerURL else { return nil }
        let url = container.appendingPathComponent("pendingImages", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private init() {
        loadPendingExtractions()
        importFromShareExtension()
    }

    // MARK: - Documents Directory

    private func getDocumentsDirectory() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Queue Management

    /// Adds a new extraction to the queue
    /// - Parameters:
    ///   - cafe: The cafe data from map selection
    ///   - image: The captured menu image
    ///   - source: Where the extraction originated
    /// - Returns: The created pending extraction
    @discardableResult
    func queueExtraction(
        cafeId: String,
        cafeName: String,
        cafeAddress: String,
        cafeLatitude: Double,
        cafeLongitude: Double,
        image: UIImage,
        source: ExtractionSource = .mainApp
    ) -> PendingExtraction? {
        // Save image to disk
        guard let imageFileName = saveImage(image) else {
            print("Failed to save image for pending extraction")
            return nil
        }

        let extraction = PendingExtraction(
            cafeId: cafeId,
            cafeName: cafeName,
            cafeAddress: cafeAddress,
            cafeLatitude: cafeLatitude,
            cafeLongitude: cafeLongitude,
            imageFileName: imageFileName,
            source: source
        )

        pendingExtractions.append(extraction)
        savePendingExtractions()

        return extraction
    }

    /// Removes a completed or cancelled extraction
    func removeExtraction(_ extraction: PendingExtraction) {
        // Remove the image file
        deleteImage(fileName: extraction.imageFileName)

        // Remove from list
        pendingExtractions.removeAll { $0.id == extraction.id }
        savePendingExtractions()
    }

    /// Marks an extraction as currently processing
    func markAsExtracting(_ extraction: PendingExtraction) {
        updateExtraction(extraction.id) { ext in
            ext.status = .extracting
            ext.lastAttempt = Date()
        }
        activeExtraction = pendingExtractions.first { $0.id == extraction.id }
    }

    /// Updates extraction with results
    func updateWithResults(_ extractionId: UUID, drinks: [DrinkPrice]) {
        updateExtraction(extractionId) { ext in
            ext.extractedDrinks = drinks
            ext.status = .saving
        }
    }

    /// Marks extraction as completed
    func markAsCompleted(_ extractionId: UUID) {
        if let extraction = pendingExtractions.first(where: { $0.id == extractionId }) {
            removeExtraction(extraction)
        }
        if activeExtraction?.id == extractionId {
            activeExtraction = nil
        }
    }

    /// Marks extraction as failed
    func markAsFailed(_ extractionId: UUID, error: String) {
        updateExtraction(extractionId) { ext in
            ext.status = .failed
            ext.lastError = error
            ext.retryCount += 1
        }
        if activeExtraction?.id == extractionId {
            activeExtraction = nil
        }
    }

    /// Resets a failed extraction for retry
    func resetForRetry(_ extractionId: UUID) {
        updateExtraction(extractionId) { ext in
            ext.status = .queued
            ext.lastError = nil
        }
    }

    /// Gets the next extraction to process
    func getNextPending() -> PendingExtraction? {
        pendingExtractions.first { $0.status == .queued }
    }

    /// Gets all extractions that need processing
    func getPendingCount() -> Int {
        pendingExtractions.filter { $0.status == .queued || $0.status == .failed && $0.canRetry }.count
    }

    /// Loads the image for an extraction
    func loadImage(for extraction: PendingExtraction) -> UIImage? {
        let url = imagesDirectory.appendingPathComponent(extraction.imageFileName)
        guard let data = try? Data(contentsOf: url) else {
            // Try shared container
            if let sharedURL = sharedImagesDirectory?.appendingPathComponent(extraction.imageFileName),
               let sharedData = try? Data(contentsOf: sharedURL) {
                return UIImage(data: sharedData)
            }
            return nil
        }
        return UIImage(data: data)
    }

    // MARK: - Private Helpers

    private func updateExtraction(_ id: UUID, update: (inout PendingExtraction) -> Void) {
        guard let index = pendingExtractions.firstIndex(where: { $0.id == id }) else { return }
        update(&pendingExtractions[index])
        savePendingExtractions()
    }

    private func saveImage(_ image: UIImage) -> String? {
        let fileName = UUID().uuidString + ".jpg"
        let url = imagesDirectory.appendingPathComponent(fileName)

        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }

        do {
            try data.write(to: url)
            return fileName
        } catch {
            print("Failed to save image: \(error)")
            return nil
        }
    }

    private func deleteImage(fileName: String) {
        let url = imagesDirectory.appendingPathComponent(fileName)
        try? fileManager.removeItem(at: url)

        // Also try shared container
        if let sharedURL = sharedImagesDirectory?.appendingPathComponent(fileName) {
            try? fileManager.removeItem(at: sharedURL)
        }
    }

    // MARK: - Persistence

    private func savePendingExtractions() {
        do {
            let data = try encoder.encode(pendingExtractions)
            try data.write(to: pendingExtractionsURL)
        } catch {
            print("Failed to save pending extractions: \(error)")
        }
    }

    private func loadPendingExtractions() {
        guard fileManager.fileExists(atPath: pendingExtractionsURL.path) else { return }

        do {
            let data = try Data(contentsOf: pendingExtractionsURL)
            pendingExtractions = try decoder.decode([PendingExtraction].self, from: data)
        } catch {
            print("Failed to load pending extractions: \(error)")
        }
    }

    // MARK: - Share Extension Import

    /// Shared extraction model format (from share extension)
    private struct SharedPendingExtraction: Codable {
        let id: UUID
        let createdAt: Date
        let cafeId: String
        let cafeName: String
        let cafeAddress: String
        let cafeLatitude: Double
        let cafeLongitude: Double
        let imageFileName: String
        let status: String
        let retryCount: Int
        let source: String
    }

    /// Imports pending extractions created by the share extension
    private func importFromShareExtension() {
        guard let sharedURL = sharedPendingExtractionsURL,
              fileManager.fileExists(atPath: sharedURL.path) else { return }

        do {
            let data = try Data(contentsOf: sharedURL)
            let sharedExtractions = try decoder.decode([SharedPendingExtraction].self, from: data)

            // Import images from shared container
            for shared in sharedExtractions {
                if let sharedImgDir = sharedImagesDirectory {
                    let sourceURL = sharedImgDir.appendingPathComponent(shared.imageFileName)
                    let destURL = imagesDirectory.appendingPathComponent(shared.imageFileName)

                    if fileManager.fileExists(atPath: sourceURL.path) {
                        try? fileManager.copyItem(at: sourceURL, to: destURL)
                        try? fileManager.removeItem(at: sourceURL)
                    }
                }

                // Convert to main app format and add if not already present
                if !pendingExtractions.contains(where: { $0.id == shared.id }) {
                    let extraction = PendingExtraction(
                        cafeId: shared.cafeId,
                        cafeName: shared.cafeName,
                        cafeAddress: shared.cafeAddress,
                        cafeLatitude: shared.cafeLatitude,
                        cafeLongitude: shared.cafeLongitude,
                        imageFileName: shared.imageFileName,
                        source: .shareExtension
                    )
                    pendingExtractions.append(extraction)
                }
            }

            // Clear shared extractions
            try? fileManager.removeItem(at: sharedURL)

            savePendingExtractions()
        } catch {
            print("Failed to import from share extension: \(error)")
        }
    }

    /// Call this when app becomes active to check for new share extension items
    func checkForSharedExtractions() {
        importFromShareExtension()
    }
}
