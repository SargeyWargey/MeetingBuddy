import Foundation

/// Protocol defining the interface for transcription services
protocol TranscriptionServiceProtocol {
    /// Indicates whether the transcription service is currently available
    var isAvailable: Bool { get }
    
    /// Indicates whether on-device transcription is available
    var isOnDeviceAvailable: Bool { get }
    
    /// Indicates whether cloud transcription is available
    var isCloudAvailable: Bool { get }
    
    /// Transcribes the given recording and returns the result
    /// - Parameter recording: The recording to transcribe
    /// - Returns: TranscriptionResult containing the transcribed text and metadata
    /// - Throws: TranscriptionError if transcription fails
    func transcribe(_ recording: Recording) async throws -> TranscriptionResult
    
    /// Queues a recording for transcription to be processed later
    /// - Parameter recording: The recording to queue for transcription
    func queueTranscription(_ recording: Recording)
    
    /// Retries transcription for a recording that previously failed
    /// - Parameter recording: The recording to retry transcription for
    /// - Returns: TranscriptionResult containing the transcribed text and metadata
    /// - Throws: TranscriptionError if transcription fails again
    func retryTranscription(_ recording: Recording) async throws -> TranscriptionResult
    
    /// Cancels an ongoing transcription for the specified recording
    /// - Parameter recording: The recording to cancel transcription for
    func cancelTranscription(_ recording: Recording)
    
    /// Requests necessary permissions for transcription
    /// - Returns: True if permissions are granted, false otherwise
    func requestPermissions() async -> Bool
    
    /// Checks if the service has the necessary permissions
    /// - Returns: True if permissions are available, false otherwise
    func hasPermissions() -> Bool
    
    /// Processes any queued transcriptions
    func processQueue() async
    
    /// Clears all queued transcriptions
    func clearQueue()
    
    /// Returns the number of items currently in the transcription queue
    var queueCount: Int { get }
}

// MARK: - Default Implementation Extensions
extension TranscriptionServiceProtocol {
    /// Default implementation that checks both on-device and cloud availability
    var isAvailable: Bool {
        return isOnDeviceAvailable || isCloudAvailable
    }
}