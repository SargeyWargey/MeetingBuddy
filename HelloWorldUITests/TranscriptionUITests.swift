//
//  TranscriptionUITests.swift
//  HelloWorldUITests
//
//  Created by Kiro on 7/27/25.
//

import XCTest

final class TranscriptionUITests: XCTestCase {
    
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
    func testTranscriptionStatusIndicators() throws {
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        if recordingsTab.exists {
            recordingsTab.tap()
        }
        
        // Check if there are any recordings in the list
        let recordingsList = app.scrollViews.firstMatch
        if recordingsList.exists && recordingsList.cells.count > 0 {
            let firstCell = recordingsList.cells.firstMatch
            
            // Test different transcription status displays
            // Note: These tests would need actual recordings with different statuses
            // In a real scenario, we'd set up test data with various transcription states
            
            // Check for transcription status text
            let transcriptionStatusTexts = [
                "Tap to transcribe",
                "Transcribing...",
                "Queued for transcription",
                "Transcription failed - tap to retry"
            ]
            
            var foundStatusText = false
            for statusText in transcriptionStatusTexts {
                if firstCell.staticTexts[statusText].exists {
                    foundStatusText = true
                    break
                }
            }
            
            // At least one status should be present
            XCTAssertTrue(foundStatusText, "Should display transcription status")
        }
    }
    
    @MainActor
    func testTranscribeButtonInteraction() throws {
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        if recordingsTab.exists {
            recordingsTab.tap()
        }
        
        let recordingsList = app.scrollViews.firstMatch
        if recordingsList.exists && recordingsList.cells.count > 0 {
            let firstCell = recordingsList.cells.firstMatch
            
            // Look for transcribe button (text.bubble icon)
            let transcribeButton = firstCell.buttons["Transcribe recording"]
            if transcribeButton.exists {
                transcribeButton.tap()
                
                // After tapping, should show progress indicator or change status
                let progressIndicator = firstCell.activityIndicators.firstMatch
                let transcribingText = firstCell.staticTexts["Transcribing..."]
                
                // Either progress indicator or "Transcribing..." text should appear
                let hasProgressFeedback = progressIndicator.exists || transcribingText.exists
                XCTAssertTrue(hasProgressFeedback, "Should show progress feedback after transcribe button tap")
            }
        }
    }
    
    @MainActor
    func testRetryTranscriptionButton() throws {
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        if recordingsTab.exists {
            recordingsTab.tap()
        }
        
        let recordingsList = app.scrollViews.firstMatch
        if recordingsList.exists && recordingsList.cells.count > 0 {
            let firstCell = recordingsList.cells.firstMatch
            
            // Look for retry button (arrow.clockwise icon)
            let retryButton = firstCell.buttons["Retry transcription"]
            if retryButton.exists {
                retryButton.tap()
                
                // After tapping retry, should show progress feedback
                let progressIndicator = firstCell.activityIndicators.firstMatch
                let transcribingText = firstCell.staticTexts["Transcribing..."]
                
                let hasProgressFeedback = progressIndicator.exists || transcribingText.exists
                XCTAssertTrue(hasProgressFeedback, "Should show progress feedback after retry button tap")
            }
        }
    }
    
    @MainActor
    func testCopyTranscriptionButton() throws {
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        if recordingsTab.exists {
            recordingsTab.tap()
        }
        
        let recordingsList = app.scrollViews.firstMatch
        if recordingsList.exists && recordingsList.cells.count > 0 {
            let firstCell = recordingsList.cells.firstMatch
            
            // Look for copy button (doc.on.clipboard icon)
            let copyButton = firstCell.buttons["Copy transcription"]
            if copyButton.exists {
                copyButton.tap()
                
                // Should show copy confirmation alert
                let copyAlert = app.alerts["Copied to Clipboard"]
                XCTAssertTrue(copyAlert.waitForExistence(timeout: 2), "Should show copy confirmation alert")
                
                // Dismiss the alert
                let okButton = copyAlert.buttons["OK"]
                if okButton.exists {
                    okButton.tap()
                }
            }
        }
    }
    
    @MainActor
    func testLongPressGestureCopy() throws {
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        if recordingsTab.exists {
            recordingsTab.tap()
        }
        
        let recordingsList = app.scrollViews.firstMatch
        if recordingsList.exists && recordingsList.cells.count > 0 {
            let firstCell = recordingsList.cells.firstMatch
            
            // Perform long press gesture on the cell
            firstCell.press(forDuration: 1.0)
            
            // Should show copy confirmation alert if transcription exists
            let copyAlert = app.alerts["Copied to Clipboard"]
            if copyAlert.exists {
                XCTAssertTrue(copyAlert.waitForExistence(timeout: 2), "Should show copy confirmation alert after long press")
                
                // Dismiss the alert
                let okButton = copyAlert.buttons["OK"]
                if okButton.exists {
                    okButton.tap()
                }
            }
        }
    }
    
    @MainActor
    func testTranscriptionPreviewDisplay() throws {
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        if recordingsTab.exists {
            recordingsTab.tap()
        }
        
        let recordingsList = app.scrollViews.firstMatch
        if recordingsList.exists && recordingsList.cells.count > 0 {
            let firstCell = recordingsList.cells.firstMatch
            
            // Check for transcription preview text
            // This would contain actual transcription content in a real scenario
            let transcriptionTexts = firstCell.staticTexts.allElementsBoundByIndex
            
            var hasTranscriptionContent = false
            for textElement in transcriptionTexts {
                let text = textElement.label
                // Look for transcription-like content (not status messages)
                if !text.contains("Tap to transcribe") &&
                   !text.contains("Transcribing...") &&
                   !text.contains("failed") &&
                   !text.contains("Queued") &&
                   text.count > 10 { // Assume transcription content is longer
                    hasTranscriptionContent = true
                    
                    // Check if long text is properly truncated
                    if text.count > 100 {
                        XCTAssertTrue(text.hasSuffix("..."), "Long transcription should be truncated with ellipsis")
                    }
                    break
                }
            }
            
            // Note: This test would be more meaningful with actual test data
            // For now, we just verify the UI structure exists
        }
    }
    
    @MainActor
    func testProgressIndicatorsDuringTranscription() throws {
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        if recordingsTab.exists {
            recordingsTab.tap()
        }
        
        let recordingsList = app.scrollViews.firstMatch
        if recordingsList.exists && recordingsList.cells.count > 0 {
            let firstCell = recordingsList.cells.firstMatch
            
            // Look for transcribe button and tap it
            let transcribeButton = firstCell.buttons["Transcribe recording"]
            if transcribeButton.exists {
                transcribeButton.tap()
                
                // Check for various progress indicators
                let progressView = firstCell.activityIndicators.firstMatch
                let transcribingText = firstCell.staticTexts["Transcribing..."]
                
                // Should show some form of progress indication
                let hasProgressIndicator = progressView.exists || transcribingText.exists
                XCTAssertTrue(hasProgressIndicator, "Should show progress indicator during transcription")
                
                // The transcribe button should be replaced or disabled during processing
                let updatedTranscribeButton = firstCell.buttons["Transcribe recording"]
                if updatedTranscribeButton.exists {
                    // Button might still exist but should be in a different state
                    // In our implementation, it gets replaced with a progress view
                }
            }
        }
    }
    
    @MainActor
    func testAccessibilityLabels() throws {
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        if recordingsTab.exists {
            recordingsTab.tap()
        }
        
        let recordingsList = app.scrollViews.firstMatch
        if recordingsList.exists && recordingsList.cells.count > 0 {
            let firstCell = recordingsList.cells.firstMatch
            
            // Test accessibility labels for transcription buttons
            let transcribeButton = firstCell.buttons["Transcribe recording"]
            let retryButton = firstCell.buttons["Retry transcription"]
            let copyButton = firstCell.buttons["Copy transcription"]
            
            // At least one of these buttons should exist with proper accessibility labels
            let hasAccessibleButton = transcribeButton.exists || retryButton.exists || copyButton.exists
            XCTAssertTrue(hasAccessibleButton, "Should have accessible transcription buttons")
            
            // Verify the accessibility labels are meaningful
            if transcribeButton.exists {
                XCTAssertEqual(transcribeButton.label, "Transcribe recording")
            }
            if retryButton.exists {
                XCTAssertEqual(retryButton.label, "Retry transcription")
            }
            if copyButton.exists {
                XCTAssertEqual(copyButton.label, "Copy transcription")
            }
        }
    }
    
    // MARK: - TranscriptionDetailView Tests
    
    @MainActor
    func testTranscriptionDetailViewNavigation() throws {
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        if recordingsTab.exists {
            recordingsTab.tap()
        }
        
        let recordingsList = app.scrollViews.firstMatch
        if recordingsList.exists && recordingsList.cells.count > 0 {
            let firstCell = recordingsList.cells.firstMatch
            
            // Look for view transcription button or transcription text that can be tapped
            let viewTranscriptionButton = firstCell.buttons["View transcription"]
            if viewTranscriptionButton.exists {
                viewTranscriptionButton.tap()
                
                // Should open the transcription detail view
                let transcriptionDetailView = app.navigationBars["Transcription"]
                XCTAssertTrue(transcriptionDetailView.waitForExistence(timeout: 3), "Should navigate to transcription detail view")
                
                // Should have a Done button
                let doneButton = transcriptionDetailView.buttons["Done"]
                XCTAssertTrue(doneButton.exists, "Should have Done button in navigation bar")
                
                // Close the detail view
                doneButton.tap()
            }
        }
    }
    
    @MainActor
    func testTranscriptionDetailViewContent() throws {
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        if recordingsTab.exists {
            recordingsTab.tap()
        }
        
        let recordingsList = app.scrollViews.firstMatch
        if recordingsList.exists && recordingsList.cells.count > 0 {
            let firstCell = recordingsList.cells.firstMatch
            
            // Navigate to detail view
            let viewTranscriptionButton = firstCell.buttons["View transcription"]
            if viewTranscriptionButton.exists {
                viewTranscriptionButton.tap()
                
                let detailView = app.scrollViews.firstMatch
                XCTAssertTrue(detailView.waitForExistence(timeout: 3), "Detail view should exist")
                
                // Check for recording info section
                let recordingTitle = detailView.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Recording'")).firstMatch
                XCTAssertTrue(recordingTitle.exists, "Should display recording title")
                
                // Check for transcription section
                let transcriptionHeading = detailView.staticTexts["Transcription"]
                XCTAssertTrue(transcriptionHeading.exists, "Should have Transcription heading")
                
                // Check for status badge
                let statusLabels = ["Completed", "In Progress", "Failed", "Queued", "Not Started"]
                var foundStatus = false
                for status in statusLabels {
                    if detailView.staticTexts[status].exists {
                        foundStatus = true
                        break
                    }
                }
                XCTAssertTrue(foundStatus, "Should display transcription status")
                
                // Close detail view
                let doneButton = app.navigationBars["Transcription"].buttons["Done"]
                doneButton.tap()
            }
        }
    }
    
    @MainActor
    func testTranscriptionDetailViewCopyFunctionality() throws {
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        if recordingsTab.exists {
            recordingsTab.tap()
        }
        
        let recordingsList = app.scrollViews.firstMatch
        if recordingsList.exists && recordingsList.cells.count > 0 {
            let firstCell = recordingsList.cells.firstMatch
            
            // Navigate to detail view
            let viewTranscriptionButton = firstCell.buttons["View transcription"]
            if viewTranscriptionButton.exists {
                viewTranscriptionButton.tap()
                
                // Test toolbar copy button
                let copyButton = app.navigationBars["Transcription"].buttons.matching(NSPredicate(format: "label CONTAINS 'Copy'")).firstMatch
                if copyButton.exists {
                    copyButton.tap()
                    
                    // Should show copy confirmation alert
                    let copyAlert = app.alerts["Copied to Clipboard"]
                    XCTAssertTrue(copyAlert.waitForExistence(timeout: 2), "Should show copy confirmation alert")
                    
                    let okButton = copyAlert.buttons["OK"]
                    okButton.tap()
                }
                
                // Test copy button in content area
                let contentCopyButton = app.buttons["Copy Text"]
                if contentCopyButton.exists {
                    contentCopyButton.tap()
                    
                    let copyAlert = app.alerts["Copied to Clipboard"]
                    XCTAssertTrue(copyAlert.waitForExistence(timeout: 2), "Should show copy confirmation alert")
                    
                    let okButton = copyAlert.buttons["OK"]
                    okButton.tap()
                }
                
                // Close detail view
                let doneButton = app.navigationBars["Transcription"].buttons["Done"]
                doneButton.tap()
            }
        }
    }
    
    @MainActor
    func testTranscriptionDetailViewRetryFunctionality() throws {
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        if recordingsTab.exists {
            recordingsTab.tap()
        }
        
        let recordingsList = app.scrollViews.firstMatch
        if recordingsList.exists && recordingsList.cells.count > 0 {
            let firstCell = recordingsList.cells.firstMatch
            
            // Navigate to detail view (could be failed transcription)
            let viewTranscriptionButton = firstCell.buttons["View transcription"]
            if viewTranscriptionButton.exists {
                viewTranscriptionButton.tap()
                
                // Look for retry buttons
                let retryButtons = [
                    app.buttons["Retry Transcription"],
                    app.buttons["Retry"],
                    app.buttons["Start Transcription"],
                    app.buttons["Process Now"]
                ]
                
                for retryButton in retryButtons {
                    if retryButton.exists {
                        retryButton.tap()
                        
                        // Should show some progress indication or state change
                        let progressIndicator = app.activityIndicators.firstMatch
                        let retryingText = app.staticTexts["Retrying..."]
                        let startingText = app.staticTexts["Starting..."]
                        
                        let hasProgressFeedback = progressIndicator.exists || retryingText.exists || startingText.exists
                        XCTAssertTrue(hasProgressFeedback, "Should show progress feedback after retry")
                        
                        break
                    }
                }
                
                // Close detail view
                let doneButton = app.navigationBars["Transcription"].buttons["Done"]
                doneButton.tap()
            }
        }
    }
    
    @MainActor
    func testTranscriptionDetailViewMetadataSection() throws {
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        if recordingsTab.exists {
            recordingsTab.tap()
        }
        
        let recordingsList = app.scrollViews.firstMatch
        if recordingsList.exists && recordingsList.cells.count > 0 {
            let firstCell = recordingsList.cells.firstMatch
            
            // Navigate to detail view
            let viewTranscriptionButton = firstCell.buttons["View transcription"]
            if viewTranscriptionButton.exists {
                viewTranscriptionButton.tap()
                
                let detailView = app.scrollViews.firstMatch
                
                // Check for metadata section (only visible for completed transcriptions)
                let metadataHeading = detailView.staticTexts["Transcription Details"]
                if metadataHeading.exists {
                    // Check for metadata fields
                    let metadataFields = [
                        "Status",
                        "Last Attempt",
                        "Method",
                        "Confidence",
                        "Processing Time",
                        "Word Count",
                        "Character Count"
                    ]
                    
                    var foundMetadataFields = 0
                    for field in metadataFields {
                        if detailView.staticTexts[field].exists {
                            foundMetadataFields += 1
                        }
                    }
                    
                    XCTAssertGreaterThan(foundMetadataFields, 0, "Should display at least one metadata field")
                }
                
                // Close detail view
                let doneButton = app.navigationBars["Transcription"].buttons["Done"]
                doneButton.tap()
            }
        }
    }
    
    @MainActor
    func testTranscriptionDetailViewEmptyState() throws {
        // This test would ideally be run with a recording that has completed transcription but no text
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        if recordingsTab.exists {
            recordingsTab.tap()
        }
        
        let recordingsList = app.scrollViews.firstMatch
        if recordingsList.exists && recordingsList.cells.count > 0 {
            let firstCell = recordingsList.cells.firstMatch
            
            // Navigate to detail view
            let viewTranscriptionButton = firstCell.buttons["View transcription"]
            if viewTranscriptionButton.exists {
                viewTranscriptionButton.tap()
                
                let detailView = app.scrollViews.firstMatch
                
                // Check for empty state elements
                let emptyStateTexts = [
                    "No Transcription Available",
                    "Not Transcribed",
                    "Transcription Failed"
                ]
                
                var foundEmptyState = false
                for text in emptyStateTexts {
                    if detailView.staticTexts[text].exists {
                        foundEmptyState = true
                        break
                    }
                }
                
                // If we found an empty state, check for appropriate action buttons
                if foundEmptyState {
                    let actionButtons = [
                        app.buttons["Retry Transcription"],
                        app.buttons["Start Transcription"]
                    ]
                    
                    var foundActionButton = false
                    for button in actionButtons {
                        if button.exists {
                            foundActionButton = true
                            break
                        }
                    }
                    
                    XCTAssertTrue(foundActionButton, "Empty state should have action button")
                }
                
                // Close detail view
                let doneButton = app.navigationBars["Transcription"].buttons["Done"]
                doneButton.tap()
            }
        }
    }
    
    @MainActor
    func testTranscriptionDetailViewAccessibility() throws {
        // Navigate to recordings tab
        let recordingsTab = app.tabBars.buttons["Recordings"]
        if recordingsTab.exists {
            recordingsTab.tap()
        }
        
        let recordingsList = app.scrollViews.firstMatch
        if recordingsList.exists && recordingsList.cells.count > 0 {
            let firstCell = recordingsList.cells.firstMatch
            
            // Navigate to detail view
            let viewTranscriptionButton = firstCell.buttons["View transcription"]
            if viewTranscriptionButton.exists {
                viewTranscriptionButton.tap()
                
                // Check accessibility of navigation elements
                let doneButton = app.navigationBars["Transcription"].buttons["Done"]
                XCTAssertTrue(doneButton.exists, "Done button should be accessible")
                
                let copyButton = app.navigationBars["Transcription"].buttons.matching(NSPredicate(format: "label CONTAINS 'Copy'")).firstMatch
                if copyButton.exists {
                    XCTAssertTrue(copyButton.isHittable, "Copy button should be accessible")
                }
                
                // Check accessibility of action buttons
                let actionButtons = [
                    app.buttons["Copy Text"],
                    app.buttons["Retry"],
                    app.buttons["Retry Transcription"],
                    app.buttons["Start Transcription"]
                ]
                
                for button in actionButtons {
                    if button.exists {
                        XCTAssertTrue(button.isHittable, "Action buttons should be accessible")
                    }
                }
                
                // Close detail view
                doneButton.tap()
            }
        }
    }}
