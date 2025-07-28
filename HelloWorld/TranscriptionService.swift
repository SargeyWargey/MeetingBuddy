import Foundation
import Speech
import AVFoundation
import Combine

/// Main transcription service that handles speech-to-text conversion
@MainActor
class TranscriptionService: ObservableObject, TranscriptionServiceProtocol {
    
    // MARK: - Private Properties
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let transcriptionQueue: TranscriptionQueue
    private var activeTranscriptions: Set<UUID> = []
    private let networkMonitor: NetworkMonitor
    
    // MARK: - Published Properties
    @Published private(set) var isProcessingQueue = false
    @Published private(set) var isOnline = true
    @Published private(set) var queuedForOffline: Set<UUID> = []
    
    // MARK: - Initialization
    init() {
        self.speechRecognizer = SFSpeechRecognizer()
        self.transcriptionQueue = TranscriptionQueue()
        self.networkMonitor = NetworkMonitor()
        
        // Set initial online status
        self.isOnline = networkMonitor.hasInternetConnection
        
        // Monitor network changes
        setupNetworkMonitoring()
    }
    
    // MARK: - Network Monitoring Setup
    private func setupNetworkMonitoring() {
        // Observe network status changes
        Task {
            for await _ in NotificationCenter.default.notifications(named: .networkStatusChanged) {
                await handleNetworkStatusChange()
            }
        }
        
        // Monitor network monitor's published properties
        networkMonitor.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.isOnline = isConnected
                if isConnected {
                    Task {
                        await self?.processOfflineQueue()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func handleNetworkStatusChange() async {
        let wasOnline = isOnline
        isOnline = networkMonitor.hasInternetConnection
        
        // If we just came back online, process the offline queue
        if !wasOnline && isOnline {
            await processOfflineQueue()
        }
    }
    
    // MARK: - TranscriptionServiceProtocol Implementation
    
    var isAvailable: Bool {
        return isOnDeviceAvailable || (isCloudAvailable && isOnline)
    }
    
    var isOnDeviceAvailable: Bool {
        guard let recognizer = speechRecognizer else { return false }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
    }
    
    var isCloudAvailable: Bool {
        guard let recognizer = speechRecognizer else { return false }
        return recognizer.isAvailable && networkMonitor.isSuitableForCloudTranscription
    }
    
    var queueCount: Int {
        return transcriptionQueue.count
    }
    
    func transcribe(_ recording: Recording) async throws -> TranscriptionResult {
        guard hasPermissions() else {
            throw TranscriptionError.permissionDenied
        }
        
        // Check if already processing this recording
        guard !activeTranscriptions.contains(recording.id) else {
            throw TranscriptionError.unknownError("Transcription already in progress for this recording")
        }
        
        // Handle offline scenarios
        if !isOnline && !isOnDeviceAvailable {
            // Queue for offline processing
            queuedForOffline.insert(recording.id)
            queueTranscription(recording, priority: .normal)
            throw TranscriptionError.networkUnavailable
        }
        
        // If online but cloud not suitable (expensive connection), prefer on-device
        let preferOnDevice = !networkMonitor.isSuitableForCloudTranscription
        
        guard isOnDeviceAvailable || (isOnline && isCloudAvailable) else {
            throw TranscriptionError.serviceUnavailable
        }
        
        activeTranscriptions.insert(recording.id)
        defer { activeTranscriptions.remove(recording.id) }
        
        let startTime = Date()
        
        do {
            let result = try await performTranscription(for: recording, preferOnDevice: preferOnDevice)
            let processingTime = Date().timeIntervalSince(startTime)
            
            // Remove from offline queue if it was there
            queuedForOffline.remove(recording.id)
            
            return TranscriptionResult(
                text: result.text,
                confidence: result.confidence,
                processingTime: processingTime,
                method: result.method,
                completedAt: Date()
            )
        } catch {
            // If network error and on-device not available, queue for offline
            if case TranscriptionError.networkUnavailable = error, !isOnDeviceAvailable {
                queuedForOffline.insert(recording.id)
                queueTranscription(recording, priority: .normal)
            }
            
            if let transcriptionError = error as? TranscriptionError {
                throw transcriptionError
            } else {
                throw TranscriptionError.unknownError(error.localizedDescription)
            }
        }
    }
    
    func queueTranscription(_ recording: Recording) {
        let priority: TranscriptionQueueItem.Priority = isOnline ? .normal : .low
        transcriptionQueue.enqueue(recordingId: recording.id, priority: priority)
        
        // If offline, add to offline queue
        if !isOnline {
            queuedForOffline.insert(recording.id)
        }
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
                // Note: In a real implementation, we would need a reference to RecordingManager
                // to get the actual Recording object. For now, we'll create a mock recording
                // This would be improved by passing a delegate or callback to get recordings
                
                let mockRecording = Recording(
                    fileName: "mock.m4a",
                    url: URL(fileURLWithPath: "/tmp/mock.m4a"),
                    createdAt: Date(),
                    duration: 60.0
                )
                
                let result = try await transcribe(mockRecording)
                print("Transcription completed for recording: \(queueItem.recordingId) - \(result.text)")
                
            } catch {
                // Handle transcription error - requeue with retry if retries available
                if queueItem.retryCount < 3 {
                    transcriptionQueue.requeueWithRetry(queueItem)
                    print("Transcription failed, requeued for retry: \(queueItem.recordingId)")
                } else {
                    print("Failed to transcribe recording \(queueItem.recordingId) after max retries: \(error)")
                }
            }
        }
    }
    
    func clearQueue() {
        transcriptionQueue.clear()
        queuedForOffline.removeAll()
    }
    
    // MARK: - Offline Queue Processing
    
    /// Processes items that were queued while offline
    private func processOfflineQueue() async {
        guard isOnline else { return }
        guard !queuedForOffline.isEmpty else { return }
        
        print("Processing offline queue with \(queuedForOffline.count) items")
        
        // Create a copy to iterate over
        let offlineItems = Array(queuedForOffline)
        
        for recordingId in offlineItems {
            // Update priority to normal since we're back online
            transcriptionQueue.updatePriority(recordingId: recordingId, priority: .normal)
        }
        
        // Process the queue
        await processQueue()
    }
    
    /// Gets the count of items queued for offline processing
    var offlineQueueCount: Int {
        return queuedForOffline.count
    }
    
    /// Checks if a recording is queued for offline processing
    func isQueuedForOffline(_ recording: Recording) -> Bool {
        return queuedForOffline.contains(recording.id)
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
    
    private func performTranscription(for recording: Recording, preferOnDevice: Bool = false) async throws -> (text: String, confidence: Float, method: TranscriptionMethod) {
        guard let speechRecognizer = speechRecognizer else {
            throw TranscriptionError.serviceUnavailable
        }
        
        // Validate audio file before processing
        try validateAudioFile(recording)
        
        // Determine transcription method based on availability and preference
        let useOnDevice = isOnDeviceAvailable && (preferOnDevice || !isOnline)
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: recording.url)
            
            // Configure request based on method
            if useOnDevice {
                request.requiresOnDeviceRecognition = true
            }
            
            // Set up recognition task
            recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    let transcriptionError = self.convertSpeechError(error)
                    continuation.resume(throwing: transcriptionError)
                    return
                }
                
                guard let result = result else {
                    continuation.resume(throwing: TranscriptionError.unknownError("No transcription result received"))
                    return
                }
                
                // Return final result when transcription is complete
                if result.isFinal {
                    let transcription = result.bestTranscription.formattedString
                    let confidence = result.bestTranscription.segments.isEmpty ? 0.0 : 
                        result.bestTranscription.segments.map { $0.confidence }.reduce(0, +) / Float(result.bestTranscription.segments.count)
                    
                    let method: TranscriptionMethod = useOnDevice ? .onDevice : .cloud
                    
                    continuation.resume(returning: (
                        text: transcription,
                        confidence: confidence,
                        method: method
                    ))
                }
            }
        }
    }
    
    /// Converts SFSpeechRecognizer errors to TranscriptionError with enhanced detection
    private func convertSpeechError(_ error: Error) -> TranscriptionError {
        // Handle NSError cases
        if let nsError = error as NSError? {
            // Check for Speech framework errors
            if nsError.domain == "kSFSpeechErrorDomain" {
                switch nsError.code {
                case 1:  // SFSpeechErrorCodeRequestDenied
                    return .permissionDenied
                case 2:  // SFSpeechErrorCodeRequestNotAuthorized
                    return .permissionDenied
                case 3:  // SFSpeechErrorCodeRequestUnsupported
                    // Check if it's a language support issue
                    if nsError.localizedDescription.lowercased().contains("language") {
                        return .languageNotSupported
                    }
                    return .serviceUnavailable
                case 4:  // SFSpeechErrorCodeRequestTimedOut
                    return .processingTimeout
                case 5:  // SFSpeechErrorCodeRequestCancelled
                    return .unknownError("Transcription was cancelled")
                case 6:  // SFSpeechErrorCodeRequestFailed
                    // Check for specific failure reasons
                    let description = nsError.localizedDescription.lowercased()
                    if description.contains("no speech") || description.contains("silence") {
                        return .noSpeechDetected
                    } else if description.contains("too short") {
                        return .audioTooShort
                    } else if description.contains("too long") {
                        return .audioTooLong
                    }
                    return .serviceUnavailable
                case 7:  // SFSpeechErrorCodeRequestNetworkUnavailable
                    return .networkUnavailable
                case 8:  // SFSpeechErrorCodeRequestQuotaExceeded
                    return .quotaExceeded
                default:
                    return .unknownError("Speech recognition error: \(nsError.localizedDescription)")
                }
            }
            
            // Handle other error domains
            switch nsError.domain {
            case NSURLErrorDomain:
                // More specific network error handling
                switch nsError.code {
                case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                    return .networkUnavailable
                case NSURLErrorTimedOut:
                    return .processingTimeout
                default:
                    return .networkUnavailable
                }
                
            case "AVAudioSessionErrorDomain":
                switch nsError.code {
                case 1852797029: // kAudioSessionUnsupportedFormatError
                    return .audioFormatUnsupported
                case 1936290409: // kAudioSessionIncompatibleCategory
                    return .microphoneUnavailable
                default:
                    return .audioFormatUnsupported
                }
                
            case NSCocoaErrorDomain:
                switch nsError.code {
                case NSFileReadNoSuchFileError:
                    return .audioFileNotFound
                case NSFileReadNoPermissionError:
                    return .permissionDenied
                case NSFileReadCorruptFileError:
                    return .audioFormatUnsupported
                default:
                    return .unknownError("File system error: \(error.localizedDescription)")
                }
                
            case "NSOSStatusErrorDomain":
                // Audio-related OS status errors
                switch nsError.code {
                case -50: // paramErr
                    return .audioFormatUnsupported
                case -43: // fnfErr (file not found)
                    return .audioFileNotFound
                case -34: // dskFulErr (disk full)
                    return .deviceStorageFull
                default:
                    return .unknownError("System error: \(error.localizedDescription)")
                }
                
            default:
                return .unknownError("Unknown error: \(error.localizedDescription)")
            }
        }
        
        // Handle specific error types
        if error.localizedDescription.lowercased().contains("storage") ||
           error.localizedDescription.lowercased().contains("disk full") {
            return .deviceStorageFull
        }
        
        if error.localizedDescription.lowercased().contains("microphone") {
            return .microphoneUnavailable
        }
        
        return .unknownError("Unexpected error: \(error.localizedDescription)")
    }
    
    /// Validates audio file before transcription
    private func validateAudioFile(_ recording: Recording) throws {
        // Check if file exists
        guard FileManager.default.fileExists(atPath: recording.url.path) else {
            throw TranscriptionError.audioFileNotFound
        }
        
        // Check file size and duration constraints
        if recording.duration < 1.0 {
            throw TranscriptionError.audioTooShort
        }
        
        if recording.duration > 600.0 { // 10 minutes
            throw TranscriptionError.audioTooLong
        }
        
        // Check available storage space
        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: recording.url.path),
           let freeSize = attributes[.systemFreeSize] as? NSNumber {
            let freeBytes = freeSize.int64Value
            let requiredBytes: Int64 = 100_000_000 // 100MB minimum
            
            if freeBytes < requiredBytes {
                throw TranscriptionError.deviceStorageFull
            }
        }
        
        // Validate audio format
        do {
            let audioFile = try AVAudioFile(forReading: recording.url)
            let format = audioFile.fileFormat
            
            // Check if format is supported - simplified check for basic audio formats
            if format.sampleRate <= 0 || format.channelCount <= 0 {
                throw TranscriptionError.audioFormatUnsupported
            }
            
        } catch {
            throw TranscriptionError.audioFormatUnsupported
        }
    }
}



// MARK: - Private Result Structure
private struct TranscriptionInternalResult {
    let text: String
    let confidence: Float
    let method: TranscriptionMethod
}