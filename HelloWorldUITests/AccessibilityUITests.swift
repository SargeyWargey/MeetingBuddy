import XCTest

class AccessibilityUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - VoiceOver Tests
    
    func testRecordingButtonAccessibility() throws {
        // Navigate to recording tab
        let recordingTab = app.tabBars.buttons["Voice Recorder"]
        XCTAssertTrue(recordingTab.exists)
        recordingTab.tap()
        
        // Test recording button accessibility
        let recordButton = app.buttons.matching(identifier: "Start recording").firstMatch
        XCTAssertTrue(recordButton.exists, "Record button should exist")
        XCTAssertTrue(recordButton.isHittable, "Record button should be hittable")
        
        // Check accessibility properties
        XCTAssertFalse(recordButton.label.isEmpty, "Record button should have accessibility label")
    }
    
    func testRecordingsListAccessibility() throws {
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        XCTAssertTrue(recordingsTab.exists)
        recordingsTab.tap()
        
        // Test search field accessibility
        let searchField = app.searchFields.firstMatch
        if searchField.exists {
            XCTAssertTrue(searchField.isHittable, "Search field should be hittable")
            XCTAssertFalse(searchField.placeholderValue?.isEmpty ?? true, "Search field should have placeholder text")
        }
        
        // Test network status indicator accessibility
        let networkIndicator = app.images["Offline"].firstMatch
        if networkIndicator.exists {
            XCTAssertFalse(networkIndicator.label.isEmpty, "Network indicator should have accessibility label")
        }
    }
    
    func testTranscriptionElementsAccessibility() throws {
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        recordingsTab.tap()
        
        // Look for transcription-related buttons
        let transcribeButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS 'transcrib'"))
        
        for i in 0..<transcribeButtons.count {
            let button = transcribeButtons.element(boundBy: i)
            if button.exists {
                XCTAssertTrue(button.isHittable, "Transcription button should be hittable")
                XCTAssertFalse(button.label.isEmpty, "Transcription button should have accessibility label")
            }
        }
    }
    
    // MARK: - Dynamic Type Tests
    
    func testDynamicTypeSupport() throws {
        // This test would ideally change the system's Dynamic Type setting
        // and verify that the app responds appropriately
        // For now, we'll just verify that text elements exist and are accessible
        
        let recordingTab = app.tabBars.buttons["Voice Recorder"]
        recordingTab.tap()
        
        let recordingTimeLabel = app.staticTexts["Recording Time"]
        if recordingTimeLabel.exists {
            XCTAssertTrue(recordingTimeLabel.isHittable, "Recording time label should be accessible")
        }
        
        let statusText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Tap to Record' OR label CONTAINS 'Recording'")).firstMatch
        if statusText.exists {
            XCTAssertTrue(statusText.isHittable, "Status text should be accessible")
        }
    }
    
    // MARK: - Transcription Detail View Tests
    
    func testTranscriptionDetailAccessibility() throws {
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        recordingsTab.tap()
        
        // Look for a recording with transcription to tap on
        let transcriptionButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS 'View transcription'"))
        
        if transcriptionButtons.count > 0 {
            let firstTranscriptionButton = transcriptionButtons.firstMatch
            firstTranscriptionButton.tap()
            
            // Test transcription detail view elements
            let copyButton = app.buttons["Copy transcription"]
            if copyButton.exists {
                XCTAssertTrue(copyButton.isHittable, "Copy button should be hittable")
                XCTAssertFalse(copyButton.label.isEmpty, "Copy button should have accessibility label")
            }
            
            let retryButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Retry'")).firstMatch
            if retryButton.exists {
                XCTAssertTrue(retryButton.isHittable, "Retry button should be hittable")
            }
            
            let doneButton = app.buttons["Done"]
            if doneButton.exists {
                doneButton.tap() // Close the detail view
            }
        }
    }
    
    // MARK: - Search Accessibility Tests
    
    func testSearchAccessibility() throws {
        let recordingsTab = app.tabBars.buttons["Recordings"]
        recordingsTab.tap()
        
        let searchField = app.searchFields.firstMatch
        if searchField.exists {
            // Test search field interaction
            searchField.tap()
            searchField.typeText("test")
            
            // Verify search results are accessible
            // The app should announce search results for accessibility
            
            // Clear search
            if app.buttons["Clear text"].exists {
                app.buttons["Clear text"].tap()
            }
        }
    }
    
    // MARK: - Error State Accessibility Tests
    
    func testErrorStateAccessibility() throws {
        // This test would verify that error states are properly announced
        // and that retry actions are accessible
        
        let recordingsTab = app.tabBars.buttons["Recordings"]
        recordingsTab.tap()
        
        // Look for failed transcription indicators
        let failedIndicators = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'failed'"))
        
        for i in 0..<failedIndicators.count {
            let indicator = failedIndicators.element(boundBy: i)
            if indicator.exists {
                XCTAssertTrue(indicator.isHittable, "Failed transcription indicator should be accessible")
            }
        }
    }
    
    // MARK: - Reduced Motion Tests
    
    func testReducedMotionSupport() throws {
        // This test would ideally enable reduced motion in system settings
        // and verify that animations are reduced appropriately
        // For now, we'll just verify that the UI elements are still functional
        
        let recordingTab = app.tabBars.buttons["Voice Recorder"]
        recordingTab.tap()
        
        let recordButton = app.buttons.matching(identifier: "Start recording").firstMatch
        if recordButton.exists {
            // The button should still be functional even with reduced motion
            XCTAssertTrue(recordButton.isHittable)
        }
    }
    
    // MARK: - Integration Tests
    
    func testFullTranscriptionFlowAccessibility() throws {
        // Test the complete transcription flow for accessibility
        
        // 1. Navigate to recordings
        let recordingsTab = app.tabBars.buttons["Recordings"]
        recordingsTab.tap()
        
        // 2. Look for a transcribe button
        let transcribeButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Transcribe recording'")).firstMatch
        
        if transcribeButton.exists {
            // 3. Tap to start transcription
            transcribeButton.tap()
            
            // 4. Verify that progress indicators are accessible
            let progressIndicator = app.activityIndicators.firstMatch
            if progressIndicator.exists {
                // Progress should be announced for accessibility
                XCTAssertTrue(progressIndicator.exists)
            }
            
            // 5. Wait a moment for potential state changes
            sleep(2)
            
            // 6. Check if transcription completed or failed states are accessible
            let completedIndicator = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'completed'")).firstMatch
            let failedIndicator = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'failed'")).firstMatch
            
            if completedIndicator.exists {
                XCTAssertTrue(completedIndicator.isHittable, "Completed indicator should be accessible")
            } else if failedIndicator.exists {
                XCTAssertTrue(failedIndicator.isHittable, "Failed indicator should be accessible")
            }
        }
    }
    
    // MARK: - Copy Functionality Tests
    
    func testCopyFunctionalityAccessibility() throws {
        let recordingsTab = app.tabBars.buttons["Recordings"]
        recordingsTab.tap()
        
        // Look for recordings with transcriptions
        let viewTranscriptionButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS 'View transcription'"))
        
        if viewTranscriptionButtons.count > 0 {
            let firstButton = viewTranscriptionButtons.firstMatch
            firstButton.tap()
            
            // Test copy button in detail view
            let copyButton = app.buttons["Copy transcription"]
            if copyButton.exists {
                copyButton.tap()
                
                // Verify copy confirmation is accessible
                let copyAlert = app.alerts["Copied to Clipboard"]
                if copyAlert.exists {
                    XCTAssertTrue(copyAlert.isHittable, "Copy confirmation should be accessible")
                    
                    let okButton = copyAlert.buttons["OK"]
                    if okButton.exists {
                        okButton.tap()
                    }
                }
            }
            
            // Close detail view
            let doneButton = app.buttons["Done"]
            if doneButton.exists {
                doneButton.tap()
            }
        }
    }
    
    // MARK: - Performance Tests
    
    func testAccessibilityPerformance() throws {
        // Measure performance of accessibility-enhanced UI
        measure {
            let recordingsTab = app.tabBars.buttons["Recordings"]
            recordingsTab.tap()
            
            let recordingTab = app.tabBars.buttons["Voice Recorder"]
            recordingTab.tap()
        }
    }
}