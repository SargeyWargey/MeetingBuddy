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
    private var transcriptionQueue: [Recording] = []
    private var activeTranscriptions: Set<UUID> = []
    
    // MARK: - Published Properties
    @Published private(set) var isProcessingQueue = false
    
    // MARK: - Initialization
    init() {
        self.speechRecognizer = SFSpeechRecognizer()
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
        // Avoid duplicate entries
        if !transcriptionQueue.contains(where: { $0.id == recording.id }) {
            transcriptionQueue.append(recording)
        }
    }
    
    func retryTranscription(_ recording: Recording) async throws -> TranscriptionResult {
        // Remove from queue if it exists
        transcriptionQueue.removeAll { $0.id == recording.id }
        
        // Perform transcription
        return try await transcribe(recording)
    }
    
    func cancelTranscription(_ recording: Recording) {
        // Remove from queue
        transcriptionQueue.removeAll { $0.id == recording.id }
        
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
        guard !transcriptionQueue.isEmpty else { return }
        
        isProcessingQueue = true
        defer { isProcessingQueue = false }
        
        // Process recordings in FIFO order
        while !transcriptionQueue.isEmpty {
            let recording = transcriptionQueue.removeFirst()
            
            do {
                _ = try await transcribe(recording)
                // Note: In a real implementation, you would notify the RecordingManager
                // or update the recording's transcription status here
            } catch {
                // Log error and continue with next item
                print("Failed to transcribe recording \(recording.id): \(error)")
            }
        }
    }
    
    func clearQueue() {
        transcriptionQueue.removeAll()
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