//
//  AddPriceView.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 07.01.26.
//

import AVFoundation
import AuthenticationServices
import MapKit
import SwiftUI

/// View for adding a new espresso price
struct AddPriceView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var cafeSearchService = CafeSearchService.shared
    @StateObject private var cloudKitManager = CloudKitManager.shared
    @StateObject private var appleSignInManager = AppleSignInManager.shared
    @StateObject private var priceExtractionService = PriceExtractionService.shared

    @State private var selectedCafe: MapItemData?
    @State private var extractedPrice: Double?
    @State private var searchQuery = ""
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showCamera = false
    @State private var showCameraPermissionAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Selected cafe header
                if let cafe = selectedCafe {
                    SelectedCafeHeader(cafe: cafe) {
                        withAnimation {
                            selectedCafe = nil
                            extractedPrice = nil
                        }
                    }
                }

                // Price capture section (when cafe is selected)
                if selectedCafe != nil {
                    PriceCaptureSection(
                        extractedPrice: $extractedPrice,
                        isSignedIn: appleSignInManager.isSignedIn,
                        isProcessing: priceExtractionService.isProcessing,
                        onSignIn: signInWithApple,
                        onTakePhoto: checkCameraAndOpen
                    )
                    .padding()
                }

                // Cafe selection list
                if selectedCafe == nil {
                    CafeSelectionList(
                        searchQuery: $searchQuery,
                        selectedCafe: $selectedCafe,
                        cafeSearchService: cafeSearchService
                    )
                }

                Spacer()
            }
            .navigationTitle(selectedCafe == nil ? "Add Price" : "Capture Price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if selectedCafe != nil && extractedPrice != nil {
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
        .task {
            // Search for nearby cafes when view appears
            locationManager.requestLocation()

            // Wait a moment for location, then search
            try? await Task.sleep(for: .milliseconds(500))
            await cafeSearchService.searchNearbyCafes(at: locationManager.currentCoordinate)

            // Auto-select closest cafe if very close
            if let closest = cafeSearchService.closestCafe(to: locationManager.currentCoordinate) {
                let distance = cafeSearchService.distance(
                    from: locationManager.currentCoordinate,
                    to: closest.coordinate
                )
                // Auto-select if within 30 meters
                if distance < 30 {
                    selectedCafe = closest
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
        guard let cafe = selectedCafe, let price = extractedPrice else {
            return
        }

        isSaving = true

        Task {
            do {
                let cafeModel = Cafe.from(mapItem: cafe)
                _ = try await cloudKitManager.addOrUpdateCafe(cafeModel, price: price, note: nil)

                await MainActor.run {
                    isSaving = false
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

/// Header showing the selected cafe
struct SelectedCafeHeader: View {
    let cafe: MapItemData
    let onDeselect: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(cafe.name)
                    .font(.headline)
                Text(cafe.address)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onDeselect) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
}

/// Section for capturing and displaying price via camera
struct PriceCaptureSection: View {
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

                    Text("Espresso price detected")
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
                    Text("Sign in to capture prices")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Button(action: onSignIn) {
                        HStack {
                            Image(systemName: "applelogo")
                            Text("Sign in with Apple")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.black)
                        .cornerRadius(8)
                    }
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

/// List for selecting a cafe from search results
struct CafeSelectionList: View {
    @Binding var searchQuery: String
    @Binding var selectedCafe: MapItemData?
    @ObservedObject var cafeSearchService: CafeSearchService
    @StateObject private var locationManager = LocationManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search cafes", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Search for cafes")

                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding()

            // Results list
            if cafeSearchService.isSearching {
                ProgressView("Searching nearby cafes...")
                    .padding()
            } else if cafeSearchService.nearbyCafes.isEmpty {
                ContentUnavailableView(
                    "No Cafes Found",
                    systemImage: "cup.and.saucer",
                    description: Text("Try searching for a cafe by name")
                )
            } else {
                List(cafeSearchService.nearbyCafes) { cafe in
                    CafeRow(cafe: cafe, currentLocation: locationManager.currentCoordinate)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation {
                                selectedCafe = cafe
                            }
                        }
                }
                .listStyle(.plain)
            }
        }
        .onChange(of: searchQuery) { _, newValue in
            Task {
                if newValue.isEmpty {
                    await cafeSearchService.searchNearbyCafes(at: locationManager.currentCoordinate)
                } else {
                    await cafeSearchService.searchCafes(
                        query: newValue, near: locationManager.currentCoordinate)
                }
            }
        }
    }
}

/// Row displaying a cafe in the selection list
struct CafeRow: View {
    let cafe: MapItemData
    let currentLocation: CLLocationCoordinate2D

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(cafe.name)
                    .font(.headline)
                Text(cafe.address)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Distance
            if let distance = formattedDistance {
                Text(distance)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var formattedDistance: String? {
        let cafeLocation = CLLocation(latitude: cafe.latitude, longitude: cafe.longitude)
        let userLocation = CLLocation(
            latitude: currentLocation.latitude, longitude: currentLocation.longitude)
        let distance = userLocation.distance(from: cafeLocation)

        if distance < 1000 {
            return String(format: "%.0f m", distance)
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
}

#Preview {
    AddPriceView()
}
