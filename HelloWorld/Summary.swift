import Foundation

// MARK: - Summary Data Model

struct Summary: Codable, Identifiable, Equatable {
    let id: UUID
    let recordingId: UUID
    let text: String
    let type: SummaryType
    let length: SummaryLength
    let createdAt: Date
    let aiProvider: AIProvider
    let confidence: Double
    let wordCount: Int
    let processingTime: TimeInterval
    let metadata: [String: String] // Changed from [String: Any] for Codable compliance
    
    init(
        id: UUID = UUID(),
        recordingId: UUID,
        text: String,
        type: SummaryType,
        length: SummaryLength,
        createdAt: Date = Date(),
        aiProvider: AIProvider,
        confidence: Double,
        wordCount: Int,
        processingTime: TimeInterval = 0,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.recordingId = recordingId
        self.text = text
        self.type = type
        self.length = length
        self.createdAt = createdAt
        self.aiProvider = aiProvider
        self.confidence = confidence
        self.wordCount = wordCount
        self.processingTime = processingTime
        self.metadata = metadata
    }
    
    // MARK: - Computed Properties
    
    var displayText: String {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var isRecent: Bool {
        return Date().timeIntervalSince(createdAt) < 24 * 60 * 60 // 24 hours
    }
    
    var confidenceLevel: ConfidenceLevel {
        switch confidence {
        case 0.8...1.0:
            return .high
        case 0.6..<0.8:
            return .medium
        case 0.0..<0.6:
            return .low
        default:
            return .unknown
        }
    }
    
    var estimatedReadingTime: TimeInterval {
        // Average reading speed: 200 words per minute
        return Double(wordCount) / 200.0 * 60.0
    }
}

// MARK: - Summary Type Enum

enum SummaryType: String, CaseIterable, Codable, Identifiable {
    case brief = "brief"
    case detailed = "detailed"
    case bulletPoints = "bullet_points"
    case keyInsights = "key_insights"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .brief:
            return "Brief"
        case .detailed:
            return "Detailed"
        case .bulletPoints:
            return "Bullet Points"
        case .keyInsights:
            return "Key Insights"
        }
    }
    
    var description: String {
        switch self {
        case .brief:
            return "A concise overview of the main points"
        case .detailed:
            return "A comprehensive summary with context"
        case .bulletPoints:
            return "Key points organized as bullet points"
        case .keyInsights:
            return "Important insights and takeaways"
        }
    }
    
    var icon: String {
        switch self {
        case .brief:
            return "doc.text"
        case .detailed:
            return "doc.text.fill"
        case .bulletPoints:
            return "list.bullet"
        case .keyInsights:
            return "lightbulb"
        }
    }
}

// MARK: - Summary Length Enum

enum SummaryLength: String, CaseIterable, Codable, Identifiable {
    case short = "short"      // ~50-100 words
    case medium = "medium"    // ~100-200 words
    case long = "long"        // ~200-300 words
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .short:
            return "Short"
        case .medium:
            return "Medium"
        case .long:
            return "Long"
        }
    }
    
    var wordRange: String {
        switch self {
        case .short:
            return "50-100 words"
        case .medium:
            return "100-200 words"
        case .long:
            return "200-300 words"
        }
    }
    
    var targetWordCount: Int {
        switch self {
        case .short:
            return 75
        case .medium:
            return 150
        case .long:
            return 250
        }
    }
    
    var maxWordCount: Int {
        switch self {
        case .short:
            return 100
        case .medium:
            return 200
        case .long:
            return 300
        }
    }
}

// MARK: - AI Provider Enum

enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case openAI = "openai"           // Primary cloud provider
    case onDevice = "on_device"      // Apple Natural Language fallback
    case claude = "claude"           // Future alternative provider
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .onDevice:
            return "On-Device"
        case .claude:
            return "Claude"
        }
    }
    
    var description: String {
        switch self {
        case .openAI:
            return "High-quality cloud-based AI summarization"
        case .onDevice:
            return "Privacy-focused local processing"
        case .claude:
            return "Alternative cloud-based AI provider"
        }
    }
    
    var requiresNetwork: Bool {
        switch self {
        case .openAI, .claude:
            return true
        case .onDevice:
            return false
        }
    }
    
    var icon: String {
        switch self {
        case .openAI:
            return "cloud"
        case .onDevice:
            return "iphone"
        case .claude:
            return "cloud.fill"
        }
    }
    
    var isAvailable: Bool {
        switch self {
        case .openAI, .onDevice:
            return true
        case .claude:
            return false // Future implementation
        }
    }
}

// MARK: - Summary Status Enum

enum SummaryStatus: String, CaseIterable, Codable, Identifiable {
    case notStarted = "not_started"
    case inProgress = "in_progress"
    case completed = "completed"
    case failed = "failed"
    case queued = "queued"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .notStarted:
            return "Not Started"
        case .inProgress:
            return "Generating..."
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .queued:
            return "Queued"
        }
    }
    
    var icon: String {
        switch self {
        case .notStarted:
            return "circle"
        case .inProgress:
            return "clock"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .queued:
            return "clock.badge"
        }
    }
    
    var color: String {
        switch self {
        case .notStarted:
            return "secondary"
        case .inProgress:
            return "blue"
        case .completed:
            return "green"
        case .failed:
            return "red"
        case .queued:
            return "orange"
        }
    }
}

// MARK: - Summary Error Enum

enum SummaryError: LocalizedError, Equatable {
    case transcriptionTooShort(wordCount: Int)
    case networkUnavailable
    case aiServiceUnavailable(provider: AIProvider)
    case quotaExceeded(provider: AIProvider)
    case invalidResponse(provider: AIProvider)
    case cacheError(operation: String)
    case apiKeyMissing
    case apiKeyInvalid
    case rateLimitExceeded
    case contentTooLarge(wordCount: Int, maxWords: Int)
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .transcriptionTooShort(let wordCount):
            return "Transcription is too short to summarize (\(wordCount) words, minimum 50 required)"
        case .networkUnavailable:
            return "Network connection required for AI summarization"
        case .aiServiceUnavailable(let provider):
            return "\(provider.displayName) summarization service is currently unavailable"
        case .quotaExceeded(let provider):
            return "Daily summarization quota exceeded for \(provider.displayName)"
        case .invalidResponse(let provider):
            return "Received invalid response from \(provider.displayName)"
        case .cacheError(let operation):
            return "Error \(operation) summary cache"
        case .apiKeyMissing:
            return "OpenAI API key is required for cloud summarization"
        case .apiKeyInvalid:
            return "Invalid OpenAI API key provided"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later"
        case .contentTooLarge(let wordCount, let maxWords):
            return "Content too large (\(wordCount) words, maximum \(maxWords) supported)"
        case .unknownError(let message):
            return "Summarization failed: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .transcriptionTooShort:
            return "Try recording longer audio content"
        case .networkUnavailable:
            return "Check your internet connection and try again"
        case .aiServiceUnavailable:
            return "Try again later or use on-device summarization"
        case .quotaExceeded:
            return "Wait until tomorrow or upgrade your plan"
        case .invalidResponse:
            return "Try again or contact support if the problem persists"
        case .cacheError:
            return "Restart the app or clear the cache"
        case .apiKeyMissing:
            return "Add your OpenAI API key in Settings"
        case .apiKeyInvalid:
            return "Check your OpenAI API key in Settings"
        case .rateLimitExceeded:
            return "Wait a few minutes before trying again"
        case .contentTooLarge:
            return "Try summarizing shorter recordings"
        case .unknownError:
            return "Try again or contact support"
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .transcriptionTooShort, .apiKeyMissing, .apiKeyInvalid, .contentTooLarge:
            return false
        case .networkUnavailable, .aiServiceUnavailable, .quotaExceeded, .invalidResponse, .cacheError, .rateLimitExceeded, .unknownError:
            return true
        }
    }
}

// MARK: - Confidence Level Enum

enum ConfidenceLevel: String, CaseIterable, Codable {
    case high = "high"
    case medium = "medium"
    case low = "low"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .high:
            return "High"
        case .medium:
            return "Medium"
        case .low:
            return "Low"
        case .unknown:
            return "Unknown"
        }
    }
    
    var color: String {
        switch self {
        case .high:
            return "green"
        case .medium:
            return "orange"
        case .low:
            return "red"
        case .unknown:
            return "gray"
        }
    }
    
    var icon: String {
        switch self {
        case .high:
            return "checkmark.circle.fill"
        case .medium:
            return "exclamationmark.circle.fill"
        case .low:
            return "xmark.circle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }
}

// MARK: - Summary Result

struct SummaryResult {
    let text: String
    let confidence: Double
    let provider: AIProvider
    let processingTime: TimeInterval
    let wordCount: Int
    let metadata: [String: String]
    
    init(
        text: String,
        confidence: Double,
        provider: AIProvider,
        processingTime: TimeInterval,
        wordCount: Int? = nil,
        metadata: [String: String] = [:]
    ) {
        self.text = text
        self.confidence = confidence
        self.provider = provider
        self.processingTime = processingTime
        self.wordCount = wordCount ?? text.split(separator: " ").count
        self.metadata = metadata
    }
    
    func toSummary(
        recordingId: UUID,
        type: SummaryType,
        length: SummaryLength
    ) -> Summary {
        return Summary(
            recordingId: recordingId,
            text: text,
            type: type,
            length: length,
            aiProvider: provider,
            confidence: confidence,
            wordCount: wordCount,
            processingTime: processingTime,
            metadata: metadata
        )
    }
}

// MARK: - Summary Preferences

struct SummaryPreferences: Codable {
    var defaultType: SummaryType
    var defaultLength: SummaryLength
    var preferredProvider: AIProvider?
    var autoGenerateOnTranscription: Bool
    var showConfidenceLevel: Bool
    var enableNotifications: Bool
    
    static let `default` = SummaryPreferences(
        defaultType: .brief,
        defaultLength: .medium,
        preferredProvider: nil, // Auto-select
        autoGenerateOnTranscription: false,
        showConfidenceLevel: true,
        enableNotifications: true
    )
}