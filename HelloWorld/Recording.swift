import Foundation

struct Recording: Identifiable, Codable, Equatable {
    let id = UUID()
    let fileName: String
    let url: URL
    let createdAt: Date
    let duration: TimeInterval
    var title: String
    
    // Transcription properties
    var transcription: String?
    var transcriptionStatus: TranscriptionStatus
    var transcriptionError: String?
    var lastTranscriptionAttempt: Date?
    
    init(fileName: String, url: URL, createdAt: Date = Date(), duration: TimeInterval = 0, title: String? = nil, transcription: String? = nil, transcriptionStatus: TranscriptionStatus = .notStarted, transcriptionError: String? = nil, lastTranscriptionAttempt: Date? = nil) {
        self.fileName = fileName
        self.url = url
        self.createdAt = createdAt
        self.duration = duration
        self.title = title ?? Recording.defaultTitle(for: createdAt)
        self.transcription = transcription
        self.transcriptionStatus = transcriptionStatus
        self.transcriptionError = transcriptionError
        self.lastTranscriptionAttempt = lastTranscriptionAttempt
    }
    
    private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Recording \(formatter.string(from: date))"
    }
    
    var fileSizeString: String {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return "Unknown size"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
    
    var durationString: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Transcription Computed Properties
    
    var hasTranscription: Bool {
        return transcription != nil && !transcription!.isEmpty
    }
    
    var isTranscriptionInProgress: Bool {
        return transcriptionStatus == .inProgress
    }
    
    var canRetryTranscription: Bool {
        return transcriptionStatus == .failed || transcriptionStatus == .notStarted
    }
    
    var transcriptionPreview: String {
        guard let transcription = transcription, !transcription.isEmpty else {
            return "No transcription available"
        }
        
        let maxLength = 100
        if transcription.count <= maxLength {
            return transcription
        }
        
        let truncated = String(transcription.prefix(maxLength))
        return truncated + "..."
    }
    
    var transcriptionStatusDisplayText: String {
        switch transcriptionStatus {
        case .notStarted:
            return "Not transcribed"
        case .inProgress:
            return "Transcribing..."
        case .completed:
            return hasTranscription ? "Transcribed" : "No transcription available"
        case .failed:
            return "Transcription failed"
        case .queued:
            return "Queued for transcription"
        }
    }
}

// MARK: - TranscriptionStatus Enum

extension Recording {
    enum TranscriptionStatus: String, Codable, CaseIterable {
        case notStarted = "not_started"
        case inProgress = "in_progress"
        case completed = "completed"
        case failed = "failed"
        case queued = "queued"
        
        var displayName: String {
            switch self {
            case .notStarted:
                return "Not Started"
            case .inProgress:
                return "In Progress"
            case .completed:
                return "Completed"
            case .failed:
                return "Failed"
            case .queued:
                return "Queued"
            }
        }
    }
}