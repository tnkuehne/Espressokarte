//
//  CafeDetailView.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 07.01.26.
//

import AVFoundation
import AuthenticationServices
import MapKit
import SwiftUI

/// Detailed view of a cafe showing current price and history
struct CafeDetailView: View {
    @State private var cafe: Cafe
    var onPriceUpdated: ((Cafe) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationManager = LocationManager.shared

    @State private var showUpdatePrice = false

    init(cafe: Cafe, onPriceUpdated: ((Cafe) -> Void)? = nil) {
        self._cafe = State(initialValue: cafe)
        self.onPriceUpdated = onPriceUpdated
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header with price
                    CafeDetailHeader(cafe: cafe)

                    // Map preview
                    CafeMapPreview(cafe: cafe)

                    // Address and distance
                    CafeLocationInfo(
                        cafe: cafe,
                        distance: locationManager.formattedDistance(to: cafe.coordinate)
                    )

                    // Latest update info
                    if let latestRecord = cafe.latestPriceRecord {
                        LatestUpdateCard(record: latestRecord)
                    }

                    // Price history
                    if !cafe.priceHistory.isEmpty {
                        PriceHistorySection(priceHistory: cafe.priceHistory)
                    }

                    // Update price button
                    Button(action: { showUpdatePrice = true }) {
                        Label("Update Price", systemImage: "pencil")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .accessibilityLabel("Update espresso price")
                }
                .padding(.bottom, 20)
            }
            .navigationTitle(cafe.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showUpdatePrice) {
                UpdatePriceView(
                    cafe: cafe,
                    onPriceUpdated: { updatedCafe in
                        self.cafe = updatedCafe
                        self.onPriceUpdated?(updatedCafe)
                    })
            }
        }
    }
}

/// Header showing the cafe name and current price
struct CafeDetailHeader: View {
    let cafe: Cafe

    var body: some View {
        VStack(spacing: 12) {
            // Large price display
            if let price = cafe.formattedPrice {
                Text(price)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(priceColor)
            } else {
                Text("No price")
                    .font(.title)
                    .foregroundColor(.secondary)
            }

            Text("Espresso")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.systemGray6))
    }

    private var priceColor: Color {
        guard let price = cafe.currentPrice else { return .gray }

        switch price {
        case ..<2.0: return .green
        case 2.0..<2.50: return .blue
        case 2.50..<3.0: return .orange
        default: return .red
        }
    }
}

/// Mini map showing cafe location
struct CafeMapPreview: View {
    let cafe: Cafe

    var body: some View {
        Map(
            initialPosition: .region(
                MKCoordinateRegion(
                    center: cafe.coordinate,
                    latitudinalMeters: 500,
                    longitudinalMeters: 500
                ))
        ) {
            Marker(cafe.name, coordinate: cafe.coordinate)
                .tint(.blue)
        }
        .mapStyle(.standard)
        .frame(height: 150)
        .cornerRadius(12)
        .padding(.horizontal)
        .disabled(true)
    }
}

/// Address and distance info
struct CafeLocationInfo: View {
    let cafe: Cafe
    let distance: String?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label(cafe.address, systemImage: "mappin")
                    .font(.subheadline)

                if let distance = distance {
                    Label(distance, systemImage: "figure.walk")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Open in Maps button
            Button(action: openInMaps) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .accessibilityLabel("Open in Maps")
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func openInMaps() {
        let location = CLLocation(
            latitude: cafe.coordinate.latitude, longitude: cafe.coordinate.longitude)
        let mapItem = MKMapItem(location: location, address: nil)
        mapItem.name = cafe.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
}

/// Card showing who last updated the price
struct LatestUpdateCard: View {
    let record: PriceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title3)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Added by \(record.addedByName)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(record.relativeDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            if let note = record.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.leading, 32)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

/// Section showing price history
struct PriceHistorySection: View {
    let priceHistory: [PriceRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Price History")
                .font(.headline)
                .padding(.horizontal)

            ForEach(priceHistory.sorted(by: { $0.date > $1.date })) { record in
                PriceHistoryRow(record: record)
            }
        }
    }
}

/// Single row in price history
struct PriceHistoryRow: View {
    let record: PriceRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.formattedDate)
                    .font(.subheadline)

                Text("by \(record.addedByName)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let note = record.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }

            Spacer()

            Text(record.formattedPrice)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

/// View for updating an existing cafe's price using camera
struct UpdatePriceView: View {
    let cafe: Cafe
    var onPriceUpdated: ((Cafe) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var cloudKitManager = CloudKitManager.shared
    @StateObject private var appleSignInManager = AppleSignInManager.shared
    @StateObject private var priceExtractionService = PriceExtractionService.shared

    @State private var extractedPrice: Double?
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showCamera = false
    @State private var showCameraPermissionAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Cafe name
                Text(cafe.name)
                    .font(.headline)
                    .foregroundColor(.secondary)

                // Current price reference
                if let currentPrice = cafe.formattedPrice {
                    Text("Current: \(currentPrice)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Price capture section
                UpdatePriceCaptureSection(
                    extractedPrice: $extractedPrice,
                    isSignedIn: appleSignInManager.isSignedIn,
                    isProcessing: priceExtractionService.isProcessing,
                    onSignIn: signInWithApple,
                    onTakePhoto: checkCameraAndOpen
                )
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Update Price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if extractedPrice != nil {
                        Button("Save") {
                            savePrice()
                        }
                        .disabled(isSaving)
                        .fontWeight(.semibold)
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .alert("Camera Access Required", isPresented: $showCameraPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please enable camera access in Settings to photograph menu prices.")
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    extractPriceFromImage(image)
                }
            }
            .overlay {
                if isSaving {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView("Saving...")
                        .padding()
                        .background(.ultraThickMaterial)
                        .cornerRadius(12)
                }
            }
        }
    }

    private func signInWithApple() {
        Task {
            do {
                _ = try await appleSignInManager.signIn()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func checkCameraAndOpen() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted {
                    showCamera = true
                }
            }
        case .denied, .restricted:
            showCameraPermissionAlert = true
        @unknown default:
            showCameraPermissionAlert = true
        }
    }

    private func extractPriceFromImage(_ image: UIImage) {
        Task {
            do {
                let price = try await priceExtractionService.extractPrice(from: image)
                if let price = price {
                    extractedPrice = price
                } else {
                    errorMessage = "Could not find espresso price in the image. Please try again."
                    showError = true
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func savePrice() {
        guard let price = extractedPrice else { return }

        isSaving = true

        Task {
            do {
                let updatedCafe = try await cloudKitManager.addOrUpdateCafe(
                    cafe, price: price, note: nil)

                await MainActor.run {
                    isSaving = false
                    onPriceUpdated?(updatedCafe)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

/// Section for capturing price via camera in update view
struct UpdatePriceCaptureSection: View {
    @Binding var extractedPrice: Double?
    let isSignedIn: Bool
    let isProcessing: Bool
    let onSignIn: () -> Void
    let onTakePhoto: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            if isProcessing {
                // Loading state
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Extracting price...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if let price = extractedPrice {
                // Price found - display it
                VStack(spacing: 8) {
                    Text(String(format: "%.2f", price))
                        .font(.system(size: 64, weight: .bold, design: .rounded))

                    Text("New price detected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color(.systemGray6))
                .cornerRadius(16)

                // Option to retake
                Button {
                    onTakePhoto()
                } label: {
                    Label("Take New Photo", systemImage: "camera")
                        .font(.subheadline)
                }
            } else if !isSignedIn {
                // Not signed in - show sign in button
                VStack(spacing: 16) {
                    Text("Sign in to update prices")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    SignInWithAppleButton(.signIn) { _ in
                    } onCompletion: { _ in
                        onSignIn()
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(8)
                }
                .padding(.vertical, 20)
            } else {
                // Signed in, ready to capture
                Button {
                    onTakePhoto()
                } label: {
                    Label("Take Photo of Menu", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
    }
}

#Preview {
    CafeDetailView(
        cafe: Cafe(
            id: "preview-1",
            name: "Test Cafe",
            address: "Marienplatz 1, 80331 Munich",
            latitude: 48.1371,
            longitude: 11.5754,
            currentPrice: 2.80,
            priceHistory: [
                PriceRecord(
                    price: 2.80,
                    date: Date(),
                    addedBy: "user1",
                    addedByName: "Max",
                    note: "Great espresso!"
                ),
                PriceRecord(
                    price: 2.50,
                    date: Date().addingTimeInterval(-86400 * 30),
                    addedBy: "user2",
                    addedByName: "Anna",
                    note: nil
                ),
            ]
        ))
}
