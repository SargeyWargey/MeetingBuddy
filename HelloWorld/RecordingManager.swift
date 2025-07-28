import Foundation
import AVFoundation
import SwiftUI

class RecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordings: [Recording] = []
    @Published var currentRecordingTime: TimeInterval = 0
    @Published var hasPermission = false
    @Published var errorMessage: String?
    
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private let audioSession = AVAudioSession.sharedInstance()
    
    override init() {
        super.init()
        loadRecordings()
        requestPermission()
    }
    
    private func requestPermission() {
        audioSession.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.hasPermission = granted
                if granted {
                    self?.setupAudioSession()
                }
            }
        }
    }
    
    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to setup audio session: \(error.localizedDescription)"
            }
        }
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