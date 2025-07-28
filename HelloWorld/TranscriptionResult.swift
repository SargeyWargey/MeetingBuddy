import Foundation

/// Represents the result of a transcription operation
struct TranscriptionResult: Equatable, Codable {
    /// The transcribed text
    let text: String
    
    /// Confidence level of the transcription (0.0 to 1.0)
    let confidence: Float
    
    /// Time taken to process the transcription
    let processingTime: TimeInterval
    
    /// Method used for transcription
    let method: TranscriptionMethod
    
    /// Timestamp when transcription was completed
    let completedAt: Date
    
    /// Optional metadata about the transcription
    let metadata: [String: String]?
    
    init(
        text: String,
        confidence: Float = 1.0,
        processingTime: TimeInterval,
        method: TranscriptionMethod,
        completedAt: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.text = text
        self.confidence = max(0.0, min(1.0, confidence)) // Clamp between 0.0 and 1.0
        self.processingTime = processingTime
        self.method = method
        self.completedAt = completedAt
        self.metadata = metadata
    }
}

/// Methods available for transcription
enum TranscriptionMethod: String, Codable, CaseIterable {
    case onDevice = "on_device"
    case cloud = "cloud"
    case cached = "cached"
    
    var displayName: String {
        switch self {
        case .onDevice:
            return "On-Device"
        case .cloud:
            return "Cloud"
        case .cached:
            return "Cached"
        }
    }
    
    var isOfflineCapable: Bool {
        switch self {
        case .onDevice, .cached:
            return true
        case .cloud:
            return false
        }
    }
}

// MARK: - TranscriptionResult Extensions
extension TranscriptionResult {
    /// Returns true if the transcription confidence is above a reasonable threshold
    var isHighConfidence: Bool {
        return confidence >= 0.7
    }
    
    /// Returns true if the transcription result is empty or contains only whitespace
    var isEmpty: Bool {
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Returns a truncated version of the text for preview purposes
    func previewText(maxLength: Int = 100) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxLength {
            return trimmed
        }
        
        let truncated = String(trimmed.prefix(maxLength))
        return truncated + "..."
    }
}