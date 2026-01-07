//
//  AddPriceView.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 07.01.26.
//

import SwiftUI
import MapKit

/// View for adding a new espresso price
struct AddPriceView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var cafeSearchService = CafeSearchService.shared
    @StateObject private var cloudKitManager = CloudKitManager.shared

    @State private var selectedCafe: MapItemData?
    @State private var priceText = ""
    @State private var note = ""
    @State private var searchQuery = ""
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    @FocusState private var isPriceFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Selected cafe header
                if let cafe = selectedCafe {
                    SelectedCafeHeader(cafe: cafe) {
                        withAnimation {
                            selectedCafe = nil
                        }
                    }
                }

                // Price input (always visible when cafe is selected)
                if selectedCafe != nil {
                    PriceInputSection(
                        priceText: $priceText,
                        note: $note,
                        isPriceFocused: $isPriceFocused
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
            .navigationTitle(selectedCafe == nil ? "Add Price" : "Enter Price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if selectedCafe != nil {
                        Button("Save") {
                            savePrice()
                        }
                        .disabled(!isValidPrice || isSaving)
                        .fontWeight(.semibold)
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
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
                    isPriceFocused = true
                }
            }
        }
        .onChange(of: selectedCafe) { _, newValue in
            if newValue != nil {
                isPriceFocused = true
            }
        }
    }

    private var isValidPrice: Bool {
        guard let price = Double(priceText.replacingOccurrences(of: ",", with: ".")) else {
            return false
        }
        return price > 0 && price < 20
    }

    private func savePrice() {
        guard let cafe = selectedCafe,
              let price = Double(priceText.replacingOccurrences(of: ",", with: ".")) else {
            return
        }

        isSaving = true

        Task {
            do {
                let cafeModel = Cafe.from(mapItem: cafe)
                let noteText = note.isEmpty ? nil : note
                _ = try await cloudKitManager.addOrUpdateCafe(cafeModel, price: price, note: noteText)

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

/// Price input section with text field and optional note
struct PriceInputSection: View {
    @Binding var priceText: String
    @Binding var note: String
    var isPriceFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 16) {
            // Price input
            HStack {
                Text("€")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("0.00", text: $priceText)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .focused(isPriceFocused)
                    .accessibilityLabel("Espresso price in euros")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(16)

            // Optional note
            TextField("Add a note (optional)", text: $note)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Optional note")
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
                    await cafeSearchService.searchCafes(query: newValue, near: locationManager.currentCoordinate)
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
        let userLocation = CLLocation(latitude: currentLocation.latitude, longitude: currentLocation.longitude)
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
