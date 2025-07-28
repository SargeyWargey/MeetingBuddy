import Foundation
import Speech
import AVFoundation

/// Main transcription service that handles speech-to-text conversion
@MainActor
class TranscriptionService: ObservableObject, TranscriptionServiceProtocol {
    
    // MARK: - Private Properties
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let transcriptionQueue: TranscriptionQueue
    private var activeTranscriptions: Set<UUID> = []
    
    // MARK: - Published Properties
    @Published private(set) var isProcessingQueue = false
    
    // MARK: - Initialization
    init() {
        self.speechRecognizer = SFSpeechRecognizer()
        self.transcriptionQueue = TranscriptionQueue()
    }
    
    // MARK: - TranscriptionServiceProtocol Implementation
    
    var isAvailable: Bool {
        return isOnDeviceAvailable || isCloudAvailable
    }
    
    var isOnDeviceAvailable: Bool {
        guard let recognizer = speechRecognizer else { return false }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
    }
    
    var isCloudAvailable: Bool {
        guard let recognizer = speechRecognizer else { return false }
        return recognizer.isAvailable
    }
    
    var queueCount: Int {
        return transcriptionQueue.count
    }
    
    func transcribe(_ recording: Recording) async throws -> TranscriptionResult {
        guard isAvailable else {
            throw TranscriptionError.serviceUnavailable
        }
        
        guard hasPermissions() else {
            throw TranscriptionError.permissionDenied
        }
        
        // Check if already processing this recording
        guard !activeTranscriptions.contains(recording.id) else {
            throw TranscriptionError.unknownError("Transcription already in progress for this recording")
        }
        
        activeTranscriptions.insert(recording.id)
        defer { activeTranscriptions.remove(recording.id) }
        
        let startTime = Date()
        
        do {
            let result = try await performTranscription(for: recording)
            let processingTime = Date().timeIntervalSince(startTime)
            
            return TranscriptionResult(
                text: result.text,
                confidence: result.confidence,
                processingTime: processingTime,
                method: result.method,
                completedAt: Date()
            )
        } catch {
            if let transcriptionError = error as? TranscriptionError {
                throw transcriptionError
            } else {
                throw TranscriptionError.unknownError(error.localizedDescription)
            }
        }
    }
    
    func queueTranscription(_ recording: Recording) {
        transcriptionQueue.enqueue(recordingId: recording.id, priority: .normal)
    }
    
    func retryTranscription(_ recording: Recording) async throws -> TranscriptionResult {
        // Remove from queue if it exists
        transcriptionQueue.remove(recordingId: recording.id)
        
        // Perform transcription with user-requested priority
        transcriptionQueue.enqueue(recordingId: recording.id, priority: .userRequested)
        return try await transcribe(recording)
    }
    
    func cancelTranscription(_ recording: Recording) {
        // Remove from queue
        transcriptionQueue.remove(recordingId: recording.id)
        
        // Cancel active transcription if running
        if activeTranscriptions.contains(recording.id) {
            recognitionTask?.cancel()
            activeTranscriptions.remove(recording.id)
        }
    }
    
    func requestPermissions() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }
    
    func hasPermissions() -> Bool {
        return SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    
    func processQueue() async {
        guard !isProcessingQueue else { return }
        guard transcriptionQueue.count > 0 else { return }
        
        isProcessingQueue = true
        defer { isProcessingQueue = false }
        
        // Process items in priority order
        while let queueItem = transcriptionQueue.dequeue() {
            do {
                // In a real implementation, you would:
                // 1. Get the Recording object from RecordingManager using queueItem.recordingId
                // 2. Call transcribe() with the recording
                // 3. Update the recording's transcription status
                // 4. Notify UI of completion
                
                // For now, simulate processing
                print("Processing transcription for recording: \(queueItem.recordingId)")
                
                // Simulate potential failure and retry logic
                if queueItem.retryCount < 2 && Bool.random() {
                    // Simulate failure - requeue with retry
                    transcriptionQueue.requeueWithRetry(queueItem)
                    print("Transcription failed, requeued for retry: \(queueItem.recordingId)")
                } else {
                    print("Transcription completed for recording: \(queueItem.recordingId)")
                }
                
            } catch {
                // Handle transcription error - requeue with retry
                transcriptionQueue.requeueWithRetry(queueItem)
                print("Failed to transcribe recording \(queueItem.recordingId): \(error)")
            }
        }
    }
    
    func clearQueue() {
        transcriptionQueue.clear()
    }
    
    // MARK: - Queue Management Methods
    
    /// Adds a recording to the transcription queue with specified priority
    func queueTranscription(_ recording: Recording, priority: TranscriptionQueueItem.Priority) {
        transcriptionQueue.enqueue(recordingId: recording.id, priority: priority)
    }
    
    /// Gets the current queue statistics
    var queueStatistics: TranscriptionQueue.QueueStatistics {
        return transcriptionQueue.statistics
    }
    
    /// Checks if a recording is currently in the queue
    func isInQueue(_ recording: Recording) -> Bool {
        return transcriptionQueue.contains(recordingId: recording.id)
    }
    
    /// Gets the queue position for a recording
    func queuePosition(for recording: Recording) -> Int? {
        return transcriptionQueue.position(for: recording.id)
    }
    
    /// Updates the priority of a queued recording
    func updateQueuePriority(_ recording: Recording, priority: TranscriptionQueueItem.Priority) {
        transcriptionQueue.updatePriority(recordingId: recording.id, priority: priority)
    }
    
    /// Cleans up expired queue items
    func cleanupQueue() {
        transcriptionQueue.cleanupExpiredItems()
    }
    
    // MARK: - Private Methods
    
    private func performTranscription(for recording: Recording) async throws -> (text: String, confidence: Float, method: TranscriptionMethod) {
        // This is a placeholder implementation
        // In the actual implementation, this would:
        // 1. Load the audio file from recording.fileURL
        // 2. Use SFSpeechRecognizer to transcribe the audio
        // 3. Handle on-device vs cloud transcription
        // 4. Return the transcription result
        
        // For now, return a mock result to satisfy the interface
        return (
            text: "Mock transcription for recording: \(recording.title)",
            confidence: 0.95,
            method: isOnDeviceAvailable ? .onDevice : .cloud
        )
    }
}

// MARK: - Private Result Structure
private struct TranscriptionInternalResult {
    let text: String
    let confidence: Float
    let method: TranscriptionMethod
}