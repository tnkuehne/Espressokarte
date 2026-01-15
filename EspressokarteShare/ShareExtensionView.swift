//
//  ShareExtensionView.swift
//  EspressokarteShare
//
//  Created by Claude on 10.01.26.
//

import SwiftUI

/// Main view for the share extension
struct ShareExtensionView: View {
    @ObservedObject var viewModel: ShareExtensionViewModel
    let onComplete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Import Price")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView(message: "Starting...")

        case .notSignedIn:
            NotSignedInView(onSignIn: {
                Task { await viewModel.signIn() }
            })

        case .parsingURL:
            LoadingStateView(message: "Reading Google Maps link...")

        case .fetchingImage:
            FetchingImageView(placeName: viewModel.photoData?.placeName)

        case .selectingCafe:
            CafeSelectionView(
                cafes: viewModel.matchingCafes,
                placeName: viewModel.photoData?.placeName ?? "",
                onSelect: { viewModel.selectCafe($0) }
            )

        case .queuing:
            LoadingStateView(message: "Queuing...")

        case .queued:
            QueuedView(onComplete: onComplete)

        case .error(let message):
            ErrorView(
                message: message,
                onRetry: { Task { await viewModel.retry() } },
                onCancel: onCancel
            )
        }
    }
}

// MARK: - State Views

struct LoadingStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text(message)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NotSignedInView: View {
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Sign In Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Sign in with Apple to import espresso prices.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: onSignIn) {
                HStack(spacing: 8) {
                    Image(systemName: "applelogo")
                    Text("Sign in with Apple")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(height: 50)
                .frame(maxWidth: 280)
                .background(Color.black)
                .cornerRadius(8)
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FetchingImageView: View {
    let placeName: String?

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Fetching menu image...")
                .foregroundColor(.secondary)
            if let name = placeName {
                Text(name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CafeSelectionView: View {
    let cafes: [ShareCafeData]
    let placeName: String
    let onSelect: (ShareCafeData) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select Matching Cafe")
                    .font(.headline)

                Text(
                    "Found \"\(placeName)\" on Google Maps. Select the matching Apple Maps location:"
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .padding()

            List(cafes) { cafe in
                Button {
                    onSelect(cafe)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cafe.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(cafe.address)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Something Went Wrong")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 16) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("Try Again") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct QueuedView: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "clock.badge.checkmark.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            Text("Queued for Processing")
                .font(.title2)
                .fontWeight(.semibold)

            Text("The price will be extracted when you open Espressokarte. You'll see it in \"Pending Extractions\".")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Done") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
