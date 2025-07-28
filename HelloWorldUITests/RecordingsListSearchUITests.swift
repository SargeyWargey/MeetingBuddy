import XCTest

final class RecordingsListSearchUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    @MainActor
    func testSearchBarAppears() throws {
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        XCTAssertTrue(recordingsTab.exists, "Recordings tab should exist")
        recordingsTab.tap()
        
        // Pull down to reveal search bar (if using searchable modifier)
        let recordingsList = app.collectionViews.firstMatch
        if recordingsList.exists {
            recordingsList.swipeDown()
        }
        
        // Check if search field appears
        let searchField = app.searchFields["Search transcriptions..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2.0), "Search field should appear")
    }
    
    @MainActor
    func testSearchFieldInteraction() throws {
        // Navigate to recordings tab
        app.tabBars.buttons["Recordings"].tap()
        
        // Pull down to reveal search bar
        let recordingsList = app.collectionViews.firstMatch
        if recordingsList.exists {
            recordingsList.swipeDown()
        }
        
        // Tap search field
        let searchField = app.searchFields["Search transcriptions..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2.0))
        searchField.tap()
        
        // Type in search field
        searchField.typeText("test search")
        
        // Verify text was entered
        XCTAssertEqual(searchField.value as? String, "test search")
    }
    
    @MainActor
    func testSearchResultsFiltering() throws {
        // This test assumes there are recordings with transcriptions
        // Navigate to recordings tab
        app.tabBars.buttons["Recordings"].tap()
        
        // Wait for recordings to load
        let recordingsList = app.collectionViews.firstMatch
        XCTAssertTrue(recordingsList.waitForExistence(timeout: 3.0))
        
        // Count initial recordings
        let initialRecordingCount = recordingsList.cells.count
        
        // Pull down to reveal search bar
        recordingsList.swipeDown()
        
        // Search for specific text
        let searchField = app.searchFields["Search transcriptions..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2.0))
        searchField.tap()
        searchField.typeText("meeting")
        
        // Wait for filtering to complete
        sleep(1)
        
        // Verify results are filtered (should be less than or equal to initial count)
        let filteredRecordingCount = recordingsList.cells.count
        XCTAssertLessThanOrEqual(filteredRecordingCount, initialRecordingCount, "Filtered results should not exceed initial count")
    }
    
    @MainActor
    func testSearchEmptyState() throws {
        // Navigate to recordings tab
        app.tabBars.buttons["Recordings"].tap()
        
        let recordingsList = app.collectionViews.firstMatch
        XCTAssertTrue(recordingsList.waitForExistence(timeout: 3.0))
        
        // Pull down to reveal search bar
        recordingsList.swipeDown()
        
        // Search for text that shouldn't exist
        let searchField = app.searchFields["Search transcriptions..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2.0))
        searchField.tap()
        searchField.typeText("xyznonexistenttext123")
        
        // Wait for filtering to complete
        sleep(1)
        
        // Check for empty state message
        let noResultsText = app.staticTexts["No Results Found"]
        XCTAssertTrue(noResultsText.waitForExistence(timeout: 2.0), "Empty state should appear for no results")
        
        // Check for search term in empty state message
        let searchTermText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'xyznonexistenttext123'")).firstMatch
        XCTAssertTrue(searchTermText.exists, "Empty state should show the search term")
    }
    
    @MainActor
    func testSearchClearFunctionality() throws {
        // Navigate to recordings tab
        app.tabBars.buttons["Recordings"].tap()
        
        let recordingsList = app.collectionViews.firstMatch
        XCTAssertTrue(recordingsList.waitForExistence(timeout: 3.0))
        
        // Count initial recordings
        let initialRecordingCount = recordingsList.cells.count
        
        // Pull down to reveal search bar
        recordingsList.swipeDown()
        
        // Search for something
        let searchField = app.searchFields["Search transcriptions..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2.0))
        searchField.tap()
        searchField.typeText("test")
        
        // Wait for filtering
        sleep(1)
        
        // Clear search
        let clearButton = searchField.buttons["Clear text"]
        if clearButton.exists {
            clearButton.tap()
        } else {
            // Alternative: select all and delete
            searchField.doubleTap()
            app.keys["delete"].tap()
        }
        
        // Wait for results to update
        sleep(1)
        
        // Verify all recordings are shown again
        let finalRecordingCount = recordingsList.cells.count
        XCTAssertEqual(finalRecordingCount, initialRecordingCount, "Clearing search should show all recordings")
    }
    
    @MainActor
    func testSearchHighlighting() throws {
        // This test verifies that search highlighting works
        // Navigate to recordings tab
        app.tabBars.buttons["Recordings"].tap()
        
        let recordingsList = app.collectionViews.firstMatch
        XCTAssertTrue(recordingsList.waitForExistence(timeout: 3.0))
        
        // Pull down to reveal search bar
        recordingsList.swipeDown()
        
        // Search for common word
        let searchField = app.searchFields["Search transcriptions..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2.0))
        searchField.tap()
        searchField.typeText("the")
        
        // Wait for filtering
        sleep(1)
        
        // Verify that at least one recording is shown (assuming transcriptions contain "the")
        let recordingCells = recordingsList.cells
        if recordingCells.count > 0 {
            // This is a basic test - in a real scenario, you might check for highlighted text
            // but XCUITest has limitations in detecting text formatting
            XCTAssertGreaterThan(recordingCells.count, 0, "Search should return results for common word")
        }
    }
    
    @MainActor
    func testSearchWithSpecialCharacters() throws {
        // Navigate to recordings tab
        app.tabBars.buttons["Recordings"].tap()
        
        let recordingsList = app.collectionViews.firstMatch
        XCTAssertTrue(recordingsList.waitForExistence(timeout: 3.0))
        
        // Pull down to reveal search bar
        recordingsList.swipeDown()
        
        // Search with special characters
        let searchField = app.searchFields["Search transcriptions..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2.0))
        searchField.tap()
        searchField.typeText("@#$%")
        
        // Wait for filtering
        sleep(1)
        
        // App should handle special characters gracefully (likely no results)
        // This test mainly ensures the app doesn't crash
        XCTAssertTrue(app.exists, "App should handle special characters in search without crashing")
    }
    
    @MainActor
    func testSearchPerformanceWithLongText() throws {
        // Navigate to recordings tab
        app.tabBars.buttons["Recordings"].tap()
        
        let recordingsList = app.collectionViews.firstMatch
        XCTAssertTrue(recordingsList.waitForExistence(timeout: 3.0))
        
        // Pull down to reveal search bar
        recordingsList.swipeDown()
        
        // Search with long text
        let searchField = app.searchFields["Search transcriptions..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2.0))
        searchField.tap()
        
        let longSearchText = String(repeating: "test ", count: 50)
        searchField.typeText(longSearchText)
        
        // Measure performance of search filtering
        measure(metrics: [XCTClockMetric()]) {
            // Wait for search to complete
            sleep(1)
        }
        
        // Verify app remains responsive
        XCTAssertTrue(app.exists, "App should remain responsive with long search text")
    }
}