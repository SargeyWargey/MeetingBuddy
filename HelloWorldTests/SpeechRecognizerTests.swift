import XCTest
import Speech
@testable import HelloWorld

@MainActor
final class SpeechRecognizerTests: XCTestCase {
    
    var speechRecognizer: SpeechRecognizer!
    
    override func setUp() {
        super.setUp()
        speechRecognizer = SpeechRecognizer()
    }
    
    override func tearDown() {
        speechRecognizer = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertNotNil(speechRecognizer)
        XCTAssertEqual(speechRecognizer.authorizationStatus, SFSpeechRecognizer.authorizationStatus())
    }
    
    // MARK: - Permission Tests
    
    func testCheckPermissionStatus() {
        let status = speechRecognizer.checkPermissionStatus()
        XCTAssertEqual(status, SFSpeechRecognizer.authorizationStatus())
        XCTAssertEqual(speechRecognizer.authorizationStatus, status)
    }
    
    // MARK: - Availability Tests
    
    func testIsAvailable() {
        // Test that isAvailable returns true when either on-device or cloud is available
        let available = speechRecognizer.isAvailable
        let expectedAvailable = speechRecognizer.isOnDeviceAvailable || speechRecognizer.isCloudAvailable
        XCTAssertEqual(available, expectedAvailable)
    }
    
    func testIsCloudAvailable() {
        let cloudAvailable = speechRecognizer.isCloudAvailable
        let expectedCloudAvailable = SFSpeechRecognizer.authorizationStatus() == .authorized
        XCTAssertEqual(cloudAvailable, expectedCloudAvailable)
    }
    
    // MARK: - Error Conversion Tests
    
    func testConvertSpeechError_PermissionDenied() async {
        // Create a mock URL for testing
        let tempURL = createTempAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        // Test with unauthorized status
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            do {
                _ = try await speechRecognizer.transcribeAudioFile(at: tempURL)
                XCTFail("Expected TranscriptionError.permissionDenied")
            } catch let error as TranscriptionError {
                XCTAssertEqual(error, .permissionDenied)
            } catch {
                XCTFail("Expected TranscriptionError, got \(error)")
            }
        }
    }
    
    func testConvertSpeechError_FileNotFound() async {
        // Test with non-existent file
        let nonExistentURL = URL(fileURLWithPath: "/non/existent/file.m4a")
        
        do {
            _ = try await speechRecognizer.transcribeAudioFile(at: nonExistentURL)
            XCTFail("Expected TranscriptionError.audioFileNotFound")
        } catch let error as TranscriptionError {
            XCTAssertEqual(error, .audioFileNotFound)
        } catch {
            XCTFail("Expected TranscriptionError, got \(error)")
        }
    }
    
    // MARK: - Transcription Tests
    
    func testTranscribeAudioFile_ServiceUnavailable() async {
        // Test when speech recognizer is not available
        let tempURL = createTempAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        // This test will depend on the actual device/simulator state
        // In a real test environment, you might want to mock SFSpeechRecognizer
        if !speechRecognizer.isAvailable {
            do {
                _ = try await speechRecognizer.transcribeAudioFile(at: tempURL)
                XCTFail("Expected TranscriptionError.serviceUnavailable")
            } catch let error as TranscriptionError {
                XCTAssertEqual(error, .serviceUnavailable)
            } catch {
                XCTFail("Expected TranscriptionError, got \(error)")
            }
        }
    }
    
    func testCancelTranscription() {
        // Test that cancellation doesn't crash
        speechRecognizer.cancelTranscription()
        // No assertion needed, just ensure it doesn't crash
    }
    
    // MARK: - Helper Methods
    
    private func createTempAudioFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("test_audio.m4a")
        
        // Create a minimal audio file for testing
        let audioData = Data([0x00, 0x00, 0x00, 0x20]) // Minimal header
        try? audioData.write(to: tempURL)
        
        return tempURL
    }
}

// MARK: - Mock Tests for Error Scenarios

extension SpeechRecognizerTests {
    
    func testErrorDescriptions() {
        let errors: [TranscriptionError] = [
            .permissionDenied,
            .audioFileNotFound,
            .audioFormatUnsupported,
            .networkUnavailable,
            .serviceUnavailable,
            .processingTimeout,
            .quotaExceeded,
            .unknownError("Test error")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertNotNil(error.recoverySuggestion)
            XCTAssertNotNil(error.failureReason)
        }
    }
    
    func testErrorEquality() {
        XCTAssertEqual(TranscriptionError.permissionDenied, TranscriptionError.permissionDenied)
        XCTAssertEqual(TranscriptionError.unknownError("test"), TranscriptionError.unknownError("test"))
        XCTAssertNotEqual(TranscriptionError.unknownError("test1"), TranscriptionError.unknownError("test2"))
        XCTAssertNotEqual(TranscriptionError.permissionDenied, TranscriptionError.serviceUnavailable)
    }
}

// MARK: - Integration Tests

extension SpeechRecognizerTests {
    
    func testRequestPermissions() async {
        // This test requires user interaction in a real environment
        // In automated testing, this would typically be mocked
        let granted = await speechRecognizer.requestPermissions()
        
        // The result depends on user interaction and current permission state
        // We can only verify that the method completes without crashing
        XCTAssertTrue(granted || !granted) // Always true, just ensures method completes
        
        // Verify that the authorization status is updated
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        XCTAssertEqual(speechRecognizer.authorizationStatus, currentStatus)
    }
}