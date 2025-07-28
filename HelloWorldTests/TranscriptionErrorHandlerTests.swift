import XCTest
@testable import HelloWorld

@MainActor
final class TranscriptionErrorHandlerTests: XCTestCase {
    
    var errorHandler: TranscriptionErrorHandler!
    var testRecordingId: UUID!
    
    override func setUp() {
        super.setUp()
        errorHandler = TranscriptionErrorHandler()
        testRecordingId = UUID()
    }
    
    override func tearDown() {
        errorHandler = nil
        testRecordingId = nil
        super.tearDown()
    }
    
    // MARK: - Error Handling Tests
    
    func testHandlePermissionDeniedError() {
        // Given
        let error = TranscriptionError.permissionDenied
        
        // When
        errorHandler.handleError(error, for: testRecordingId, context: "Test")
        
        // Then
        XCTAssertEqual(errorHandler.currentError, error)
        XCTAssertEqual(errorHandler.errorBanners.count, 1)
        XCTAssertEqual(errorHandler.errorBanners.first?.error, error)
        XCTAssertEqual(errorHandler.errorBanners.first?.recordingId, testRecordingId)
    }
    
    func testHandleNetworkUnavailableError() {
        // Given
        let error = TranscriptionError.networkUnavailable
        
        // When
        errorHandler.handleError(error, for: testRecordingId, context: "Test")
        
        // Then
        XCTAssertEqual(errorHandler.currentError, error)
        XCTAssertTrue(errorHandler.errorBanners.count > 0)
    }
    
    func testHandleServiceUnavailableWithAutoRetry() {
        // Given
        let error = TranscriptionError.serviceUnavailable
        
        // When
        errorHandler.handleError(error, for: testRecordingId, context: "Test")
        
        // Then
        XCTAssertEqual(errorHandler.getRetryCount(for: testRecordingId), 0)
        XCTAssertTrue(error.canRetry)
        XCTAssertFalse(error.requiresUserAction)
    }
    
    func testMaxRetryAttemptsReached() {
        // Given
        let error = TranscriptionError.serviceUnavailable
        
        // When - Simulate multiple retry attempts
        for i in 0..<4 {
            errorHandler.handleError(error, for: testRecordingId, context: "Attempt \(i)")
        }
        
        // Then
        XCTAssertTrue(errorHandler.hasReachedMaxRetries(for: testRecordingId))
        XCTAssertEqual(errorHandler.getRetryCount(for: testRecordingId), 3)
    }
    
    func testHandleSuccess() {
        // Given
        let error = TranscriptionError.networkUnavailable
        errorHandler.handleError(error, for: testRecordingId, context: "Test")
        
        // When
        errorHandler.handleSuccess(for: testRecordingId)
        
        // Then
        XCTAssertEqual(errorHandler.getRetryCount(for: testRecordingId), 0)
        XCTAssertTrue(errorHandler.errorBanners.isEmpty)
        XCTAssertNil(errorHandler.currentError)
    }
    
    // MARK: - Error Action Tests
    
    func testProcessRetryAction() {
        // Given
        let error = TranscriptionError.serviceUnavailable
        errorHandler.handleError(error, for: testRecordingId, context: "Test")
        
        // When
        errorHandler.processErrorAction(.retry, for: error, recordingId: testRecordingId)
        
        // Then
        XCTAssertEqual(errorHandler.getRetryCount(for: testRecordingId), 0) // Reset on manual retry
        XCTAssertNil(errorHandler.currentError)
        XCTAssertTrue(errorHandler.errorBanners.isEmpty)
    }
    
    func testProcessDismissAction() {
        // Given
        let error = TranscriptionError.permissionDenied
        errorHandler.handleError(error, for: testRecordingId, context: "Test")
        
        // When
        errorHandler.processErrorAction(.dismiss, for: error, recordingId: testRecordingId)
        
        // Then
        XCTAssertNil(errorHandler.currentError)
        XCTAssertTrue(errorHandler.errorBanners.isEmpty)
    }
    
    // MARK: - Error Banner Tests
    
    func testGetErrorBannersForRecording() {
        // Given
        let error1 = TranscriptionError.networkUnavailable
        let error2 = TranscriptionError.serviceUnavailable
        let otherRecordingId = UUID()
        
        errorHandler.handleError(error1, for: testRecordingId, context: "Test 1")
        errorHandler.handleError(error2, for: otherRecordingId, context: "Test 2")
        
        // When
        let bannersForTestRecording = errorHandler.getErrorBanners(for: testRecordingId)
        let bannersForOtherRecording = errorHandler.getErrorBanners(for: otherRecordingId)
        
        // Then
        XCTAssertEqual(bannersForTestRecording.count, 1)
        XCTAssertEqual(bannersForTestRecording.first?.error, error1)
        XCTAssertEqual(bannersForOtherRecording.count, 1)
        XCTAssertEqual(bannersForOtherRecording.first?.error, error2)
    }
    
    func testClearAllErrors() {
        // Given
        let error = TranscriptionError.networkUnavailable
        errorHandler.handleError(error, for: testRecordingId, context: "Test")
        
        // When
        errorHandler.clearAllErrors()
        
        // Then
        XCTAssertNil(errorHandler.currentError)
        XCTAssertTrue(errorHandler.errorBanners.isEmpty)
        XCTAssertTrue(errorHandler.retryAttempts.isEmpty)
    }
    
    // MARK: - Error Properties Tests
    
    func testErrorCanRetryProperty() {
        XCTAssertTrue(TranscriptionError.networkUnavailable.canRetry)
        XCTAssertTrue(TranscriptionError.serviceUnavailable.canRetry)
        XCTAssertTrue(TranscriptionError.processingTimeout.canRetry)
        XCTAssertTrue(TranscriptionError.quotaExceeded.canRetry)
        XCTAssertTrue(TranscriptionError.noSpeechDetected.canRetry)
        XCTAssertTrue(TranscriptionError.microphoneUnavailable.canRetry)
        XCTAssertTrue(TranscriptionError.unknownError("test").canRetry)
        
        XCTAssertFalse(TranscriptionError.permissionDenied.canRetry)
        XCTAssertFalse(TranscriptionError.audioFileNotFound.canRetry)
        XCTAssertFalse(TranscriptionError.audioFormatUnsupported.canRetry)
        XCTAssertFalse(TranscriptionError.audioTooShort.canRetry)
        XCTAssertFalse(TranscriptionError.audioTooLong.canRetry)
        XCTAssertFalse(TranscriptionError.languageNotSupported.canRetry)
        XCTAssertFalse(TranscriptionError.deviceStorageFull.canRetry)
    }
    
    func testErrorRequiresUserActionProperty() {
        XCTAssertTrue(TranscriptionError.permissionDenied.requiresUserAction)
        XCTAssertTrue(TranscriptionError.audioFormatUnsupported.requiresUserAction)
        XCTAssertTrue(TranscriptionError.languageNotSupported.requiresUserAction)
        XCTAssertTrue(TranscriptionError.deviceStorageFull.requiresUserAction)
        XCTAssertTrue(TranscriptionError.microphoneUnavailable.requiresUserAction)
        
        XCTAssertFalse(TranscriptionError.networkUnavailable.requiresUserAction)
        XCTAssertFalse(TranscriptionError.serviceUnavailable.requiresUserAction)
        XCTAssertFalse(TranscriptionError.processingTimeout.requiresUserAction)
        XCTAssertFalse(TranscriptionError.quotaExceeded.requiresUserAction)
        XCTAssertFalse(TranscriptionError.audioTooShort.requiresUserAction)
        XCTAssertFalse(TranscriptionError.audioTooLong.requiresUserAction)
        XCTAssertFalse(TranscriptionError.noSpeechDetected.requiresUserAction)
        XCTAssertFalse(TranscriptionError.unknownError("test").requiresUserAction)
    }
    
    func testErrorPrimaryActions() {
        XCTAssertEqual(TranscriptionError.permissionDenied.primaryAction, .openSettings)
        XCTAssertEqual(TranscriptionError.audioFileNotFound.primaryAction, .recordAgain)
        XCTAssertEqual(TranscriptionError.audioFormatUnsupported.primaryAction, .recordAgain)
        XCTAssertEqual(TranscriptionError.networkUnavailable.primaryAction, .waitForConnection)
        XCTAssertEqual(TranscriptionError.serviceUnavailable.primaryAction, .retry)
        XCTAssertEqual(TranscriptionError.processingTimeout.primaryAction, .retry)
        XCTAssertEqual(TranscriptionError.quotaExceeded.primaryAction, .waitForReset)
        XCTAssertEqual(TranscriptionError.audioTooShort.primaryAction, .recordAgain)
        XCTAssertEqual(TranscriptionError.audioTooLong.primaryAction, .recordShorter)
        XCTAssertEqual(TranscriptionError.noSpeechDetected.primaryAction, .retry)
        XCTAssertEqual(TranscriptionError.languageNotSupported.primaryAction, .openSettings)
        XCTAssertEqual(TranscriptionError.deviceStorageFull.primaryAction, .freeStorage)
        XCTAssertEqual(TranscriptionError.microphoneUnavailable.primaryAction, .checkMicrophone)
        XCTAssertEqual(TranscriptionError.unknownError("test").primaryAction, .retry)
    }
    
    func testErrorColors() {
        XCTAssertEqual(TranscriptionError.permissionDenied.errorColor, .warning)
        XCTAssertEqual(TranscriptionError.audioFileNotFound.errorColor, .info)
        XCTAssertEqual(TranscriptionError.networkUnavailable.errorColor, .offline)
        XCTAssertEqual(TranscriptionError.serviceUnavailable.errorColor, .error)
        XCTAssertEqual(TranscriptionError.processingTimeout.errorColor, .error)
        XCTAssertEqual(TranscriptionError.quotaExceeded.errorColor, .error)
        XCTAssertEqual(TranscriptionError.audioTooShort.errorColor, .info)
        XCTAssertEqual(TranscriptionError.audioTooLong.errorColor, .info)
        XCTAssertEqual(TranscriptionError.noSpeechDetected.errorColor, .error)
        XCTAssertEqual(TranscriptionError.languageNotSupported.errorColor, .warning)
        XCTAssertEqual(TranscriptionError.deviceStorageFull.errorColor, .warning)
        XCTAssertEqual(TranscriptionError.microphoneUnavailable.errorColor, .warning)
        XCTAssertEqual(TranscriptionError.unknownError("test").errorColor, .error)
    }
    
    func testErrorDescriptions() {
        XCTAssertEqual(TranscriptionError.permissionDenied.errorDescription, "Speech Recognition Permission Required")
        XCTAssertEqual(TranscriptionError.audioFileNotFound.errorDescription, "Audio File Not Found")
        XCTAssertEqual(TranscriptionError.networkUnavailable.errorDescription, "No Internet Connection")
        XCTAssertEqual(TranscriptionError.serviceUnavailable.errorDescription, "Transcription Service Unavailable")
        XCTAssertEqual(TranscriptionError.audioTooShort.errorDescription, "Audio Too Short")
        XCTAssertEqual(TranscriptionError.audioTooLong.errorDescription, "Audio Too Long")
        XCTAssertEqual(TranscriptionError.noSpeechDetected.errorDescription, "No Speech Detected")
        XCTAssertEqual(TranscriptionError.languageNotSupported.errorDescription, "Language Not Supported")
        XCTAssertEqual(TranscriptionError.deviceStorageFull.errorDescription, "Device Storage Full")
        XCTAssertEqual(TranscriptionError.microphoneUnavailable.errorDescription, "Microphone Unavailable")
    }
    
    func testErrorRecoverySuggestions() {
        XCTAssertNotNil(TranscriptionError.permissionDenied.recoverySuggestion)
        XCTAssertNotNil(TranscriptionError.networkUnavailable.recoverySuggestion)
        XCTAssertNotNil(TranscriptionError.audioTooShort.recoverySuggestion)
        XCTAssertNotNil(TranscriptionError.deviceStorageFull.recoverySuggestion)
        
        XCTAssertTrue(TranscriptionError.permissionDenied.recoverySuggestion!.contains("Settings"))
        XCTAssertTrue(TranscriptionError.audioTooShort.recoverySuggestion!.contains("3 seconds"))
        XCTAssertTrue(TranscriptionError.deviceStorageFull.recoverySuggestion!.contains("storage"))
    }
    
    // MARK: - Error Action Tests
    
    func testErrorActionProperties() {
        XCTAssertEqual(ErrorAction.retry.title, "Try Again")
        XCTAssertEqual(ErrorAction.openSettings.title, "Open Settings")
        XCTAssertEqual(ErrorAction.recordAgain.title, "Record Again")
        XCTAssertEqual(ErrorAction.dismiss.title, "Dismiss")
        
        XCTAssertEqual(ErrorAction.retry.iconName, "arrow.clockwise")
        XCTAssertEqual(ErrorAction.openSettings.iconName, "gear")
        XCTAssertEqual(ErrorAction.recordAgain.iconName, "mic.circle")
        XCTAssertEqual(ErrorAction.dismiss.iconName, "xmark")
        
        XCTAssertTrue(ErrorAction.dismiss.isDestructive)
        XCTAssertFalse(ErrorAction.retry.isDestructive)
        
        XCTAssertTrue(ErrorAction.retry.isPrimary)
        XCTAssertTrue(ErrorAction.openSettings.isPrimary)
        XCTAssertTrue(ErrorAction.recordAgain.isPrimary)
        XCTAssertFalse(ErrorAction.dismiss.isPrimary)
    }
    
    // MARK: - Error Logging Tests
    
    func testErrorLogEntry() {
        // Given
        let error = TranscriptionError.permissionDenied
        
        // When
        let logEntry = error.logEntry
        
        // Then
        XCTAssertEqual(logEntry["error_type"] as? String, "permissionDenied")
        XCTAssertEqual(logEntry["error_description"] as? String, error.errorDescription)
        XCTAssertEqual(logEntry["failure_reason"] as? String, error.failureReason)
        XCTAssertEqual(logEntry["recovery_suggestion"] as? String, error.recoverySuggestion)
        XCTAssertEqual(logEntry["can_retry"] as? Bool, error.canRetry)
        XCTAssertEqual(logEntry["requires_user_action"] as? Bool, error.requiresUserAction)
        XCTAssertEqual(logEntry["primary_action"] as? String, error.primaryAction?.title)
        XCTAssertNotNil(logEntry["timestamp"])
    }
    
    // MARK: - Notification Tests
    
    func testNotificationNames() {
        XCTAssertEqual(Notification.Name.transcriptionAutoRetry.rawValue, "transcriptionAutoRetry")
        XCTAssertEqual(Notification.Name.transcriptionManualRetry.rawValue, "transcriptionManualRetry")
        XCTAssertEqual(Notification.Name.switchToRecordingTab.rawValue, "switchToRecordingTab")
        XCTAssertEqual(Notification.Name.queueTranscriptionForOffline.rawValue, "queueTranscriptionForOffline")
    }
}

// MARK: - Error Action Tests

final class ErrorActionTests: XCTestCase {
    
    func testAllErrorActionsCovered() {
        let allActions = ErrorAction.allCases
        
        // Ensure we have all expected actions
        XCTAssertTrue(allActions.contains(.retry))
        XCTAssertTrue(allActions.contains(.openSettings))
        XCTAssertTrue(allActions.contains(.recordAgain))
        XCTAssertTrue(allActions.contains(.recordShorter))
        XCTAssertTrue(allActions.contains(.waitForConnection))
        XCTAssertTrue(allActions.contains(.waitForReset))
        XCTAssertTrue(allActions.contains(.queueForLater))
        XCTAssertTrue(allActions.contains(.freeStorage))
        XCTAssertTrue(allActions.contains(.checkMicrophone))
        XCTAssertTrue(allActions.contains(.dismiss))
        
        // Ensure each action has proper properties
        for action in allActions {
            XCTAssertFalse(action.title.isEmpty, "Action \(action) should have a title")
            XCTAssertFalse(action.iconName.isEmpty, "Action \(action) should have an icon name")
        }
    }
}

// MARK: - TranscriptionError Equatable Tests

final class TranscriptionErrorEquatableTests: XCTestCase {
    
    func testErrorEquality() {
        XCTAssertEqual(TranscriptionError.permissionDenied, TranscriptionError.permissionDenied)
        XCTAssertEqual(TranscriptionError.networkUnavailable, TranscriptionError.networkUnavailable)
        XCTAssertEqual(TranscriptionError.unknownError("test"), TranscriptionError.unknownError("test"))
        
        XCTAssertNotEqual(TranscriptionError.permissionDenied, TranscriptionError.networkUnavailable)
        XCTAssertNotEqual(TranscriptionError.unknownError("test1"), TranscriptionError.unknownError("test2"))
    }
}