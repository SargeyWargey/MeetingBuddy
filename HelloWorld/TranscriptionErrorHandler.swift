import Foundation
import SwiftUI

/// Centralized error handling for transcription operations
@MainActor
class TranscriptionErrorHandler: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentError: TranscriptionError?
    @Published var errorBanners: [ErrorBanner] = []
    @Published var retryAttempts: [UUID: Int] = [:]
    
    // MARK: - Private Properties
    
    private let maxRetryAttempts = 3
    private let retryDelays: [TimeInterval] = [1.0, 2.0, 4.0] // Exponential backoff
    private var retryTimers: [UUID: Timer] = [:]
    
    // MARK: - Error Banner Model
    
    struct ErrorBanner: Identifiable {
        let id = UUID()
        let error: TranscriptionError
        let recordingId: UUID
        let timestamp: Date
        
        init(error: TranscriptionError, recordingId: UUID) {
            self.error = error
            self.recordingId = recordingId
            self.timestamp = Date()
        }
    }
    
    // MARK: - Error Handling Methods
    
    /// Handles a transcription error with comprehensive logging and user feedback
    func handleError(_ error: TranscriptionError, for recordingId: UUID, context: String = "") {
        // Log the error
        error.logError(context: context)
        
        // Track retry attempts
        let currentAttempts = retryAttempts[recordingId] ?? 0
        retryAttempts[recordingId] = currentAttempts
        
        // Determine if we should show user feedback
        if shouldShowUserFeedback(for: error, attempts: currentAttempts) {
            showErrorToUser(error, recordingId: recordingId)
        }
        
        // Handle automatic retry if appropriate
        if shouldAutoRetry(error: error, attempts: currentAttempts) {
            scheduleAutoRetry(for: recordingId, error: error, attempt: currentAttempts + 1)
        }
        
        // Log analytics (in production, this would go to your analytics service)
        logErrorAnalytics(error: error, recordingId: recordingId, attempts: currentAttempts)
    }
    
    /// Handles successful transcription (clears error state)
    func handleSuccess(for recordingId: UUID) {
        // Clear retry attempts
        retryAttempts.removeValue(forKey: recordingId)
        
        // Cancel any pending retry timers
        retryTimers[recordingId]?.invalidate()
        retryTimers.removeValue(forKey: recordingId)
        
        // Remove error banners for this recording
        errorBanners.removeAll { $0.recordingId == recordingId }
        
        // Clear current error if it's for this recording
        if let currentError = currentError {
            // Note: We don't have recording ID in current error, so we clear it
            // In a more sophisticated implementation, we'd track which recording the current error is for
            self.currentError = nil
        }
    }
    
    /// Processes an error action taken by the user
    func processErrorAction(_ action: ErrorAction, for error: TranscriptionError, recordingId: UUID) {
        switch action {
        case .retry:
            handleRetryAction(for: recordingId, error: error)
            
        case .openSettings:
            handleOpenSettingsAction()
            
        case .recordAgain:
            handleRecordAgainAction(for: recordingId)
            
        case .recordShorter:
            handleRecordShorterAction(for: recordingId)
            
        case .waitForConnection:
            handleWaitForConnectionAction(for: recordingId, error: error)
            
        case .waitForReset:
            handleWaitForResetAction(for: recordingId)
            
        case .queueForLater:
            handleQueueForLaterAction(for: recordingId)
            
        case .freeStorage:
            handleFreeStorageAction()
            
        case .checkMicrophone:
            handleCheckMicrophoneAction()
            
        case .dismiss:
            handleDismissAction(for: recordingId)
        }
        
        // Log the user action
        logUserAction(action: action, error: error, recordingId: recordingId)
    }
    
    // MARK: - Private Helper Methods
    
    private func shouldShowUserFeedback(for error: TranscriptionError, attempts: Int) -> Bool {
        // Always show feedback for errors that require user action
        if error.requiresUserAction {
            return true
        }
        
        // Show feedback after first retry attempt for retryable errors
        if error.canRetry && attempts >= 1 {
            return true
        }
        
        // Show feedback immediately for critical errors
        switch error {
        case .audioFileNotFound, .quotaExceeded:
            return true
        default:
            return false
        }
    }
    
    private func shouldAutoRetry(error: TranscriptionError, attempts: Int) -> Bool {
        return error.canRetry && attempts < maxRetryAttempts && !error.requiresUserAction
    }
    
    private func showErrorToUser(_ error: TranscriptionError, recordingId: UUID) {
        // Set current error for modal display
        currentError = error
        
        // Add error banner for persistent display
        let banner = ErrorBanner(error: error, recordingId: recordingId)
        errorBanners.append(banner)
        
        // Auto-dismiss banner after 10 seconds for non-critical errors
        if !error.requiresUserAction {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                self.errorBanners.removeAll { $0.id == banner.id }
            }
        }
    }
    
    private func scheduleAutoRetry(for recordingId: UUID, error: TranscriptionError, attempt: Int) {
        let delayIndex = min(attempt - 1, retryDelays.count - 1)
        let delay = retryDelays[delayIndex]
        
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performAutoRetry(for: recordingId, error: error, attempt: attempt)
            }
        }
        
        retryTimers[recordingId] = timer
    }
    
    private func performAutoRetry(for recordingId: UUID, error: TranscriptionError, attempt: Int) {
        retryAttempts[recordingId] = attempt
        
        // Notify the system to retry transcription
        NotificationCenter.default.post(
            name: .transcriptionAutoRetry,
            object: nil,
            userInfo: [
                "recordingId": recordingId,
                "attempt": attempt,
                "originalError": error
            ]
        )
    }
    
    // MARK: - Action Handlers
    
    private func handleRetryAction(for recordingId: UUID, error: TranscriptionError) {
        // Reset retry count for manual retry
        retryAttempts[recordingId] = 0
        
        // Clear current error state
        currentError = nil
        errorBanners.removeAll { $0.recordingId == recordingId }
        
        // Notify the system to retry transcription
        NotificationCenter.default.post(
            name: .transcriptionManualRetry,
            object: nil,
            userInfo: ["recordingId": recordingId]
        )
    }
    
    private func handleOpenSettingsAction() {
        #if os(iOS)
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
        #elseif os(macOS)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!)
        #endif
        
        currentError = nil
    }
    
    private func handleRecordAgainAction(for recordingId: UUID) {
        // Clear error state
        currentError = nil
        errorBanners.removeAll { $0.recordingId == recordingId }
        
        // Notify the system to switch to recording tab
        NotificationCenter.default.post(
            name: .switchToRecordingTab,
            object: nil
        )
    }
    
    private func handleRecordShorterAction(for recordingId: UUID) {
        handleRecordAgainAction(for: recordingId)
    }
    
    private func handleWaitForConnectionAction(for recordingId: UUID, error: TranscriptionError) {
        // Queue the transcription for when connection is restored
        NotificationCenter.default.post(
            name: .queueTranscriptionForOffline,
            object: nil,
            userInfo: ["recordingId": recordingId]
        )
        
        currentError = nil
    }
    
    private func handleWaitForResetAction(for recordingId: UUID) {
        // Schedule a notification for when quota might reset (24 hours)
        scheduleQuotaResetNotification()
        currentError = nil
    }
    
    private func handleQueueForLaterAction(for recordingId: UUID) {
        handleWaitForConnectionAction(for: recordingId, error: .networkUnavailable)
    }
    
    private func handleFreeStorageAction() {
        #if os(iOS)
        if let settingsUrl = URL(string: "App-prefs:General&path=STORAGE_MGMT") {
            UIApplication.shared.open(settingsUrl)
        }
        #elseif os(macOS)
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/Applications/Storage Management.app"))
        #endif
        
        currentError = nil
    }
    
    private func handleCheckMicrophoneAction() {
        // Show system microphone test or settings
        #if os(iOS)
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
        #elseif os(macOS)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        #endif
        
        currentError = nil
    }
    
    private func handleDismissAction(for recordingId: UUID) {
        currentError = nil
        errorBanners.removeAll { $0.recordingId == recordingId }
        
        // Cancel any pending retries
        retryTimers[recordingId]?.invalidate()
        retryTimers.removeValue(forKey: recordingId)
    }
    
    // MARK: - Utility Methods
    
    private func scheduleQuotaResetNotification() {
        // In a real app, you would schedule a local notification
        // For now, we'll just log it
        print("📅 Quota reset notification scheduled for 24 hours from now")
    }
    
    private func logErrorAnalytics(error: TranscriptionError, recordingId: UUID, attempts: Int) {
        let analyticsData: [String: Any] = [
            "event": "transcription_error",
            "error_type": String(describing: error).components(separatedBy: "(").first ?? "unknown",
            "recording_id": recordingId.uuidString,
            "retry_attempt": attempts,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "can_retry": error.canRetry,
            "requires_user_action": error.requiresUserAction
        ]
        
        // In production, send to analytics service
        print("📊 Analytics: \(analyticsData)")
    }
    
    private func logUserAction(action: ErrorAction, error: TranscriptionError, recordingId: UUID) {
        let actionData: [String: Any] = [
            "event": "error_action_taken",
            "action": action.title,
            "error_type": String(describing: error).components(separatedBy: "(").first ?? "unknown",
            "recording_id": recordingId.uuidString,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        // In production, send to analytics service
        print("📊 User Action: \(actionData)")
    }
    
    // MARK: - Public Utility Methods
    
    /// Gets the current retry count for a recording
    func getRetryCount(for recordingId: UUID) -> Int {
        return retryAttempts[recordingId] ?? 0
    }
    
    /// Checks if a recording has reached max retry attempts
    func hasReachedMaxRetries(for recordingId: UUID) -> Bool {
        return getRetryCount(for: recordingId) >= maxRetryAttempts
    }
    
    /// Clears all error state
    func clearAllErrors() {
        currentError = nil
        errorBanners.removeAll()
        retryAttempts.removeAll()
        
        // Cancel all retry timers
        retryTimers.values.forEach { $0.invalidate() }
        retryTimers.removeAll()
    }
    
    /// Gets error banners for a specific recording
    func getErrorBanners(for recordingId: UUID) -> [ErrorBanner] {
        return errorBanners.filter { $0.recordingId == recordingId }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let transcriptionAutoRetry = Notification.Name("transcriptionAutoRetry")
    static let transcriptionManualRetry = Notification.Name("transcriptionManualRetry")
    static let switchToRecordingTab = Notification.Name("switchToRecordingTab")
    static let queueTranscriptionForOffline = Notification.Name("queueTranscriptionForOffline")
}