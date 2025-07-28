import Foundation

/// Errors that can occur during audio transcription
enum TranscriptionError: LocalizedError, Equatable {
    case permissionDenied
    case audioFileNotFound
    case audioFormatUnsupported
    case networkUnavailable
    case serviceUnavailable
    case processingTimeout
    case quotaExceeded
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Speech recognition permission is required"
        case .audioFileNotFound:
            return "Audio file could not be found"
        case .audioFormatUnsupported:
            return "Audio format is not supported for transcription"
        case .networkUnavailable:
            return "Network connection is required for transcription"
        case .serviceUnavailable:
            return "Transcription service is currently unavailable"
        case .processingTimeout:
            return "Transcription processing timed out"
        case .quotaExceeded:
            return "Transcription quota has been exceeded"
        case .unknownError(let message):
            return "An unexpected error occurred: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Please enable Speech Recognition in Settings > Privacy & Security > Speech Recognition"
        case .audioFileNotFound:
            return "Try recording a new audio file"
        case .audioFormatUnsupported:
            return "Please use a supported audio format (M4A, WAV, MP3)"
        case .networkUnavailable:
            return "Check your internet connection and try again"
        case .serviceUnavailable:
            return "Please try again later"
        case .processingTimeout:
            return "Try transcribing a shorter audio file or check your connection"
        case .quotaExceeded:
            return "Please wait before making more transcription requests"
        case .unknownError:
            return "Please try again or contact support if the problem persists"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .permissionDenied:
            return "The app does not have permission to use speech recognition"
        case .audioFileNotFound:
            return "The specified audio file does not exist"
        case .audioFormatUnsupported:
            return "The audio file format is not compatible with the transcription service"
        case .networkUnavailable:
            return "No internet connection is available"
        case .serviceUnavailable:
            return "The transcription service is temporarily unavailable"
        case .processingTimeout:
            return "The transcription request took too long to complete"
        case .quotaExceeded:
            return "Too many transcription requests have been made"
        case .unknownError:
            return "An internal error occurred"
        }
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
             (.quotaExceeded, .quotaExceeded):
            return true
        case (.unknownError(let lhsMessage), .unknownError(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}