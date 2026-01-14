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

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedCafe: Cafe?
    @State private var showAddPrice = false
    @State private var showCafeDetail = false
    @State private var shouldRefreshAfterAdd = false
    @State private var showDrinkFilter = false

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

#Preview {
    MapView()
}
