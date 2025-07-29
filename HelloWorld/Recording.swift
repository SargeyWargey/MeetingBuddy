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
    
    // AI Summary properties
    var summary: Summary?
    var summaryStatus: SummaryStatus
    var summaryError: String?
    var lastSummaryAttempt: Date?
    
    init(fileName: String, url: URL, createdAt: Date = Date(), duration: TimeInterval = 0, title: String? = nil, transcription: String? = nil, transcriptionStatus: TranscriptionStatus = .notStarted, transcriptionError: String? = nil, lastTranscriptionAttempt: Date? = nil, summary: Summary? = nil, summaryStatus: SummaryStatus = .notStarted, summaryError: String? = nil, lastSummaryAttempt: Date? = nil) {
        self.fileName = fileName
        self.url = url
        self.createdAt = createdAt
        self.duration = duration
        self.title = title ?? Recording.defaultTitle(for: createdAt)
        self.transcription = transcription
        self.transcriptionStatus = transcriptionStatus
        self.transcriptionError = transcriptionError
        self.lastTranscriptionAttempt = lastTranscriptionAttempt
        self.summary = summary
        self.summaryStatus = summaryStatus
        self.summaryError = summaryError
        self.lastSummaryAttempt = lastSummaryAttempt
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
    
    // MARK: - AI Summary Computed Properties
    
    var hasSummary: Bool {
        return summary != nil && summaryStatus == .completed
    }
    
    var canSummarize: Bool {
        guard hasTranscription, let transcription = transcription else {
            return false
        }
        
        // Check if transcription has at least 50 words
        let wordCount = transcription.split(separator: " ").count
        return wordCount >= 50
    }
    
    var isSummaryInProgress: Bool {
        return summaryStatus == .inProgress
    }
    
    var canRetrySummary: Bool {
        return summaryStatus == .failed || summaryStatus == .notStarted
    }
    
    var summaryPreview: String {
        guard let summary = summary, !summary.text.isEmpty else {
            return "No summary available"
        }
        
        let maxLength = 100
        if summary.text.count <= maxLength {
            return summary.text
        }
        
        let truncated = String(summary.text.prefix(maxLength))
        return truncated + "..."
    }
    
    var summaryStatusDisplayText: String {
        switch summaryStatus {
        case .notStarted:
            return canSummarize ? "Not summarized" : "Cannot summarize"
        case .inProgress:
            return "Generating summary..."
        case .completed:
            return hasSummary ? "Summarized" : "No summary available"
        case .failed:
            return "Summary failed"
        case .queued:
            return "Queued for summary"
        }
    }
    
    var transcriptionWordCount: Int {
        guard let transcription = transcription else { return 0 }
        return transcription.split(separator: " ").count
    }
    
    var summaryWordCount: Int {
        return summary?.wordCount ?? 0
    }
    
    var summaryCompressionRatio: Double {
        guard transcriptionWordCount > 0, summaryWordCount > 0 else { return 0 }
        return Double(summaryWordCount) / Double(transcriptionWordCount)
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