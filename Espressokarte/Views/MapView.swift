//
//  MapView.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 07.01.26.
//

import SwiftUI
import MapKit

/// Main map view showing cafes with espresso prices
struct MapView: View {
    @StateObject private var cloudKitManager = CloudKitManager.shared
    @StateObject private var locationManager = LocationManager.shared

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedCafe: Cafe?
    @State private var showAddPrice = false
    @State private var showCafeDetail = false

    // Munich center coordinates
    private let munichCenter = CLLocationCoordinate2D(latitude: 48.1351, longitude: 11.5820)

    var body: some View {
        ZStack {
            // Map with cafe annotations
            Map(position: $cameraPosition, selection: $selectedCafe) {
                // User location
                UserAnnotation()

                // Cafe markers with prices
                ForEach(cloudKitManager.cafes) { cafe in
                    Annotation(
                        cafe.name,
                        coordinate: cafe.coordinate,
                        anchor: .bottom
                    ) {
                        CafePriceMarker(cafe: cafe)
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

            // Floating add button
            VStack {
                Spacer()

                HStack {
                    Spacer()

                    Button(action: {
                        showAddPrice = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.white, .blue)
                            .shadow(radius: 4)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 30)
                    .accessibilityLabel("Add espresso price")
                }
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
            AddPriceView()
        }
        .onChange(of: showAddPrice) { _, isShowing in
            if !isShowing {
                // Refresh cafes when add price sheet is dismissed
                Task {
                    await cloudKitManager.fetchAllCafes()
                }
            }
        }
        .sheet(isPresented: $showCafeDetail) {
            if let cafe = selectedCafe {
                CafeDetailView(cafe: cafe, onPriceUpdated: { updatedCafe in
                    cloudKitManager.updateLocalCafe(updatedCafe)
                })
                .onDisappear {
                    selectedCafe = nil
                }
            }
        }
        .task {
            // Request location permission
            locationManager.requestPermission()

            // Fetch user identity
            await cloudKitManager.fetchUserIdentity()

            // Fetch all cafes
            await cloudKitManager.fetchAllCafes()

            // Set up CloudKit subscription
            await cloudKitManager.setupSubscription()

            // Center on user location or Munich
            updateCameraPosition()
        }
        .refreshable {
            await cloudKitManager.fetchAllCafes()
        }
    }

    private func updateCameraPosition() {
        let center = locationManager.currentLocation?.coordinate ?? munichCenter
        cameraPosition = .region(MKCoordinateRegion(
            center: center,
            latitudinalMeters: 2000,
            longitudinalMeters: 2000
        ))
    }
}

/// Custom marker showing the espresso price
struct CafePriceMarker: View {
    let cafe: Cafe

    var body: some View {
        VStack(spacing: 0) {
            // Price bubble
            Text(cafe.formattedPrice ?? "?")
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

    /// Color based on price (green = cheap, red = expensive)
    private var priceColor: Color {
        guard let price = cafe.currentPrice else {
            return .gray
        }

        switch price {
        case ..<2.0:
            return .green
        case 2.0..<2.50:
            return .blue
        case 2.50..<3.0:
            return .orange
        default:
            return .red
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
