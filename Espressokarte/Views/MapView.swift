//
//  MapView.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 07.01.26.
//

import MapKit
import SwiftUI

/// Main map view showing cafes with espresso prices
struct MapView: View {
    @StateObject private var cloudKitManager = CloudKitManager.shared
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var drinkFilter = DrinkFilterManager.shared
    @StateObject private var pendingExtractionManager = PendingExtractionManager.shared
    @StateObject private var backgroundExtractionManager = BackgroundExtractionManager.shared

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedCafe: Cafe?
    @State private var showAddPrice = false
    @State private var showCafeDetail = false
    @State private var shouldRefreshAfterAdd = false
    @State private var showDrinkFilter = false
    @State private var showPendingExtractions = false

    /// Cafes filtered to only those that have the selected drink
    private var filteredCafes: [Cafe] {
        cloudKitManager.cafes.filter { cafe in
            cafe.price(for: drinkFilter.selectedDrink) != nil
        }
    }

    var body: some View {
        ZStack {
            // Map with cafe annotations
            Map(position: $cameraPosition, selection: $selectedCafe) {
                // User location
                UserAnnotation()

                // Cafe markers with prices - only show cafes that have the selected drink
                ForEach(filteredCafes) { cafe in
                    Annotation(
                        cafe.name,
                        coordinate: cafe.coordinate,
                        anchor: .bottom
                    ) {
                        CafePriceMarker(
                            cafe: cafe,
                            drinkName: drinkFilter.selectedDrink,
                            priceStats: drinkFilter.currentDrinkStats
                        )
                    }
                    .tag(cafe)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onChange(of: selectedCafe) { _, newValue in
                if newValue != nil {
                    showCafeDetail = true
                }
            }

            // Floating buttons
            VStack {
                Spacer()

                HStack(alignment: .bottom) {
                    // Drink filter pill - bottom left
                    Button(action: { showDrinkFilter = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 14))
                            Text(drinkFilter.selectedDrink)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        .shadow(radius: 2)
                    }
                    .accessibilityLabel("Filter by drink type")

                    Spacer()

                    // Add button - bottom right
                    Button(action: {
                        showAddPrice = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.white, .blue)
                            .shadow(radius: 4)
                    }
                    .accessibilityLabel("Add espresso price")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }

            // Loading indicator
            if cloudKitManager.isLoading {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    Spacer()
                }
                .padding(.top, 100)
            }

            // Pending extractions status banner
            if !pendingExtractionManager.pendingExtractions.isEmpty {
                VStack {
                    PendingExtractionsStatusView(
                        pendingCount: pendingExtractionManager.pendingExtractions.count,
                        isProcessing: backgroundExtractionManager.isProcessing,
                        currentProgress: backgroundExtractionManager.currentProgress
                    )
                    .onTapGesture {
                        showPendingExtractions = true
                    }
                    Spacer()
                }
                .padding(.top, 60)
            }
        }
        .sheet(isPresented: $showAddPrice) {
            AddPriceView(onPriceSaved: {
                shouldRefreshAfterAdd = true
            })
        }
        .onChange(of: showAddPrice) { _, isShowing in
            if !isShowing && shouldRefreshAfterAdd {
                // Refresh cafes only when a price was actually saved
                shouldRefreshAfterAdd = false
                Task {
                    await cloudKitManager.fetchAllCafes()
                }
            }
        }
        .sheet(isPresented: $showCafeDetail) {
            if let cafe = selectedCafe {
                CafeDetailView(
                    cafe: cafe,
                    onPriceUpdated: { updatedCafe in
                        cloudKitManager.updateLocalCafe(updatedCafe)
                    }
                )
                .onDisappear {
                    selectedCafe = nil
                }
            }
        }
        .sheet(isPresented: $showDrinkFilter) {
            DrinkFilterSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPendingExtractions) {
            PendingExtractionsListView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: cloudKitManager.cafes) { _, cafes in
            drinkFilter.updateAvailableDrinks(from: cafes)
        }
        .task {
            // Request location permission
            locationManager.requestPermission()

            // Fetch user identity
            await cloudKitManager.fetchUserIdentity()

            // Fetch all cafes
            await cloudKitManager.fetchAllCafes()
            
            // Update available drinks from fetched cafes
            drinkFilter.updateAvailableDrinks(from: cloudKitManager.cafes)

            // Set up CloudKit subscription
            await cloudKitManager.setupSubscription()
        }
        .refreshable {
            await cloudKitManager.fetchAllCafes()
        }
        .onAppear {
            // Update drinks from cached cafes immediately
            drinkFilter.updateAvailableDrinks(from: cloudKitManager.cafes)
        }
    }
}

/// Custom marker showing the drink price
struct CafePriceMarker: View {
    let cafe: Cafe
    var drinkName: String = "Espresso"
    var priceStats: DrinkPriceStats?

    /// Price for the specific drink only - no fallback
    private var displayPrice: String {
        cafe.formattedPrice(for: drinkName) ?? "?"
    }

    /// Numeric price for the specific drink only - no fallback
    private var numericPrice: Double? {
        cafe.price(for: drinkName)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Price bubble
            Text(displayPrice)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(priceColor)
                .cornerRadius(12)

            // Triangle pointer
            Triangle()
                .fill(priceColor)
                .frame(width: 12, height: 8)
        }
        .shadow(radius: 2)
    }

    /// Color palette for price categories (coffee-inspired earthy palette)
    private static let categoryColors: [Color] = [
        Color(red: 0.545, green: 0.604, blue: 0.482),  // Sage #8B9A7B - cheap
        Color(red: 0.769, green: 0.584, blue: 0.416),  // Caramel #C4956A - medium
        Color(red: 0.722, green: 0.463, blue: 0.318),  // Terracotta #B87651 - expensive
        Color(red: 0.365, green: 0.251, blue: 0.216)   // Espresso #5D4037 - very expensive
    ]

    /// Color based on price relative to the drink's price range
    private var priceColor: Color {
        guard let price = numericPrice else {
            return Color(red: 0.55, green: 0.55, blue: 0.55)  // Warm gray for no price
        }

        // Use dynamic price stats if available
        if let stats = priceStats {
            let category = stats.category(for: price)
            return Self.categoryColors[category]
        }

        // Fallback to hardcoded ranges only if no stats available
        switch price {
        case ..<2.0:
            return Self.categoryColors[0]
        case 2.0..<2.50:
            return Self.categoryColors[1]
        case 2.50..<3.0:
            return Self.categoryColors[2]
        default:
            return Self.categoryColors[3]
        }
    }
}

/// Sheet for selecting drink filter
struct DrinkFilterSheet: View {
    @StateObject private var drinkFilter = DrinkFilterManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List(drinkFilter.availableDrinks, id: \.self) { drink in
                Button {
                    drinkFilter.selectedDrink = drink
                    dismiss()
                } label: {
                    HStack {
                        Text(drink)
                            .foregroundColor(.primary)
                        Spacer()
                        if drink == drinkFilter.selectedDrink {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Show Prices For")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Triangle shape for marker pointer
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Status banner for pending extractions
struct PendingExtractionsStatusView: View {
    let pendingCount: Int
    let isProcessing: Bool
    let currentProgress: String?

    var body: some View {
        HStack(spacing: 8) {
            if isProcessing {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "clock.fill")
                    .foregroundColor(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isProcessing ? "Processing..." : "\(pendingCount) pending")
                    .font(.system(size: 13, weight: .semibold))

                if let progress = currentProgress {
                    Text(progress)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .shadow(radius: 2)
    }
}

/// List view showing all pending extractions
struct PendingExtractionsListView: View {
    @StateObject private var pendingManager = PendingExtractionManager.shared
    @StateObject private var backgroundManager = BackgroundExtractionManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if pendingManager.pendingExtractions.isEmpty {
                    ContentUnavailableView(
                        "No Pending Extractions",
                        systemImage: "checkmark.circle",
                        description: Text("All price extractions have been processed")
                    )
                } else {
                    ForEach(pendingManager.pendingExtractions) { extraction in
                        PendingExtractionRow(extraction: extraction)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let extraction = pendingManager.pendingExtractions[index]
                            pendingManager.removeExtraction(extraction)
                        }
                    }
                }
            }
            .navigationTitle("Pending Extractions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                if !pendingManager.pendingExtractions.isEmpty && !backgroundManager.isProcessing {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Process Now") {
                            backgroundManager.startProcessing()
                        }
                    }
                }
            }
        }
    }
}

/// Row showing a single pending extraction
struct PendingExtractionRow: View {
    let extraction: PendingExtraction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(extraction.cafeName)
                    .font(.headline)
                Text(extraction.cafeAddress)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    statusIcon
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(statusColor)
                }
            }

            Spacer()

            if extraction.status == .failed, let error = extraction.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
                    .frame(maxWidth: 100)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: some View {
        Group {
            switch extraction.status {
            case .queued:
                Image(systemName: "clock")
            case .extracting:
                ProgressView().scaleEffect(0.6)
            case .saving:
                ProgressView().scaleEffect(0.6)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
            }
        }
        .foregroundColor(statusColor)
    }

    private var statusText: String {
        switch extraction.status {
        case .queued:
            return "Waiting..."
        case .extracting:
            return "Extracting prices..."
        case .saving:
            return "Saving..."
        case .completed:
            return "Completed"
        case .failed:
            return "Failed (retry \(extraction.retryCount)/\(PendingExtraction.maxRetries))"
        }
    }

    private var statusColor: Color {
        switch extraction.status {
        case .queued:
            return .orange
        case .extracting, .saving:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}

#Preview {
    MapView()
}
