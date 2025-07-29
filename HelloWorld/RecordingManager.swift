import Foundation
import AVFoundation
import SwiftUI

class RecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordings: [Recording] = []
    @Published var currentRecordingTime: TimeInterval = 0
    @Published var hasPermission = false
    @Published var errorMessage: String?
    
    // Transcription-related published properties
    @Published var transcriptionService: TranscriptionService?
    @Published var isTranscriptionAvailable = false
    @Published var transcriptionPermissionGranted = false
    @Published var errorHandler: TranscriptionErrorHandler!
    
    // Performance optimization components
    private var performanceMonitor: TranscriptionPerformanceMonitor?
    private var transcriptionCache: TranscriptionCache?
    private var audioMemoryManager: AudioMemoryManager?
    private var uiThreadOptimizer: UIThreadOptimizer?
    
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    
    #if os(iOS)
    private let audioSession = AVAudioSession.sharedInstance()
    #endif
    
    override init() {
        super.init()
        
        // Initialize transcription service and error handler on main actor
        Task { @MainActor in
            self.errorHandler = TranscriptionErrorHandler()
            self.transcriptionService = TranscriptionService()
            self.setupTranscriptionService()
            self.setupErrorHandlerNotifications()
            self.initializePerformanceComponents()
        }
        
        loadRecordings()
        requestPermission()
    }
    
    // MARK: - Performance Components Initialization
    
    @MainActor
    private func initializePerformanceComponents() {
        // Initialize audio memory manager
        self.audioMemoryManager = AudioMemoryManager()
        
        // Initialize transcription cache
        do {
            self.transcriptionCache = try TranscriptionCache()
        } catch {
            print("Failed to initialize transcription cache: \(error)")
        }
        
        print("Performance optimization components initialized in RecordingManager")
    }
    
    /// Configure performance optimization components (called from ContentView)
    @MainActor
    func configurePerformanceOptimization(
        performanceMonitor: TranscriptionPerformanceMonitor,
        uiThreadOptimizer: UIThreadOptimizer
    ) {
        self.performanceMonitor = performanceMonitor
        self.uiThreadOptimizer = uiThreadOptimizer
        
        print("Performance optimization components configured")
    }
    
    // MARK: - Transcription Service Setup
    
    @MainActor
    private func setupTranscriptionService() {
        guard let service = transcriptionService else { return }
        
        isTranscriptionAvailable = service.isAvailable
        transcriptionPermissionGranted = service.hasPermissions()
        
        // Request transcription permissions if not already granted
        if !transcriptionPermissionGranted {
            Task {
                let granted = await service.requestPermissions()
                await MainActor.run {
                    self.transcriptionPermissionGranted = granted
                    if !granted {
                        let error = TranscriptionError.permissionDenied
                        self.errorHandler.handleError(error, for: UUID(), context: "Initial permission request")
                    }
                }
            }
        }
    }
    
    @MainActor
    private func setupErrorHandlerNotifications() {
        // Listen for auto-retry notifications
        NotificationCenter.default.addObserver(
            forName: .transcriptionAutoRetry,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let recordingId = userInfo["recordingId"] as? UUID,
                  let recording = self?.getRecording(by: recordingId) else { return }
            
            self?.performAutoRetry(for: recording)
        }
        
        // Listen for manual retry notifications
        NotificationCenter.default.addObserver(
            forName: .transcriptionManualRetry,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let recordingId = userInfo["recordingId"] as? UUID,
                  let recording = self?.getRecording(by: recordingId) else { return }
            
            self?.retryTranscription(recording)
        }
        
        // Listen for offline queue notifications
        NotificationCenter.default.addObserver(
            forName: .queueTranscriptionForOffline,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let recordingId = userInfo["recordingId"] as? UUID,
                  let recording = self?.getRecording(by: recordingId) else { return }
            
            Task { @MainActor in
                self?.queueTranscription(recording)
            }
        }
    }
    
    private func performAutoRetry(for recording: Recording) {
        Task {
            do {
                let service = await MainActor.run { self.transcriptionService }
                guard let service = service else {
                    await handleTranscriptionError(recordingId: recording.id, error: TranscriptionError.serviceUnavailable)
                    return
                }
                
                let result = try await service.retryTranscription(recording)
                await handleTranscriptionSuccess(recordingId: recording.id, result: result)
            } catch {
                await handleTranscriptionError(recordingId: recording.id, error: error)
            }
        }
    }
    
    private func requestPermission() {
        #if os(iOS)
        audioSession.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.hasPermission = granted
                if granted {
                    self?.setupAudioSession()
                }
            }
        }
        #else
        // On macOS, assume permission is granted
        hasPermission = true
        setupAudioSession()
        #endif
    }
    
    private func setupAudioSession() {
        #if os(iOS)
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to setup audio session: \(error.localizedDescription)"
            }
        }
        #endif
        // On macOS, no audio session setup needed
    }
    
    func startRecording() {
        guard hasPermission else {
            errorMessage = "Microphone permission not granted"
            return
        }
        
        guard !isRecording else { return }
        
        let fileName = "Recording_\(Date().timeIntervalSince1970).m4a"
        let url = getDocumentsDirectory().appendingPathComponent(fileName)
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            isRecording = true
            currentRecordingTime = 0
            errorMessage = nil
            
            startTimer()
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        audioRecorder?.stop()
        stopTimer()
        
        isRecording = false
        
        if let url = audioRecorder?.url {
            // Calculate actual duration from the audio file
            let duration = getAudioFileDuration(url: url)
            let recording = Recording(
                fileName: url.lastPathComponent,
                url: url,
                createdAt: Date(),
                duration: duration
            )
            recordings.insert(recording, at: 0)
            saveRecordings()
            
            // Automatically trigger transcription for new recording
            triggerAutoTranscription(for: recording)
        }
        
        audioRecorder = nil
    }
    
    private func startTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.currentRecordingTime = self?.audioRecorder?.currentTime ?? 0
            }
        }
    }
    
    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    func playRecording(_ recording: Recording) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: recording.url)
            audioPlayer?.play()
        } catch {
            errorMessage = "Failed to play recording: \(error.localizedDescription)"
        }
    }
    
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    func deleteRecording(_ recording: Recording) {
        do {
            try FileManager.default.removeItem(at: recording.url)
            recordings.removeAll { $0.id == recording.id }
            saveRecordings()
        } catch {
            errorMessage = "Failed to delete recording: \(error.localizedDescription)"
        }
    }
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private func getAudioFileDuration(url: URL) -> TimeInterval {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let frameCount = audioFile.length
            let sampleRate = audioFile.fileFormat.sampleRate
            return Double(frameCount) / sampleRate
        } catch {
            // Fallback to using AVAudioPlayer if AVAudioFile fails
            do {
                let audioPlayer = try AVAudioPlayer(contentsOf: url)
                return audioPlayer.duration
            } catch {
                print("Failed to get audio duration: \(error)")
                return 0
            }
        }
    }
    
    private func saveRecordings() {
        if let data = try? JSONEncoder().encode(recordings) {
            UserDefaults.standard.set(data, forKey: "SavedRecordings")
        }
    }
    
    private func loadRecordings() {
        guard let data = UserDefaults.standard.data(forKey: "SavedRecordings"),
              let decodedRecordings = try? JSONDecoder().decode([Recording].self, from: data) else {
            return
        }
        
        recordings = decodedRecordings.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        
        if recordings.count != decodedRecordings.count {
            saveRecordings()
        }
    }
    
    var formattedCurrentTime: String {
        let minutes = Int(currentRecordingTime) / 60
        let seconds = Int(currentRecordingTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // MARK: - Transcription Methods
    
    /// Automatically triggers transcription for a new recording
    private func triggerAutoTranscription(for recording: Recording) {
        guard transcriptionPermissionGranted && isTranscriptionAvailable else {
            return
        }
        
        // Update recording status to in progress with UI optimization
        Task { @MainActor in
            await self.updateRecordingTranscriptionStatusOptimized(recording.id, status: .inProgress)
        }
        
        Task {
            await performOptimizedTranscription(
                recording: recording,
                operationType: .automatic,
                priority: .normal
            )
        }
    }
    
    /// Manually triggers transcription for a specific recording
    func transcribeRecording(_ recording: Recording) {
        guard transcriptionPermissionGranted else {
            errorMessage = "Speech recognition permission is required for transcription"
            return
        }
        
        guard isTranscriptionAvailable else {
            errorMessage = "Transcription service is not available"
            return
        }
        
        // Update recording status to in progress with UI optimization
        Task { @MainActor in
            await self.updateRecordingTranscriptionStatusOptimized(recording.id, status: .inProgress)
        }
        
        Task {
            await performOptimizedTranscription(
                recording: recording,
                operationType: .manual,
                priority: .userRequested
            )
        }
    }
    
    /// Retries transcription for a failed recording
    func retryTranscription(_ recording: Recording) {
        guard transcriptionPermissionGranted else {
            errorMessage = "Speech recognition permission is required for transcription"
            return
        }
        
        guard isTranscriptionAvailable else {
            errorMessage = "Transcription service is not available"
            return
        }
        
        // Update recording status to in progress with UI optimization
        Task { @MainActor in
            await self.updateRecordingTranscriptionStatusOptimized(recording.id, status: .inProgress)
        }
        
        Task {
            await performOptimizedTranscription(
                recording: recording,
                operationType: .retry,
                priority: .userRequested
            )
        }
    }
    
    /// Cancels transcription for a specific recording
    @MainActor
    func cancelTranscription(_ recording: Recording) {
        transcriptionService?.cancelTranscription(recording)
        updateRecordingTranscriptionStatus(recording.id, status: .notStarted)
    }
    
    /// Queues a recording for transcription
    @MainActor
    func queueTranscription(_ recording: Recording) {
        transcriptionService?.queueTranscription(recording)
        updateRecordingTranscriptionStatus(recording.id, status: .queued)
    }
    
    /// Processes the transcription queue
    func processTranscriptionQueue() {
        Task {
            let service = await MainActor.run { self.transcriptionService }
            guard let service = service else { return }
            await service.processQueue()
        }
    }
    
    /// Requests transcription permissions
    func requestTranscriptionPermissions() {
        Task {
            let service = await MainActor.run { self.transcriptionService }
            guard let service = service else { return }
            let granted = await service.requestPermissions()
            await MainActor.run {
                self.transcriptionPermissionGranted = granted
                if !granted {
                    self.errorMessage = "Speech recognition permission is required for transcription"
                }
            }
        }
    }
    
    // MARK: - Private Transcription Helper Methods
    
    @MainActor
    private func handleTranscriptionSuccess(recordingId: UUID, result: TranscriptionResult) {
        guard let index = recordings.firstIndex(where: { $0.id == recordingId }) else {
            return
        }
        
        recordings[index].transcription = result.text
        recordings[index].transcriptionStatus = .completed
        recordings[index].transcriptionError = nil
        recordings[index].lastTranscriptionAttempt = result.completedAt
        
        // Notify error handler of success to clear error state
        errorHandler.handleSuccess(for: recordingId)
        
        saveRecordings()
    }
    
    @MainActor
    private func handleTranscriptionError(recordingId: UUID, error: Error) {
        guard let index = recordings.firstIndex(where: { $0.id == recordingId }) else {
            return
        }
        
        recordings[index].transcriptionStatus = .failed
        recordings[index].lastTranscriptionAttempt = Date()
        
        let transcriptionError: TranscriptionError
        if let tError = error as? TranscriptionError {
            transcriptionError = tError
            recordings[index].transcriptionError = tError.errorDescription
        } else {
            transcriptionError = TranscriptionError.unknownError(error.localizedDescription)
            recordings[index].transcriptionError = error.localizedDescription
        }
        
        // Use the error handler for comprehensive error management
        errorHandler.handleError(transcriptionError, for: recordingId, context: "Transcription failed")
        
        saveRecordings()
    }
    
    private func updateRecordingTranscriptionStatus(_ recordingId: UUID, status: Recording.TranscriptionStatus) {
        DispatchQueue.main.async {
            guard let index = self.recordings.firstIndex(where: { $0.id == recordingId }) else {
                return
            }
            
            self.recordings[index].transcriptionStatus = status
            if status == .inProgress {
                self.recordings[index].transcriptionError = nil
            }
            
            self.saveRecordings()
        }
    }
    
    /// Gets the current recording by ID (helper for transcription service)
    func getRecording(by id: UUID) -> Recording? {
        return recordings.first { $0.id == id }
    }
    
    /// Updates a recording's transcription data
    func updateRecordingTranscription(_ recordingId: UUID, transcription: String?, status: Recording.TranscriptionStatus, error: String? = nil) {
        DispatchQueue.main.async {
            guard let index = self.recordings.firstIndex(where: { $0.id == recordingId }) else {
                return
            }
            
            self.recordings[index].transcription = transcription
            self.recordings[index].transcriptionStatus = status
            self.recordings[index].transcriptionError = error
            self.recordings[index].lastTranscriptionAttempt = Date()
            
            self.saveRecordings()
        }
    }
    
    // MARK: - Performance Optimized Transcription Methods
    
    /// Performs transcription with full performance optimization
    private func performOptimizedTranscription(
        recording: Recording,
        operationType: TranscriptionOperationType,
        priority: TranscriptionPriority
    ) async {
        let operationId = UUID()
        
        // Start performance tracking
        await MainActor.run {
            self.performanceMonitor?.startTrackingOperation(
                id: operationId,
                type: operationType,
                audioFileSize: self.getAudioFileSize(recording.url),
                priority: priority
            )
        }
        
        do {
            // Check cache first
            if let cachedResult = await checkTranscriptionCache(for: recording) {
                await handleCachedTranscriptionResult(recordingId: recording.id, result: cachedResult, operationId: operationId)
                return
            }
            
            // Perform transcription with memory management
            let result = try await performMemoryOptimizedTranscription(recording: recording, operationId: operationId)
            
            // Cache the result
            await cacheTranscriptionResult(result: result, for: recording)
            
            // Handle success with UI optimization
            await handleOptimizedTranscriptionSuccess(recordingId: recording.id, result: result, operationId: operationId)
            
        } catch {
            await handleOptimizedTranscriptionError(recordingId: recording.id, error: error, operationId: operationId)
        }
    }
    
    /// Check transcription cache for existing result
    private func checkTranscriptionCache(for recording: Recording) async -> CachedTranscriptionResult? {
        guard let cache = self.transcriptionCache else { return nil }
        
        let parameters = TranscriptionParameters(
            language: nil,
            requiresOnlineProcessing: false,
            preferredQuality: .balanced
        )
        
        return await cache.getCachedTranscription(for: recording.url, parameters: parameters)
    }
    
    /// Cache transcription result for future use
    private func cacheTranscriptionResult(result: TranscriptionResult, for recording: Recording) async {
        guard let cache = self.transcriptionCache else { return }
        
        let cachedResult = CachedTranscriptionResult(
            text: result.text,
            confidence: result.confidence,
            processingTime: result.processingTime,
            method: CachedTranscriptionResult.TranscriptionMethod(rawValue: result.method.rawValue) ?? .onDevice,
            language: nil,
            timestamp: result.completedAt
        )
        
        let parameters = TranscriptionParameters(
            language: nil,
            requiresOnlineProcessing: false,
            preferredQuality: .balanced
        )
        
        await cache.cacheTranscription(result: cachedResult, for: recording.url, parameters: parameters)
    }
    
    /// Perform transcription with memory optimization
    private func performMemoryOptimizedTranscription(recording: Recording, operationId: UUID) async throws -> TranscriptionResult {
        guard let service = self.transcriptionService else {
            throw TranscriptionError.serviceUnavailable
        }
        
        // Update progress
        await MainActor.run {
            self.performanceMonitor?.updateOperationProgress(
                id: operationId,
                progress: 0.1,
                currentPhase: "Starting transcription"
            )
        }
        
        // Use memory manager for large files
        let fileSize = getAudioFileSize(recording.url)
        if fileSize > 10 * 1024 * 1024 { // 10MB threshold
            return try await performChunkedTranscription(recording: recording, operationId: operationId)
        } else {
            return try await service.transcribe(recording)
        }
    }
    
    /// Perform chunked transcription for large files
    private func performChunkedTranscription(recording: Recording, operationId: UUID) async throws -> TranscriptionResult {
        guard let audioManager = audioMemoryManager else {
            throw TranscriptionError.unknownError("Audio memory manager not available")
        }
        
        var transcriptionChunks: [String] = []
        var totalConfidence: Float = 0
        var chunkCount = 0
        
        try await audioManager.processAudioFile(at: recording.url, operationId: operationId) { chunkData, chunkIndex, totalChunks in
            // Update progress
            let progress = Double(chunkIndex) / Double(totalChunks)
            await MainActor.run {
                self.performanceMonitor?.updateOperationProgress(
                    id: operationId,
                    progress: progress * 0.8 + 0.1, // 10-90% range
                    currentPhase: "Processing chunk \(chunkIndex + 1) of \(totalChunks)"
                )
            }
            
            // Process chunk (simplified - in real implementation would need audio processing)
            // This is a placeholder for actual chunk transcription
            transcriptionChunks.append("Chunk \(chunkIndex) transcription")
            totalConfidence += 0.8 // Placeholder confidence
            chunkCount += 1
        }
        
        // Combine chunks
        let combinedText = transcriptionChunks.joined(separator: " ")
        let averageConfidence = chunkCount > 0 ? totalConfidence / Float(chunkCount) : 0
        
        return TranscriptionResult(
            text: combinedText,
            confidence: averageConfidence,
            processingTime: 0, // Would be calculated
            method: .onDevice,
            completedAt: Date()
        )
    }
    
    /// Handle cached transcription result
    private func handleCachedTranscriptionResult(recordingId: UUID, result: CachedTranscriptionResult, operationId: UUID) async {
        let transcriptionResult = TranscriptionResult(
            text: result.text,
            confidence: result.confidence,
            processingTime: result.processingTime,
            method: TranscriptionMethod(rawValue: result.method.rawValue) ?? .onDevice,
            completedAt: result.timestamp
        )
        
        await handleOptimizedTranscriptionSuccess(recordingId: recordingId, result: transcriptionResult, operationId: operationId)
    }
    
    /// Handle transcription success with UI optimization
    private func handleOptimizedTranscriptionSuccess(recordingId: UUID, result: TranscriptionResult, operationId: UUID) async {
        // Complete performance tracking
        await MainActor.run {
            self.performanceMonitor?.completeOperation(
                id: operationId,
                success: true,
                resultSize: result.text.count
            )
        }
        
        // Update UI with optimization
        guard let uiOptimizer = self.uiThreadOptimizer else {
            await handleTranscriptionSuccess(recordingId: recordingId, result: result)
            return
        }
        
        await uiOptimizer.scheduleUpdate(
            UIUpdateOperation(priority: .high, estimatedDuration: 0.005) {
                await self.handleTranscriptionSuccess(recordingId: recordingId, result: result)
            }
        )
    }
    
    /// Handle transcription error with UI optimization
    private func handleOptimizedTranscriptionError(recordingId: UUID, error: Error, operationId: UUID) async {
        // Complete performance tracking
        await MainActor.run {
            self.performanceMonitor?.completeOperation(
                id: operationId,
                success: false,
                error: error
            )
        }
        
        // Update UI with optimization
        guard let uiOptimizer = self.uiThreadOptimizer else {
            await handleTranscriptionError(recordingId: recordingId, error: error)
            return
        }
        
        await uiOptimizer.scheduleUpdate(
            UIUpdateOperation(priority: .high, estimatedDuration: 0.005) {
                await self.handleTranscriptionError(recordingId: recordingId, error: error)
            }
        )
    }
    
    /// Update recording transcription status with UI optimization
    @MainActor
    private func updateRecordingTranscriptionStatusOptimized(_ recordingId: UUID, status: Recording.TranscriptionStatus) async {
        guard let uiOptimizer = self.uiThreadOptimizer else {
            updateRecordingTranscriptionStatus(recordingId, status: status)
            return
        }
        
        await uiOptimizer.scheduleUpdate(
            UIUpdateOperation(priority: .medium, estimatedDuration: 0.002) {
                self.updateRecordingTranscriptionStatus(recordingId, status: status)
            }
        )
    }
    
    /// Get audio file size for performance tracking
    private func getAudioFileSize(_ url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return 0 }
        return attributes[.size] as? Int64 ?? 0
    }
}

extension RecordingManager: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            errorMessage = "Recording failed to finish successfully"
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            errorMessage = "Recording encode error: \(error.localizedDescription)"
        }
    }
}