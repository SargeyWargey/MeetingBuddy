import Foundation
import Speech
import AVFoundation

/// A wrapper class for iOS Speech Recognition functionality
@MainActor
class SpeechRecognizer: NSObject, ObservableObject {
    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    /// Current authorization status for speech recognition
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    
    /// Whether on-device speech recognition is available
    var isOnDeviceAvailable: Bool {
        guard let recognizer = speechRecognizer else { return false }
        return recognizer.supportsOnDeviceRecognition
    }
    
    /// Whether cloud-based speech recognition is available
    var isCloudAvailable: Bool {
        guard speechRecognizer != nil else { return false }
        return SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    
    /// Whether any speech recognition is available
    var isAvailable: Bool {
        return isOnDeviceAvailable || isCloudAvailable
    }
    
    override init() {
        // Initialize with user's preferred locale, fallback to English
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        self.authorizationStatus = SFSpeechRecognizer.authorizationStatus()
        
        super.init()
        
        // Set up delegate to monitor availability changes
        speechRecognizer?.delegate = self
    }
    
    /// Request permission for speech recognition
    func requestPermissions() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    self.authorizationStatus = status
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }
    
    /// Check current permission status
    func checkPermissionStatus() -> SFSpeechRecognizerAuthorizationStatus {
        let status = SFSpeechRecognizer.authorizationStatus()
        authorizationStatus = status
        return status
    }
    
    /// Transcribe an audio file using iOS Speech Recognition
    func transcribeAudioFile(at url: URL) async throws -> String {
        // Check if speech recognizer is available
        guard let speechRecognizer = speechRecognizer else {
            throw TranscriptionError.serviceUnavailable
        }
        
        // Check authorization
        guard authorizationStatus == .authorized else {
            throw TranscriptionError.permissionDenied
        }
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TranscriptionError.audioFileNotFound
        }
        
        // Check if recognizer is available
        guard speechRecognizer.isAvailable else {
            throw TranscriptionError.serviceUnavailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: url)
            
            // Prefer on-device recognition if available
            if isOnDeviceAvailable {
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
                    continuation.resume(returning: transcription)
                }
            }
        }
    }
    
    /// Cancel any ongoing transcription
    func cancelTranscription() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
    
    /// Convert SFSpeechRecognizer errors to TranscriptionError
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
                    return .serviceUnavailable
                case 4:  // SFSpeechErrorCodeRequestTimedOut
                    return .processingTimeout
                case 5:  // SFSpeechErrorCodeRequestCancelled
                    return .unknownError("Transcription was cancelled")
                case 6:  // SFSpeechErrorCodeRequestFailed
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
                return .networkUnavailable
            case "AVAudioSessionErrorDomain":
                return .audioFormatUnsupported
            default:
                return .unknownError("Unknown error: \(error.localizedDescription)")
            }
        }
        
        return .unknownError("Unexpected error: \(error.localizedDescription)")
    }
}

// MARK: - SFSpeechRecognizerDelegate
extension SpeechRecognizer: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        // Update UI or handle availability changes if needed
        Task { @MainActor in
            objectWillChange.send()
        }
    }
}