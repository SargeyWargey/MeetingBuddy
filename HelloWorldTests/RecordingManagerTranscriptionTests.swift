import XCTest
@testable import HelloWorld
import AVFoundation

@MainActor
final class RecordingManagerTranscriptionTests: XCTestCase {
    
    var recordingManager: RecordingManager!
    var mockTranscriptionService: MockTranscriptionService!
    
    override func setUp() {
        super.setUp()
        recordingManager = RecordingManager()
        mockTranscriptionService = MockTranscriptionService()
        recordingManager.transcriptionService = mockTranscriptionService
    }
    
    override func tearDown() {
        recordingManager = nil
        mockTranscriptionService = nil
        super.tearDown()
    }
    
    // MARK: - Auto Transcription Tests
    
    func testAutoTranscriptionTriggeredAfterRecording() {
        // Given
        recordingManager.transcriptionPermissionGranted = true
        recordingManager.isTranscriptionAvailable = true
        mockTranscriptionService.shouldSucceed = true
        mockTranscriptionService.mockResult = TranscriptionResult(
            text: "Test transcription",
            confidence: 0.95,
            processingTime: 1.0,
            method: .onDevice
        )
        
        // When
        let recording = createTestRecording()
        recordingManager.recordings.insert(recording, at: 0)
        
        // Simulate the auto transcription trigger
        recordingManager.transcribeRecording(recording)
        
        // Then
        let expectation = XCTestExpectation(description: "Auto transcription completed")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.mockTranscriptionService.transcribeCalled)
            XCTAssertEqual(self.mockTranscriptionService.lastTranscribedRecording?.id, recording.id)
            
            // Check that recording was updated with transcription
            if let updatedRecording = self.recordingManager.recordings.first(where: { $0.id == recording.id }) {
                XCTAssertEqual(updatedRecording.transcription, "Test transcription")
                XCTAssertEqual(updatedRecording.transcriptionStatus, .completed)
                XCTAssertNil(updatedRecording.transcriptionError)
            } else {
                XCTFail("Recording not found after transcription")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testAutoTranscriptionSkippedWhenPermissionDenied() {
        // Given
        recordingManager.transcriptionPermissionGranted = false
        recordingManager.isTranscriptionAvailable = true
        
        // When
        let recording = createTestRecording()
        recordingManager.transcribeRecording(recording)
        
        // Then
        XCTAssertFalse(mockTranscriptionService.transcribeCalled)
        XCTAssertNotNil(recordingManager.errorMessage)
        XCTAssertTrue(recordingManager.errorMessage!.contains("permission"))
    }
    
    func testAutoTranscriptionSkippedWhenServiceUnavailable() {
        // Given
        recordingManager.transcriptionPermissionGranted = true
        recordingManager.isTranscriptionAvailable = false
        
        // When
        let recording = createTestRecording()
        recordingManager.transcribeRecording(recording)
        
        // Then
        XCTAssertFalse(mockTranscriptionService.transcribeCalled)
        XCTAssertNotNil(recordingManager.errorMessage)
        XCTAssertTrue(recordingManager.errorMessage!.contains("not available"))
    }
    
    // MARK: - Manual Transcription Tests
    
    func testManualTranscriptionSuccess() {
        // Given
        recordingManager.transcriptionPermissionGranted = true
        recordingManager.isTranscriptionAvailable = true
        mockTranscriptionService.shouldSucceed = true
        mockTranscriptionService.mockResult = TranscriptionResult(
            text: "Manual transcription result",
            confidence: 0.88,
            processingTime: 2.0,
            method: .cloud
        )
        
        let recording = createTestRecording()
        recordingManager.recordings.append(recording)
        
        // When
        recordingManager.transcribeRecording(recording)
        
        // Then
        let expectation = XCTestExpectation(description: "Manual transcription completed")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.mockTranscriptionService.transcribeCalled)
            
            if let updatedRecording = self.recordingManager.recordings.first(where: { $0.id == recording.id }) {
                XCTAssertEqual(updatedRecording.transcription, "Manual transcription result")
                XCTAssertEqual(updatedRecording.transcriptionStatus, .completed)
                XCTAssertNil(updatedRecording.transcriptionError)
            } else {
                XCTFail("Recording not found after manual transcription")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testManualTranscriptionFailure() {
        // Given
        recordingManager.transcriptionPermissionGranted = true
        recordingManager.isTranscriptionAvailable = true
        mockTranscriptionService.shouldSucceed = false
        mockTranscriptionService.mockError = TranscriptionError.networkUnavailable
        
        let recording = createTestRecording()
        recordingManager.recordings.append(recording)
        
        // When
        recordingManager.transcribeRecording(recording)
        
        // Then
        let expectation = XCTestExpectation(description: "Manual transcription failed")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.mockTranscriptionService.transcribeCalled)
            
            if let updatedRecording = self.recordingManager.recordings.first(where: { $0.id == recording.id }) {
                XCTAssertEqual(updatedRecording.transcriptionStatus, .failed)
                XCTAssertNotNil(updatedRecording.transcriptionError)
                XCTAssertTrue(updatedRecording.transcriptionError!.contains("Network"))
            } else {
                XCTFail("Recording not found after failed transcription")
            }
            
            XCTAssertNotNil(self.recordingManager.errorMessage)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Retry Transcription Tests
    
    func testRetryTranscriptionSuccess() {
        // Given
        recordingManager.transcriptionPermissionGranted = true
        recordingManager.isTranscriptionAvailable = true
        mockTranscriptionService.shouldSucceed = true
        mockTranscriptionService.mockResult = TranscriptionResult(
            text: "Retry transcription success",
            confidence: 0.92,
            processingTime: 1.5,
            method: .onDevice
        )
        
        var recording = createTestRecording()
        recording.transcriptionStatus = .failed
        recording.transcriptionError = "Previous error"
        recordingManager.recordings.append(recording)
        
        // When
        recordingManager.retryTranscription(recording)
        
        // Then
        let expectation = XCTestExpectation(description: "Retry transcription completed")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.mockTranscriptionService.retryTranscriptionCalled)
            
            if let updatedRecording = self.recordingManager.recordings.first(where: { $0.id == recording.id }) {
                XCTAssertEqual(updatedRecording.transcription, "Retry transcription success")
                XCTAssertEqual(updatedRecording.transcriptionStatus, .completed)
                XCTAssertNil(updatedRecording.transcriptionError)
            } else {
                XCTFail("Recording not found after retry transcription")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Queue Management Tests
    
    func testQueueTranscription() {
        // Given
        let recording = createTestRecording()
        recordingManager.recordings.append(recording)
        
        // When
        recordingManager.queueTranscription(recording)
        
        // Then
        XCTAssertTrue(mockTranscriptionService.queueTranscriptionCalled)
        XCTAssertEqual(mockTranscriptionService.lastQueuedRecording?.id, recording.id)
        
        if let updatedRecording = recordingManager.recordings.first(where: { $0.id == recording.id }) {
            XCTAssertEqual(updatedRecording.transcriptionStatus, .queued)
        } else {
            XCTFail("Recording not found after queueing")
        }
    }
    
    func testCancelTranscription() {
        // Given
        let recording = createTestRecording()
        recordingManager.recordings.append(recording)
        
        // When
        recordingManager.cancelTranscription(recording)
        
        // Then
        XCTAssertTrue(mockTranscriptionService.cancelTranscriptionCalled)
        XCTAssertEqual(mockTranscriptionService.lastCancelledRecording?.id, recording.id)
        
        if let updatedRecording = recordingManager.recordings.first(where: { $0.id == recording.id }) {
            XCTAssertEqual(updatedRecording.transcriptionStatus, .notStarted)
        } else {
            XCTFail("Recording not found after cancellation")
        }
    }
    
    func testProcessTranscriptionQueue() {
        // When
        recordingManager.processTranscriptionQueue()
        
        // Then
        let expectation = XCTestExpectation(description: "Queue processing started")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.mockTranscriptionService.processQueueCalled)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Permission Tests
    
    func testRequestTranscriptionPermissions() {
        // Given
        mockTranscriptionService.mockPermissionResult = true
        
        // When
        recordingManager.requestTranscriptionPermissions()
        
        // Then
        let expectation = XCTestExpectation(description: "Permission request completed")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.mockTranscriptionService.requestPermissionsCalled)
            XCTAssertTrue(self.recordingManager.transcriptionPermissionGranted)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testRequestTranscriptionPermissionsDenied() {
        // Given
        mockTranscriptionService.mockPermissionResult = false
        
        // When
        recordingManager.requestTranscriptionPermissions()
        
        // Then
        let expectation = XCTestExpectation(description: "Permission request denied")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.mockTranscriptionService.requestPermissionsCalled)
            XCTAssertFalse(self.recordingManager.transcriptionPermissionGranted)
            XCTAssertNotNil(self.recordingManager.errorMessage)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Helper Methods
    
    private func createTestRecording() -> Recording {
        let url = URL(fileURLWithPath: "/tmp/test_recording.m4a")
        return Recording(
            fileName: "test_recording.m4a",
            url: url,
            createdAt: Date(),
            duration: 30.0,
            title: "Test Recording"
        )
    }
}

// MARK: - Mock Transcription Service

class MockTranscriptionService: TranscriptionService {
    
    // Mock properties
    var shouldSucceed = true
    var mockResult: TranscriptionResult?
    var mockError: TranscriptionError?
    var mockPermissionResult = true
    
    // Call tracking
    var transcribeCalled = false
    var retryTranscriptionCalled = false
    var queueTranscriptionCalled = false
    var cancelTranscriptionCalled = false
    var requestPermissionsCalled = false
    var processQueueCalled = false
    
    // Last called parameters
    var lastTranscribedRecording: Recording?
    var lastQueuedRecording: Recording?
    var lastCancelledRecording: Recording?
    
    override var isAvailable: Bool {
        return true
    }
    
    override var isOnDeviceAvailable: Bool {
        return true
    }
    
    override var isCloudAvailable: Bool {
        return true
    }
    
    override func transcribe(_ recording: Recording) async throws -> TranscriptionResult {
        transcribeCalled = true
        lastTranscribedRecording = recording
        
        if shouldSucceed, let result = mockResult {
            return result
        } else if let error = mockError {
            throw error
        } else {
            throw TranscriptionError.unknownError("Mock error")
        }
    }
    
    override func retryTranscription(_ recording: Recording) async throws -> TranscriptionResult {
        retryTranscriptionCalled = true
        return try await transcribe(recording)
    }
    
    override func queueTranscription(_ recording: Recording) {
        queueTranscriptionCalled = true
        lastQueuedRecording = recording
    }
    
    override func cancelTranscription(_ recording: Recording) {
        cancelTranscriptionCalled = true
        lastCancelledRecording = recording
    }
    
    override func requestPermissions() async -> Bool {
        requestPermissionsCalled = true
        return mockPermissionResult
    }
    
    override func hasPermissions() -> Bool {
        return mockPermissionResult
    }
    
    override func processQueue() async {
        processQueueCalled = true
    }
}