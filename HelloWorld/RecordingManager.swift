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
    
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    
    #if os(iOS)
    private let audioSession = AVAudioSession.sharedInstance()
    #endif
    
    override init() {
        super.init()
        
        // Initialize transcription service on main actor
        Task { @MainActor in
            self.transcriptionService = TranscriptionService()
            self.setupTranscriptionService()
        }
        
        loadRecordings()
        requestPermission()
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
                }
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
            let duration = audioRecorder?.currentTime ?? 0
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
        
        // Update recording status to in progress
        updateRecordingTranscriptionStatus(recording.id, status: .inProgress)
        
        Task {
            let service = await MainActor.run { self.transcriptionService }
            guard let service = service else {
                await handleTranscriptionError(recordingId: recording.id, error: TranscriptionError.serviceUnavailable)
                return
            }
            
            do {
                let result = try await service.transcribe(recording)
                await handleTranscriptionSuccess(recordingId: recording.id, result: result)
            } catch {
                await handleTranscriptionError(recordingId: recording.id, error: error)
            }
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
        
        // Update recording status to in progress
        updateRecordingTranscriptionStatus(recording.id, status: .inProgress)
        
        Task {
            let service = await MainActor.run { self.transcriptionService }
            guard let service = service else {
                await handleTranscriptionError(recordingId: recording.id, error: TranscriptionError.serviceUnavailable)
                return
            }
            
            do {
                let result = try await service.transcribe(recording)
                await handleTranscriptionSuccess(recordingId: recording.id, result: result)
            } catch {
                await handleTranscriptionError(recordingId: recording.id, error: error)
            }
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
        
        // Update recording status to in progress
        updateRecordingTranscriptionStatus(recording.id, status: .inProgress)
        
        Task {
            let service = await MainActor.run { self.transcriptionService }
            guard let service = service else {
                await handleTranscriptionError(recordingId: recording.id, error: TranscriptionError.serviceUnavailable)
                return
            }
            
            do {
                let result = try await service.retryTranscription(recording)
                await handleTranscriptionSuccess(recordingId: recording.id, result: result)
            } catch {
                await handleTranscriptionError(recordingId: recording.id, error: error)
            }
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
        
        saveRecordings()
    }
    
    @MainActor
    private func handleTranscriptionError(recordingId: UUID, error: Error) {
        guard let index = recordings.firstIndex(where: { $0.id == recordingId }) else {
            return
        }
        
        recordings[index].transcriptionStatus = .failed
        recordings[index].lastTranscriptionAttempt = Date()
        
        if let transcriptionError = error as? TranscriptionError {
            recordings[index].transcriptionError = transcriptionError.localizedDescription
            errorMessage = transcriptionError.localizedDescription
        } else {
            recordings[index].transcriptionError = error.localizedDescription
            errorMessage = "Transcription failed: \(error.localizedDescription)"
        }
        
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