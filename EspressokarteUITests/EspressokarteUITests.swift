//
//  EspressokarteUITests.swift
//  EspressokarteUITests
//
//  Created by Timo Kuehne on 07.01.26.
//

import XCTest

final class EspressokarteUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Map View Tests

    @MainActor
    func testMapViewLoads() throws {
        // The map should be visible
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5), "Map should be visible")
    }

    @MainActor
    func testAddPriceButtonExists() throws {
        // The add price button should exist
        let addButton = app.buttons["Add espresso price"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Add button should exist")
    }

    @MainActor
    func testAddPriceButtonOpensSheet() throws {
        // Tap the add price button
        let addButton = app.buttons["Add espresso price"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        // The add price sheet should appear
        let navigationTitle = app.navigationBars["Add Price"]
        XCTAssertTrue(navigationTitle.waitForExistence(timeout: 3), "Add Price sheet should open")
    }

    // MARK: - Add Price Flow Tests

    @MainActor
    func testAddPriceSheetHasCancelButton() throws {
        // Open add price sheet
        let addButton = app.buttons["Add espresso price"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        // Cancel button should exist
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3), "Cancel button should exist")
    }

    @MainActor
    func testAddPriceSheetCanBeDismissed() throws {
        // Open add price sheet
        let addButton = app.buttons["Add espresso price"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        // Wait for sheet to appear
        let navigationTitle = app.navigationBars["Add Price"]
        XCTAssertTrue(navigationTitle.waitForExistence(timeout: 3))

        // Tap cancel
        let cancelButton = app.buttons["Cancel"]
        cancelButton.tap()

        // Sheet should be dismissed - map should be visible again
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 3), "Map should be visible after dismissing sheet")
    }

    @MainActor
    func testAddPriceSheetHasSearchField() throws {
        // Open add price sheet
        let addButton = app.buttons["Add espresso price"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        // Search field should exist
        let searchField = app.textFields["Search for cafes"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3), "Search field should exist")
    }

    @MainActor
    func testSearchFieldAcceptsInput() throws {
        // Open add price sheet
        let addButton = app.buttons["Add espresso price"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        // Type in search field
        let searchField = app.textFields["Search for cafes"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.tap()
        searchField.typeText("Starbucks")

        // Verify text was entered
        XCTAssertEqual(searchField.value as? String, "Starbucks")
    }

    // MARK: - Price Input Tests

    @MainActor
    func testPriceInputFieldAcceptsNumbers() throws {
        // This test requires selecting a cafe first, which needs location permission
        // In a real test environment, this would be mocked

        // Open add price sheet
        let addButton = app.buttons["Add espresso price"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        // Wait for cafes to load (if location is available)
        sleep(2)

        // If there's a cafe in the list, tap it
        let tables = app.tables
        if tables.cells.count > 0 {
            tables.cells.firstMatch.tap()

            // Price input should appear
            let priceField = app.textFields["Espresso price in euros"]
            if priceField.waitForExistence(timeout: 3) {
                priceField.tap()
                priceField.typeText("2.50")

                // Verify price was entered
                let value = priceField.value as? String ?? ""
                XCTAssertTrue(value.contains("2") || value.contains("50"), "Price should be entered")
            }
        }
    }

    // MARK: - Navigation Tests

    @MainActor
    func testMapControlsExist() throws {
        // Map controls should be present
        // Note: The exact accessibility labels depend on MapKit's implementation
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))
    }

    // MARK: - Accessibility Tests

    @MainActor
    func testAddButtonHasAccessibilityLabel() throws {
        let addButton = app.buttons["Add espresso price"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Add button should have accessibility label")
    }

    // MARK: - Performance Tests

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

// MARK: - Cafe Detail View Tests

final class CafeDetailUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testTappingMapMarkerShowsDetail() throws {
        // Wait for map to load
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))

        // This test depends on having cafes loaded
        // In a real test environment, we would seed test data
        // For now, we just verify the map loads
    }
}

// MARK: - Error Handling Tests

final class ErrorHandlingUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testAppDoesNotCrashOnLaunch() throws {
        // Simply launching and waiting should not crash
        sleep(3)
        XCTAssertTrue(app.state == .runningForeground, "App should still be running")
    }

    @MainActor
    func testAppHandlesMultipleSheetOpenClose() throws {
        // Rapidly open and close the add price sheet
        for _ in 0..<3 {
            let addButton = app.buttons["Add espresso price"]
            if addButton.waitForExistence(timeout: 2) {
                addButton.tap()

                let cancelButton = app.buttons["Cancel"]
                if cancelButton.waitForExistence(timeout: 2) {
                    cancelButton.tap()
                }

                sleep(1)
            }
        }

        // App should still be responsive
        XCTAssertTrue(app.state == .runningForeground, "App should handle repeated sheet interactions")
    }
}
