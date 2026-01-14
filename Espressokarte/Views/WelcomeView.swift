//
//  WelcomeView.swift
//  Espressokarte
//
//  Created by Timo Kuehne on 13.01.26.
//

import SwiftUI

/// Apple-style welcome/onboarding screen shown on first launch
struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App icon and welcome title
            VStack(spacing: 16) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.brown)

                Text("Welcome to\nEspressokarte")
                    .font(.system(size: 36, weight: .bold))
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 48)

            // Feature list
            VStack(spacing: 28) {
                WelcomeFeatureRow(
                    icon: "mappin.and.ellipse",
                    iconColor: .blue,
                    title: "Discover Prices",
                    description: "Browse cafes on the map and see current espresso prices at a glance."
                )

                WelcomeFeatureRow(
                    icon: "camera.fill",
                    iconColor: .orange,
                    title: "Add Prices at the Cafe",
                    description: "When you're at a cafe, snap a photo of the menu to add or update prices."
                )

                WelcomeFeatureRow(
                    icon: "cup.and.saucer",
                    iconColor: Color(red: 0.722, green: 0.463, blue: 0.318),
                    title: "Filter by Drink",
                    description: "See prices for espresso, cappuccino, and other drinks by tapping the filter."
                )

                WelcomeFeatureRow(
                    icon: "clock.arrow.circlepath",
                    iconColor: .purple,
                    title: "Track Price History",
                    description: "Tap any cafe to see its full price history and when it was last updated."
                )
            }
            .padding(.horizontal, 24)

            Spacer()
            Spacer()

            // Continue button
            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

/// Individual feature row in the welcome screen
struct WelcomeFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon in a rounded square
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(iconColor)
            }

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))

                Text(description)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

#Preview {
    WelcomeView {
        print("Continue tapped")
    }
}
