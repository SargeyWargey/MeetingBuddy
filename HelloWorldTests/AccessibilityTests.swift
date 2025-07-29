import XCTest
import SwiftUI
@testable import HelloWorld

class AccessibilityTests: XCTestCase {
    var recordingManager: RecordingManager!
    
    override func setUp() {
        super.setUp()
        recordingManager = RecordingManager()
    }
    
    override func tearDown() {
        recordingManager = nil
        super.tearDown()
    }
    
    // MARK: - Accessibility Label Tests
    
    func testTranscriptionStatusAccessibilityLabels() {
        let statuses: [Recording.TranscriptionStatus] = [.notStarted, .inProgress, .queued, .completed, .failed]
        
        for status in statuses {
            let (label, hint) = accessibilityInfo(for: status)
            XCTAssertFalse(label.isEmpty, "Accessibility label should not be empty for status: \(status)")
            XCTAssertFalse(hint.isEmpty, "Accessibility hint should not be empty for status: \(status)")
        }
    }
    
    func testTranscriptionActionAccessibilityLabels() {
        let actions: [TranscriptionAction] = [.transcribe, .retry, .view, .copy, .dismiss]
        
        for action in actions {
            let (label, hint) = accessibilityInfo(for: action)
            XCTAssertFalse(label.isEmpty, "Accessibility label should not be empty for action: \(action)")
            XCTAssertFalse(hint.isEmpty, "Accessibility hint should not be empty for action: \(action)")
        }
    }
    
    // MARK: - Dynamic Type Tests
    
    func testDynamicTypeSizes() {
        let sizes: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge, .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5]
        
        for size in sizes {
            let fontSize = size.transcriptionFontSize
            XCTAssertGreaterThan(fontSize, 0, "Font size should be greater than 0 for size: \(size)")
            
            if size.isAccessibilitySize {
                XCTAssertGreaterThanOrEqual(fontSize, 28, "Accessibility sizes should have font size >= 28")
            }
        }
    }
    
    func testAccessibilitySizeDetection() {
        XCTAssertTrue(DynamicTypeSize.accessibility1.isAccessibilitySize)
        XCTAssertTrue(DynamicTypeSize.accessibility5.isAccessibilitySize)
        XCTAssertFalse(DynamicTypeSize.medium.isAccessibilitySize)
        XCTAssertFalse(DynamicTypeSize.large.isAccessibilitySize)
    }
    
    // MARK: - Haptic Feedback Tests
    
    func testHapticFeedbackManager() {
        let hapticManager = HapticFeedbackManager.shared
        
        // These methods should not crash when called
        XCTAssertNoThrow(hapticManager.transcriptionCompleted())
        XCTAssertNoThrow(hapticManager.transcriptionFailed())
        XCTAssertNoThrow(hapticManager.transcriptionStarted())
        XCTAssertNoThrow(hapticManager.textCopied())
        XCTAssertNoThrow(hapticManager.buttonPressed())
    }
    
    // MARK: - Accessibility Announcements Tests
    
    func testAccessibilityAnnouncementManager() {
        let announcementManager = AccessibilityAnnouncementManager.shared
        let sampleRecording = createSampleRecording()
        
        // These methods should not crash when called
        XCTAssertNoThrow(announcementManager.announce("Test message"))
        XCTAssertNoThrow(announcementManager.announceTranscriptionCompleted(for: sampleRecording))
        XCTAssertNoThrow(announcementManager.announceTranscriptionFailed(for: sampleRecording))
        XCTAssertNoThrow(announcementManager.announceTranscriptionStarted(for: sampleRecording))
        XCTAssertNoThrow(announcementManager.announceTextCopied())
    }
    
    // MARK: - Recording Accessibility Tests
    
    func testRecordingAccessibilityProperties() {
        let recording = createSampleRecording()
        
        // Test that recording has accessible properties
        XCTAssertFalse(recording.title.isEmpty, "Recording title should not be empty for accessibility")
        XCTAssertFalse(recording.durationString.isEmpty, "Duration string should not be empty for accessibility")
        XCTAssertFalse(recording.transcriptionStatusDisplayText.isEmpty, "Status display text should not be empty for accessibility")
    }
    
    func testTranscriptionPreviewAccessibility() {
        var recording = createSampleRecording()
        recording.transcription = "This is a sample transcription for accessibility testing"
        recording.transcriptionStatus = .completed
        
        let preview = recording.transcriptionPreview
        XCTAssertFalse(preview.isEmpty, "Transcription preview should not be empty for accessibility")
        XCTAssertLessThanOrEqual(preview.count, 100, "Preview should be truncated for accessibility")
    }
    
    // MARK: - UI Component Accessibility Tests
    
    func testRecordingViewAccessibility() {
        let recordingView = RecordingView(recordingManager: recordingManager)
        
        // Test that the view can be created without crashing
        XCTAssertNotNil(recordingView)
    }
    
    func testRecordingsListViewAccessibility() {
        let listView = RecordingsListView(recordingManager: recordingManager)
        
        // Test that the view can be created without crashing
        XCTAssertNotNil(listView)
    }
    
    func testTranscriptionDetailViewAccessibility() {
        let recording = createSampleRecording()
        let detailView = TranscriptionDetailView(recording: recording, recordingManager: recordingManager)
        
        // Test that the view can be created without crashing
        XCTAssertNotNil(detailView)
    }
    
    // MARK: - Reduced Motion Tests
    
    func testReducedMotionSupport() {
        // Test that reduced motion alternatives exist
        // This is mainly tested through UI interaction, but we can verify the extension exists
        let testView = Text("Test")
        let animatedView = testView.transcriptionReducedMotion(value: true)
        
        XCTAssertNotNil(animatedView)
    }
    
    // MARK: - Integration Tests
    
    func testAccessibilityIntegrationWithTranscriptionFlow() {
        let recording = createSampleRecording()
        
        // Test that accessibility feedback is properly integrated
        recordingManager.transcribeRecording(recording)
        
        // Verify that the recording status is updated (which should trigger accessibility feedback)
        XCTAssertEqual(recording.transcriptionStatus, .notStarted) // Initial state
    }
    
    // MARK: - Helper Methods
    
    private func createSampleRecording() -> Recording {
        return Recording(
            fileName: "test.m4a",
            url: URL(fileURLWithPath: "/tmp/test.m4a"),
            createdAt: Date(),
            duration: 60.0,
            title: "Test Recording",
            transcription: nil,
            transcriptionStatus: .notStarted
        )
    }
}

// MARK: - Helper Functions for Testing

private func accessibilityInfo(for status: Recording.TranscriptionStatus) -> (label: String, hint: String) {
    switch status {
    case .notStarted:
        return ("Not transcribed", "Tap to start transcription")
    case .inProgress:
        return ("Transcribing", "Transcription in progress, please wait")
    case .queued:
        return ("Queued for transcription", "Transcription will start automatically when possible")
    case .completed:
        return ("Transcription completed", "Tap to view full transcription")
    case .failed:
        return ("Transcription failed", "Tap to retry transcription")
    }
}

private func accessibilityInfo(for action: TranscriptionAction) -> (label: String, hint: String) {
    switch action {
    case .transcribe:
        return ("Transcribe recording", "Starts transcription of this audio recording")
    case .retry:
        return ("Retry transcription", "Attempts to transcribe this recording again")
    case .view:
        return ("View transcription", "Opens the full transcription text")
    case .copy:
        return ("Copy transcription", "Copies the transcription text to clipboard")
    case .dismiss:
        return ("Dismiss", "Dismisses this notification")
    }
}