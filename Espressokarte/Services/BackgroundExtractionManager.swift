//
//  BackgroundExtractionManager.swift
//  Espressokarte
//
//  Created by Claude on 15.01.26.
//

import BackgroundTasks
import Combine
import Foundation
import UIKit

/// Manages background processing of price extractions
/// Handles both foreground processing and iOS background task scheduling
@MainActor
final class BackgroundExtractionManager: ObservableObject {
    static let shared = BackgroundExtractionManager()

    /// Background task identifier - must be registered in Info.plist
    static let backgroundTaskIdentifier = "com.timokuehne.Espressokarte.priceExtraction"

    @Published private(set) var isProcessing = false
    @Published private(set) var currentProgress: String?

    private let pendingManager = PendingExtractionManager.shared
    private let priceService = PriceExtractionService.shared
    private let cloudKitManager = CloudKitManager.shared

    private var processingTask: Task<Void, Never>?

    private init() {}

    // MARK: - Background Task Registration

    /// Registers the background task handler with iOS
    /// Call this from application(_:didFinishLaunchingWithOptions:)
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let bgTask = task as? BGProcessingTask else { return }
            Task { @MainActor in
                self?.handleBackgroundTask(bgTask)
            }
        }
    }

    /// Schedules a background task to process pending extractions
    func scheduleBackgroundProcessing() {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        // Schedule to run soon
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background task scheduled")
        } catch {
            print("Failed to schedule background task: \(error)")
        }
    }

    /// Handles the background task execution
    private func handleBackgroundTask(_ task: BGProcessingTask) {
        // Schedule next task
        scheduleBackgroundProcessing()

        // Set up expiration handler
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.processingTask?.cancel()
                self?.isProcessing = false
            }
        }

        // Process pending extractions
        processingTask = Task {
            await processPendingExtractions()
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: - Foreground Processing

    /// Starts processing pending extractions in the foreground
    /// This can run while the user uses the app
    func startProcessing() {
        guard !isProcessing else { return }
        guard pendingManager.getPendingCount() > 0 else { return }

        processingTask = Task {
            await processPendingExtractions()
        }
    }

    /// Stops any ongoing processing
    func stopProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        currentProgress = nil
    }

    // MARK: - Processing Logic

    /// Processes all pending extractions sequentially
    private func processPendingExtractions() async {
        isProcessing = true

        while let extraction = pendingManager.getNextPending() {
            // Check if task was cancelled
            if Task.isCancelled { break }

            await processExtraction(extraction)

            // Small delay between extractions
            try? await Task.sleep(for: .milliseconds(500))
        }

        isProcessing = false
        currentProgress = nil
    }

    /// Processes a single extraction
    private func processExtraction(_ extraction: PendingExtraction) async {
        currentProgress = "Processing \(extraction.cafeName)..."

        // Mark as extracting
        pendingManager.markAsExtracting(extraction)

        // Load the image
        guard let image = pendingManager.loadImage(for: extraction) else {
            pendingManager.markAsFailed(extraction.id, error: "Could not load image")
            return
        }

        do {
            // Step 1: Extract prices from image
            currentProgress = "Extracting prices from menu..."
            let result = try await priceService.extractPrices(from: image)

            guard let espressoPrice = result.espressoPrice else {
                pendingManager.markAsFailed(extraction.id, error: "No espresso price found in image")
                return
            }

            // Update with results
            pendingManager.updateWithResults(extraction.id, drinks: result.drinks)

            // Step 2: Save to CloudKit
            currentProgress = "Saving to cloud..."
            let cafe = Cafe(
                id: extraction.cafeId,
                name: extraction.cafeName,
                address: extraction.cafeAddress,
                latitude: extraction.cafeLatitude,
                longitude: extraction.cafeLongitude,
                currentPrice: espressoPrice,
                priceHistory: []
            )

            let imageData = image.jpegData(compressionQuality: 0.7)
            _ = try await cloudKitManager.addOrUpdateCafe(
                cafe,
                drinks: result.drinks,
                note: nil,
                menuImageData: imageData
            )

            // Success
            pendingManager.markAsCompleted(extraction.id)
            currentProgress = nil

        } catch {
            pendingManager.markAsFailed(extraction.id, error: error.localizedDescription)
        }
    }

    // MARK: - App Lifecycle

    /// Call when app enters background to schedule processing
    func appDidEnterBackground() {
        if pendingManager.getPendingCount() > 0 {
            scheduleBackgroundProcessing()
        }
    }

    /// Call when app becomes active to process pending items
    func appDidBecomeActive() {
        pendingManager.checkForSharedExtractions()
        startProcessing()
    }
}
