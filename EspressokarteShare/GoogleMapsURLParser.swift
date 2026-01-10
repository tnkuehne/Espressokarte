//
//  GoogleMapsURLParser.swift
//  EspressokarteShare
//
//  Created by Claude on 10.01.26.
//

import CoreLocation
import Foundation

/// Data extracted from a Google Maps photo URL
struct GoogleMapsPhotoData {
    let imageURL: URL
    let coordinate: CLLocationCoordinate2D
    let placeName: String
    let imageWidth: Int?
    let imageHeight: Int?
}

/// Errors that can occur when parsing Google Maps URLs
enum GoogleMapsURLParserError: LocalizedError {
    case invalidURL
    case notGoogleMapsURL
    case notPhotoURL
    case missingImageData
    case missingCoordinates
    case missingPlaceName
    case shortURLResolutionFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL format."
        case .notGoogleMapsURL:
            return "This is not a Google Maps link."
        case .notPhotoURL:
            return "This link doesn't contain a photo."
        case .missingImageData:
            return "Could not find the photo in this link."
        case .missingCoordinates:
            return "Could not find location coordinates."
        case .missingPlaceName:
            return "Could not find the place name."
        case .shortURLResolutionFailed:
            return "Could not resolve the shortened link."
        }
    }
}

/// Parses Google Maps URLs to extract photo data, coordinates, and place information
final class GoogleMapsURLParser {

    init() {}

    /// Resolves a short URL (maps.app.goo.gl) to the full Google Maps URL
    func resolveShortURL(_ shortURL: URL) async throws -> URL {
        // Create a request that follows redirects
        var request = URLRequest(url: shortURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        // Use a custom session that doesn't follow redirects automatically
        // so we can capture the final URL
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config)

        let (_, response) = try await session.data(for: request)

        // The response.url should be the final resolved URL after redirects
        guard let finalURL = response.url,
            finalURL.host?.contains("google.com") == true
        else {
            throw GoogleMapsURLParserError.shortURLResolutionFailed
        }

        return finalURL
    }

    /// Parses a full Google Maps URL to extract photo data
    func parse(_ url: URL) throws -> GoogleMapsPhotoData {
        let urlString = url.absoluteString

        // Validate it's a Google Maps URL
        guard urlString.contains("google.com/maps") else {
            throw GoogleMapsURLParserError.notGoogleMapsURL
        }

        // Check if it contains photo data (the !6s marker indicates an embedded image)
        guard urlString.contains("!6s") else {
            throw GoogleMapsURLParserError.notPhotoURL
        }

        // Extract place name from path: /maps/place/<name>/
        guard let placeName = extractPlaceName(from: urlString) else {
            throw GoogleMapsURLParserError.missingPlaceName
        }

        // Extract coordinates: !3d<lat>!4d<lng>
        guard let coordinate = extractCoordinates(from: urlString) else {
            throw GoogleMapsURLParserError.missingCoordinates
        }

        // Extract image URL: after !6s, URL-encoded
        guard let imageURL = extractImageURL(from: urlString) else {
            throw GoogleMapsURLParserError.missingImageData
        }

        // Extract dimensions (optional): !7i<width>!8i<height>
        let dimensions = extractDimensions(from: urlString)

        return GoogleMapsPhotoData(
            imageURL: imageURL,
            coordinate: coordinate,
            placeName: placeName,
            imageWidth: dimensions?.width,
            imageHeight: dimensions?.height
        )
    }

    /// Checks if a URL is a Google Maps short link that needs resolution
    func isShortURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("goo.gl") || host.contains("maps.app")
    }

    // MARK: - Private Extraction Methods

    private func extractPlaceName(from urlString: String) -> String? {
        // Pattern: /maps/place/<encoded-name>/
        // The name is URL-encoded with + for spaces
        guard let placeRange = urlString.range(of: "/maps/place/") else {
            return nil
        }

        let afterPlace = String(urlString[placeRange.upperBound...])

        // Find the end of the place name (next /)
        guard let slashRange = afterPlace.range(of: "/") else {
            return nil
        }

        let encoded = String(afterPlace[..<slashRange.lowerBound])

        // Decode: first replace + with space, then percent-decode
        let withSpaces = encoded.replacingOccurrences(of: "+", with: " ")
        return withSpaces.removingPercentEncoding ?? withSpaces
    }

    private func extractCoordinates(from urlString: String) -> CLLocationCoordinate2D? {
        // Pattern: !3d<latitude>!4d<longitude>
        // Latitude comes after !3d, longitude after !4d

        // Use regex to find the patterns
        let latPattern = #"!3d(-?\d+\.?\d*)"#
        let lngPattern = #"!4d(-?\d+\.?\d*)"#

        guard let latRange = urlString.range(of: latPattern, options: .regularExpression),
            let lngRange = urlString.range(of: lngPattern, options: .regularExpression)
        else {
            return nil
        }

        // Extract the numeric values
        let latMatch = String(urlString[latRange])
        let lngMatch = String(urlString[lngRange])

        let latString = latMatch.replacingOccurrences(of: "!3d", with: "")
        let lngString = lngMatch.replacingOccurrences(of: "!4d", with: "")

        guard let lat = Double(latString),
            let lng = Double(lngString),
            lat >= -90 && lat <= 90,
            lng >= -180 && lng <= 180
        else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private func extractImageURL(from urlString: String) -> URL? {
        // Pattern: !6s<url-encoded-image-url>
        // The image URL is between !6s and the next parameter marker (!7i for width usually)

        guard let startRange = urlString.range(of: "!6s") else {
            return nil
        }

        let afterStart = String(urlString[startRange.upperBound...])

        // Find the end - look for !7i (width) or any other ! followed by a digit
        var endIndex = afterStart.endIndex

        // Try to find !7i first (most common)
        if let widthMarker = afterStart.range(of: "!7i") {
            endIndex = widthMarker.lowerBound
        } else {
            // Otherwise find the next !<digit> pattern
            let nextMarkerPattern = #"!\d"#
            if let nextMarker = afterStart.range(of: nextMarkerPattern, options: .regularExpression)
            {
                endIndex = nextMarker.lowerBound
            }
        }

        let encoded = String(afterStart[..<endIndex])

        // URL decode the image URL
        guard let decoded = encoded.removingPercentEncoding else {
            return nil
        }

        // The URL might have additional parameters we need to clean up
        // Remove any trailing parameters that aren't part of the URL
        var cleanURL = decoded

        // Ensure we get the full-resolution image by modifying the URL parameters
        // Google image URLs often end with =k-no- or similar, we want =s0 for full size
        if cleanURL.contains("=k-no") {
            cleanURL = cleanURL.replacingOccurrences(of: "=k-no", with: "=s0")
        } else if !cleanURL.contains("=s") {
            // Add full-size parameter if not present
            cleanURL += "=s0"
        }

        return URL(string: cleanURL)
    }

    private func extractDimensions(from urlString: String) -> (width: Int, height: Int)? {
        // Pattern: !7i<width>!8i<height>
        let widthPattern = #"!7i(\d+)"#
        let heightPattern = #"!8i(\d+)"#

        guard let widthRange = urlString.range(of: widthPattern, options: .regularExpression),
            let heightRange = urlString.range(of: heightPattern, options: .regularExpression)
        else {
            return nil
        }

        let widthMatch = String(urlString[widthRange])
        let heightMatch = String(urlString[heightRange])

        let widthString = widthMatch.replacingOccurrences(of: "!7i", with: "")
        let heightString = heightMatch.replacingOccurrences(of: "!8i", with: "")

        guard let width = Int(widthString),
            let height = Int(heightString)
        else {
            return nil
        }

        return (width, height)
    }
}
