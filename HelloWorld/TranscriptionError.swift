import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Errors that can occur during audio transcription
enum TranscriptionError: LocalizedError, Equatable {
    case permissionDenied
    case audioFileNotFound
    case audioFormatUnsupported
    case networkUnavailable
    case serviceUnavailable
    case processingTimeout
    case quotaExceeded
    case audioTooShort
    case audioTooLong
    case noSpeechDetected
    case languageNotSupported
    case deviceStorageFull
    case microphoneUnavailable
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Speech Recognition Permission Required"
        case .audioFileNotFound:
            return "Audio File Not Found"
        case .audioFormatUnsupported:
            return "Unsupported Audio Format"
        case .networkUnavailable:
            return "No Internet Connection"
        case .serviceUnavailable:
            return "Transcription Service Unavailable"
        case .processingTimeout:
            return "Transcription Timed Out"
        case .quotaExceeded:
            return "Daily Limit Reached"
        case .audioTooShort:
            return "Audio Too Short"
        case .audioTooLong:
            return "Audio Too Long"
        case .noSpeechDetected:
            return "No Speech Detected"
        case .languageNotSupported:
            return "Language Not Supported"
        case .deviceStorageFull:
            return "Device Storage Full"
        case .microphoneUnavailable:
            return "Microphone Unavailable"
        case .unknownError(_):
            return "Transcription Failed"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Enable Speech Recognition in Settings to transcribe your recordings."
        case .audioFileNotFound:
            return "The recording file may have been deleted. Try recording again."
        case .audioFormatUnsupported:
            return "This audio format isn't supported. Try recording in a different format."
        case .networkUnavailable:
            return "Connect to the internet and try again, or wait for offline processing."
        case .serviceUnavailable:
            return "The transcription service is temporarily down. Try again in a few minutes."
        case .processingTimeout:
            return "The audio file may be too long or complex. Try with a shorter recording."
        case .quotaExceeded:
            return "You've reached your daily transcription limit. Try again tomorrow."
        case .audioTooShort:
            return "Record for at least 3 seconds to enable transcription."
        case .audioTooLong:
            return "Break longer recordings into segments under 10 minutes for better results."
        case .noSpeechDetected:
            return "Make sure you're speaking clearly and the microphone can hear you."
        case .languageNotSupported:
            return "Change your device language to a supported language in Settings."
        case .deviceStorageFull:
            return "Free up storage space on your device and try again."
        case .microphoneUnavailable:
            return "Check that your microphone is working and not being used by another app."
        case .unknownError:
            return "Try again or restart the app if the problem continues."
        }
    }
    
    var failureReason: String? {
        switch self {
        case .permissionDenied:
            return "The app doesn't have permission to use speech recognition."
        case .audioFileNotFound:
            return "The audio file couldn't be located on the device."
        case .audioFormatUnsupported:
            return "The audio format isn't compatible with the transcription engine."
        case .networkUnavailable:
            return "Internet connection is required for cloud transcription."
        case .serviceUnavailable:
            return "The transcription service is experiencing issues."
        case .processingTimeout:
            return "The transcription process took too long to complete."
        case .quotaExceeded:
            return "The daily transcription limit has been exceeded."
        case .audioTooShort:
            return "The audio recording is too short to transcribe effectively."
        case .audioTooLong:
            return "The audio recording exceeds the maximum length for transcription."
        case .noSpeechDetected:
            return "No recognizable speech was found in the audio."
        case .languageNotSupported:
            return "The current device language isn't supported for transcription."
        case .deviceStorageFull:
            return "Insufficient storage space for transcription processing."
        case .microphoneUnavailable:
            return "The microphone is not accessible or is being used by another app."
        case .unknownError(let message):
            return "An unexpected error occurred: \(message)"
        }
    }
    
    /// User-friendly detailed explanation of the error
    var detailedDescription: String {
        switch self {
        case .permissionDenied:
            return "To transcribe your recordings, this app needs permission to use speech recognition. This allows us to convert your audio into text."
        case .audioFileNotFound:
            return "The recording file couldn't be found. It may have been moved or deleted from your device."
        case .audioFormatUnsupported:
            return "The audio file format isn't supported by the transcription service. Supported formats include M4A, WAV, and MP3."
        case .networkUnavailable:
            return "Cloud transcription requires an internet connection. Your recording will be queued and processed when you're back online."
        case .serviceUnavailable:
            return "The transcription service is temporarily unavailable. This could be due to maintenance or high demand."
        case .processingTimeout:
            return "The transcription took too long to complete. This usually happens with very long recordings or poor network conditions."
        case .quotaExceeded:
            return "You've reached the daily limit for transcriptions. This limit resets every 24 hours."
        case .audioTooShort:
            return "The recording is too short to transcribe effectively. Try recording for at least 3 seconds."
        case .audioTooLong:
            return "The recording is too long for a single transcription. Consider breaking it into shorter segments."
        case .noSpeechDetected:
            return "No speech was detected in the recording. Make sure you're speaking clearly and the microphone is working properly."
        case .languageNotSupported:
            return "The current device language isn't supported for transcription. You can change your language in Settings."
        case .deviceStorageFull:
            return "Your device doesn't have enough storage space for transcription processing. Free up some space and try again."
        case .microphoneUnavailable:
            return "The microphone couldn't be accessed. Make sure it's not being used by another app and that you've granted microphone permissions."
        case .unknownError(let message):
            return "An unexpected error occurred during transcription. Error details: \(message)"
        }
    }
    
    /// Whether this error can be retried automatically
    var canRetry: Bool {
        switch self {
        case .permissionDenied, .audioFileNotFound, .audioFormatUnsupported, 
             .audioTooShort, .audioTooLong, .languageNotSupported, .deviceStorageFull:
            return false
        case .networkUnavailable, .serviceUnavailable, .processingTimeout, 
             .quotaExceeded, .noSpeechDetected, .microphoneUnavailable, .unknownError:
            return true
        }
    }
    
    /// Whether this error requires user action to resolve
    var requiresUserAction: Bool {
        switch self {
        case .permissionDenied, .audioFormatUnsupported, .languageNotSupported, 
             .deviceStorageFull, .microphoneUnavailable:
            return true
        case .audioFileNotFound, .networkUnavailable, .serviceUnavailable, 
             .processingTimeout, .quotaExceeded, .audioTooShort, .audioTooLong, 
             .noSpeechDetected, .unknownError:
            return false
        }
    }
    
    /// Primary action the user can take to resolve this error
    var primaryAction: ErrorAction? {
        switch self {
        case .permissionDenied:
            return .openSettings
        case .audioFileNotFound:
            return .recordAgain
        case .audioFormatUnsupported:
            return .recordAgain
        case .networkUnavailable:
            return .waitForConnection
        case .serviceUnavailable:
            return .retry
        case .processingTimeout:
            return .retry
        case .quotaExceeded:
            return .waitForReset
        case .audioTooShort:
            return .recordAgain
        case .audioTooLong:
            return .recordShorter
        case .noSpeechDetected:
            return .retry
        case .languageNotSupported:
            return .openSettings
        case .deviceStorageFull:
            return .freeStorage
        case .microphoneUnavailable:
            return .checkMicrophone
        case .unknownError:
            return .retry
        }
    }
    
    /// Secondary action the user can take
    var secondaryAction: ErrorAction? {
        switch self {
        case .permissionDenied:
            return .dismiss
        case .audioFileNotFound:
            return .dismiss
        case .audioFormatUnsupported:
            return .dismiss
        case .networkUnavailable:
            return .queueForLater
        case .serviceUnavailable:
            return .dismiss
        case .processingTimeout:
            return .dismiss
        case .quotaExceeded:
            return .dismiss
        case .audioTooShort:
            return .dismiss
        case .audioTooLong:
            return .dismiss
        case .noSpeechDetected:
            return .dismiss
        case .languageNotSupported:
            return .dismiss
        case .deviceStorageFull:
            return .dismiss
        case .microphoneUnavailable:
            return .openSettings
        case .unknownError:
            return .dismiss
        }
    }
    
    /// Icon to display with this error
    var iconName: String {
        switch self {
        case .permissionDenied:
            return "lock.shield"
        case .audioFileNotFound:
            return "doc.questionmark"
        case .audioFormatUnsupported:
            return "waveform.badge.exclamationmark"
        case .networkUnavailable:
            return "wifi.slash"
        case .serviceUnavailable:
            return "server.rack"
        case .processingTimeout:
            return "clock.badge.exclamationmark"
        case .quotaExceeded:
            return "gauge.badge.minus"
        case .audioTooShort:
            return "waveform.path.badge.minus"
        case .audioTooLong:
            return "waveform.path.badge.plus"
        case .noSpeechDetected:
            return "mic.slash"
        case .languageNotSupported:
            return "globe.badge.chevron.backward"
        case .deviceStorageFull:
            return "internaldrive.fill"
        case .microphoneUnavailable:
            return "mic.badge.xmark"
        case .unknownError:
            return "exclamationmark.triangle"
        }
    }
    
    /// Color to use for this error type
    var errorColor: ErrorColor {
        switch self {
        case .permissionDenied, .audioFormatUnsupported, .languageNotSupported, 
             .deviceStorageFull, .microphoneUnavailable:
            return .warning
        case .audioFileNotFound, .audioTooShort, .audioTooLong:
            return .info
        case .networkUnavailable:
            return .offline
        case .serviceUnavailable, .processingTimeout, .quotaExceeded, 
             .noSpeechDetected, .unknownError:
            return .error
        }
    }
}

// MARK: - Supporting Types

/// Actions that users can take to resolve transcription errors
enum ErrorAction: CaseIterable {
    case retry
    case openSettings
    case recordAgain
    case recordShorter
    case waitForConnection
    case waitForReset
    case queueForLater
    case freeStorage
    case checkMicrophone
    case dismiss
    
    var title: String {
        switch self {
        case .retry:
            return "Try Again"
        case .openSettings:
            return "Open Settings"
        case .recordAgain:
            return "Record Again"
        case .recordShorter:
            return "Record Shorter"
        case .waitForConnection:
            return "Wait for Connection"
        case .waitForReset:
            return "Wait for Reset"
        case .queueForLater:
            return "Queue for Later"
        case .freeStorage:
            return "Free Storage"
        case .checkMicrophone:
            return "Check Microphone"
        case .dismiss:
            return "Dismiss"
        }
    }
    
    var iconName: String {
        switch self {
        case .retry:
            return "arrow.clockwise"
        case .openSettings:
            return "gear"
        case .recordAgain:
            return "mic.circle"
        case .recordShorter:
            return "waveform.path.badge.minus"
        case .waitForConnection:
            return "wifi"
        case .waitForReset:
            return "clock"
        case .queueForLater:
            return "tray.and.arrow.down"
        case .freeStorage:
            return "internaldrive"
        case .checkMicrophone:
            return "mic"
        case .dismiss:
            return "xmark"
        }
    }
    
    var isDestructive: Bool {
        return self == .dismiss
    }
    
    var isPrimary: Bool {
        switch self {
        case .retry, .openSettings, .recordAgain:
            return true
        default:
            return false
        }
    }
}

/// Color categories for different error types
enum ErrorColor {
    case error
    case warning
    case info
    case offline
    
    #if os(iOS)
    var uiColor: UIColor {
        switch self {
        case .error:
            return .systemRed
        case .warning:
            return .systemOrange
        case .info:
            return .systemBlue
        case .offline:
            return .systemYellow
        }
    }
    #elseif os(macOS)
    var nsColor: NSColor {
        switch self {
        case .error:
            return .systemRed
        case .warning:
            return .systemOrange
        case .info:
            return .systemBlue
        case .offline:
            return .systemYellow
        }
    }
    #endif
}

// MARK: - Error Logging Support

extension TranscriptionError {
    /// Creates a structured log entry for this error
    var logEntry: [String: Any] {
        return [
            "error_type": String(describing: self).components(separatedBy: "(").first ?? "unknown",
            "error_description": errorDescription ?? "No description",
            "failure_reason": failureReason ?? "No reason",
            "recovery_suggestion": recoverySuggestion ?? "No suggestion",
            "can_retry": canRetry,
            "requires_user_action": requiresUserAction,
            "primary_action": primaryAction?.title ?? "None",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
    }
    
    /// Logs this error to the console with structured information
    func logError(context: String = "") {
        let contextPrefix = context.isEmpty ? "" : "[\(context)] "
        print("🚨 \(contextPrefix)Transcription Error: \(errorDescription ?? "Unknown")")
        print("   Reason: \(failureReason ?? "Unknown")")
        print("   Recovery: \(recoverySuggestion ?? "None")")
        print("   Can Retry: \(canRetry)")
        print("   User Action Required: \(requiresUserAction)")
        
        // In a production app, you would send this to your analytics service
        // Analytics.logError(self.logEntry)
    }
}

// MARK: - Equatable Implementation
extension TranscriptionError {
    static func == (lhs: TranscriptionError, rhs: TranscriptionError) -> Bool {
        switch (lhs, rhs) {
        case (.permissionDenied, .permissionDenied),
             (.audioFileNotFound, .audioFileNotFound),
             (.audioFormatUnsupported, .audioFormatUnsupported),
             (.networkUnavailable, .networkUnavailable),
             (.serviceUnavailable, .serviceUnavailable),
             (.processingTimeout, .processingTimeout),
             (.quotaExceeded, .quotaExceeded),
             (.audioTooShort, .audioTooShort),
             (.audioTooLong, .audioTooLong),
             (.noSpeechDetected, .noSpeechDetected),
             (.languageNotSupported, .languageNotSupported),
             (.deviceStorageFull, .deviceStorageFull),
             (.microphoneUnavailable, .microphoneUnavailable):
            return true
        case (.unknownError(let lhsMessage), .unknownError(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}