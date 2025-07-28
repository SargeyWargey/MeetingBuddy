import Testing
import Foundation
@testable import HelloWorld

struct TranscriptionErrorTests {
    
    // MARK: - Error Description Tests
    
    @Test func testTranscriptionErrorDescriptions() async throws {
        #expect(TranscriptionError.permissionDenied.errorDescription == "Speech recognition permission is required")
        #expect(TranscriptionError.audioFileNotFound.errorDescription == "Audio file could not be found")
        #expect(TranscriptionError.audioFormatUnsupported.errorDescription == "Audio format is not supported for transcription")
        #expect(TranscriptionError.networkUnavailable.errorDescription == "Network connection is required for transcription")
        #expect(TranscriptionError.serviceUnavailable.errorDescription == "Transcription service is currently unavailable")
        #expect(TranscriptionError.processingTimeout.errorDescription == "Transcription processing timed out")
        #expect(TranscriptionError.quotaExceeded.errorDescription == "Transcription quota has been exceeded")
        
        let unknownError = TranscriptionError.unknownError("Custom message")
        #expect(unknownError.errorDescription == "An unexpected error occurred: Custom message")
    }
    
    // MARK: - Recovery Suggestion Tests
    
    @Test func testTranscriptionErrorRecoverySuggestions() async throws {
        #expect(TranscriptionError.permissionDenied.recoverySuggestion == "Please enable Speech Recognition in Settings > Privacy & Security > Speech Recognition")
        #expect(TranscriptionError.audioFileNotFound.recoverySuggestion == "Try recording a new audio file")
        #expect(TranscriptionError.audioFormatUnsupported.recoverySuggestion == "Please use a supported audio format (M4A, WAV, MP3)")
        #expect(TranscriptionError.networkUnavailable.recoverySuggestion == "Check your internet connection and try again")
        #expect(TranscriptionError.serviceUnavailable.recoverySuggestion == "Please try again later")
        #expect(TranscriptionError.processingTimeout.recoverySuggestion == "Try transcribing a shorter audio file or check your connection")
        #expect(TranscriptionError.quotaExceeded.recoverySuggestion == "Please wait before making more transcription requests")
        #expect(TranscriptionError.unknownError("test").recoverySuggestion == "Please try again or contact support if the problem persists")
    }
    
    // MARK: - Failure Reason Tests
    
    @Test func testTranscriptionErrorFailureReasons() async throws {
        #expect(TranscriptionError.permissionDenied.failureReason == "The app does not have permission to use speech recognition")
        #expect(TranscriptionError.audioFileNotFound.failureReason == "The specified audio file does not exist")
        #expect(TranscriptionError.audioFormatUnsupported.failureReason == "The audio file format is not compatible with the transcription service")
        #expect(TranscriptionError.networkUnavailable.failureReason == "No internet connection is available")
        #expect(TranscriptionError.serviceUnavailable.failureReason == "The transcription service is temporarily unavailable")
        #expect(TranscriptionError.processingTimeout.failureReason == "The transcription request took too long to complete")
        #expect(TranscriptionError.quotaExceeded.failureReason == "Too many transcription requests have been made")
        #expect(TranscriptionError.unknownError("test").failureReason == "An internal error occurred")
    }
    
    // MARK: - Equatable Tests
    
    @Test func testTranscriptionErrorEquality() async throws {
        // Test same error types are equal
        #expect(TranscriptionError.permissionDenied == TranscriptionError.permissionDenied)
        #expect(TranscriptionError.audioFileNotFound == TranscriptionError.audioFileNotFound)
        #expect(TranscriptionError.networkUnavailable == TranscriptionError.networkUnavailable)
        
        // Test different error types are not equal
        #expect(TranscriptionError.permissionDenied != TranscriptionError.audioFileNotFound)
        #expect(TranscriptionError.networkUnavailable != TranscriptionError.serviceUnavailable)
        
        // Test unknown errors with same message are equal
        let unknownError1 = TranscriptionError.unknownError("Same message")
        let unknownError2 = TranscriptionError.unknownError("Same message")
        #expect(unknownError1 == unknownError2)
        
        // Test unknown errors with different messages are not equal
        let unknownError3 = TranscriptionError.unknownError("Different message")
        #expect(unknownError1 != unknownError3)
        
        // Test unknown error is not equal to other error types
        #expect(unknownError1 != TranscriptionError.permissionDenied)
    }
}

struct TranscriptionResultTests {
    
    // MARK: - Initialization Tests
    
    @Test func testTranscriptionResultInitialization() async throws {
        let result = TranscriptionResult(
            text: "Hello world",
            confidence: 0.95,
            processingTime: 2.5,
            method: .onDevice
        )
        
        #expect(result.text == "Hello world")
        #expect(result.confidence == 0.95)
        #expect(result.processingTime == 2.5)
        #expect(result.method == .onDevice)
        #expect(result.metadata == nil)
    }
    
    @Test func testTranscriptionResultInitializationWithMetadata() async throws {
        let metadata = ["language": "en-US", "model": "latest"]
        let result = TranscriptionResult(
            text: "Test",
            confidence: 0.8,
            processingTime: 1.0,
            method: .cloud,
            metadata: metadata
        )
        
        #expect(result.metadata?["language"] == "en-US")
        #expect(result.metadata?["model"] == "latest")
    }
    
    @Test func testConfidenceClampingInInitialization() async throws {
        // Test confidence above 1.0 is clamped to 1.0
        let highConfidenceResult = TranscriptionResult(
            text: "Test",
            confidence: 1.5,
            processingTime: 1.0,
            method: .onDevice
        )
        #expect(highConfidenceResult.confidence == 1.0)
        
        // Test confidence below 0.0 is clamped to 0.0
        let lowConfidenceResult = TranscriptionResult(
            text: "Test",
            confidence: -0.5,
            processingTime: 1.0,
            method: .onDevice
        )
        #expect(lowConfidenceResult.confidence == 0.0)
        
        // Test valid confidence remains unchanged
        let validConfidenceResult = TranscriptionResult(
            text: "Test",
            confidence: 0.75,
            processingTime: 1.0,
            method: .onDevice
        )
        #expect(validConfidenceResult.confidence == 0.75)
    }
    
    // MARK: - Computed Properties Tests
    
    @Test func testIsHighConfidenceProperty() async throws {
        let highConfidenceResult = TranscriptionResult(
            text: "Test",
            confidence: 0.8,
            processingTime: 1.0,
            method: .onDevice
        )
        #expect(highConfidenceResult.isHighConfidence == true)
        
        let lowConfidenceResult = TranscriptionResult(
            text: "Test",
            confidence: 0.6,
            processingTime: 1.0,
            method: .onDevice
        )
        #expect(lowConfidenceResult.isHighConfidence == false)
        
        let exactThresholdResult = TranscriptionResult(
            text: "Test",
            confidence: 0.7,
            processingTime: 1.0,
            method: .onDevice
        )
        #expect(exactThresholdResult.isHighConfidence == true)
    }
    
    @Test func testIsEmptyProperty() async throws {
        let emptyResult = TranscriptionResult(
            text: "",
            confidence: 1.0,
            processingTime: 1.0,
            method: .onDevice
        )
        #expect(emptyResult.isEmpty == true)
        
        let whitespaceResult = TranscriptionResult(
            text: "   \n\t  ",
            confidence: 1.0,
            processingTime: 1.0,
            method: .onDevice
        )
        #expect(whitespaceResult.isEmpty == true)
        
        let nonEmptyResult = TranscriptionResult(
            text: "Hello world",
            confidence: 1.0,
            processingTime: 1.0,
            method: .onDevice
        )
        #expect(nonEmptyResult.isEmpty == false)
    }
    
    @Test func testPreviewTextMethod() async throws {
        // Test short text returns as-is
        let shortResult = TranscriptionResult(
            text: "Short text",
            confidence: 1.0,
            processingTime: 1.0,
            method: .onDevice
        )
        #expect(shortResult.previewText() == "Short text")
        
        // Test long text is truncated
        let longText = String(repeating: "A", count: 150)
        let longResult = TranscriptionResult(
            text: longText,
            confidence: 1.0,
            processingTime: 1.0,
            method: .onDevice
        )
        let expectedPreview = String(repeating: "A", count: 100) + "..."
        #expect(longResult.previewText() == expectedPreview)
        
        // Test custom max length
        #expect(longResult.previewText(maxLength: 50) == String(repeating: "A", count: 50) + "...")
        
        // Test text with whitespace is trimmed
        let whitespaceResult = TranscriptionResult(
            text: "  Hello world  ",
            confidence: 1.0,
            processingTime: 1.0,
            method: .onDevice
        )
        #expect(whitespaceResult.previewText() == "Hello world")
    }
    
    // MARK: - Codable Tests
    
    @Test func testTranscriptionResultCodable() async throws {
        let originalResult = TranscriptionResult(
            text: "Test transcription",
            confidence: 0.85,
            processingTime: 2.5,
            method: .cloud,
            metadata: ["language": "en-US"]
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(originalResult)
        let decodedResult = try decoder.decode(TranscriptionResult.self, from: data)
        
        #expect(decodedResult.text == originalResult.text)
        #expect(decodedResult.confidence == originalResult.confidence)
        #expect(decodedResult.processingTime == originalResult.processingTime)
        #expect(decodedResult.method == originalResult.method)
        #expect(decodedResult.metadata?["language"] == originalResult.metadata?["language"])
    }
    
    // MARK: - Equatable Tests
    
    @Test func testTranscriptionResultEquality() async throws {
        let result1 = TranscriptionResult(
            text: "Same text",
            confidence: 0.8,
            processingTime: 1.0,
            method: .onDevice
        )
        
        let result2 = TranscriptionResult(
            text: "Same text",
            confidence: 0.8,
            processingTime: 1.0,
            method: .onDevice
        )
        
        // Note: These won't be equal due to different timestamps, but we can test individual properties
        #expect(result1.text == result2.text)
        #expect(result1.confidence == result2.confidence)
        #expect(result1.method == result2.method)
    }
}

struct TranscriptionMethodTests {
    
    // MARK: - Raw Value Tests
    
    @Test func testTranscriptionMethodRawValues() async throws {
        #expect(TranscriptionMethod.onDevice.rawValue == "on_device")
        #expect(TranscriptionMethod.cloud.rawValue == "cloud")
        #expect(TranscriptionMethod.cached.rawValue == "cached")
    }
    
    // MARK: - Display Name Tests
    
    @Test func testTranscriptionMethodDisplayNames() async throws {
        #expect(TranscriptionMethod.onDevice.displayName == "On-Device")
        #expect(TranscriptionMethod.cloud.displayName == "Cloud")
        #expect(TranscriptionMethod.cached.displayName == "Cached")
    }
    
    // MARK: - Offline Capability Tests
    
    @Test func testTranscriptionMethodOfflineCapability() async throws {
        #expect(TranscriptionMethod.onDevice.isOfflineCapable == true)
        #expect(TranscriptionMethod.cloud.isOfflineCapable == false)
        #expect(TranscriptionMethod.cached.isOfflineCapable == true)
    }
    
    // MARK: - Case Iteration Tests
    
    @Test func testTranscriptionMethodCaseIterable() async throws {
        let allCases = TranscriptionMethod.allCases
        #expect(allCases.count == 3)
        #expect(allCases.contains(.onDevice))
        #expect(allCases.contains(.cloud))
        #expect(allCases.contains(.cached))
    }
}

@MainActor
struct TranscriptionServiceTests {
    
    // MARK: - Initialization Tests
    
    @Test func testTranscriptionServiceInitialization() async throws {
        let service = TranscriptionService()
        #expect(service.queueCount == 0)
        #expect(service.isProcessingQueue == false)
    }
    
    // MARK: - Queue Management Tests
    
    @Test func testQueueTranscription() async throws {
        let service = TranscriptionService()
        let recording = createTestRecording()
        
        service.queueTranscription(recording)
        #expect(service.queueCount == 1)
        
        // Test duplicate prevention
        service.queueTranscription(recording)
        #expect(service.queueCount == 1)
    }
    
    @Test func testClearQueue() async throws {
        let service = TranscriptionService()
        let recording1 = createTestRecording()
        let recording2 = createTestRecording()
        
        service.queueTranscription(recording1)
        service.queueTranscription(recording2)
        #expect(service.queueCount == 2)
        
        service.clearQueue()
        #expect(service.queueCount == 0)
    }
    
    @Test func testCancelTranscription() async throws {
        let service = TranscriptionService()
        let recording = createTestRecording()
        
        service.queueTranscription(recording)
        #expect(service.queueCount == 1)
        
        service.cancelTranscription(recording)
        #expect(service.queueCount == 0)
    }
    
    // MARK: - Helper Methods
    
    private func createTestRecording() -> Recording {
        let testURL = URL(fileURLWithPath: "/tmp/test_\(UUID().uuidString).m4a")
        return Recording(
            fileName: "test.m4a",
            url: testURL,
            createdAt: Date(),
            duration: 60.0,
            title: "Test Recording"
        )
    }
}