import Foundation

/// Represents an item in the transcription queue with priority and retry tracking
struct TranscriptionQueueItem: Codable, Identifiable, Equatable {
    let id = UUID()
    let recordingId: UUID
    let priority: Priority
    let createdAt: Date
    let retryCount: Int
    let lastAttemptAt: Date?
    let nextRetryAt: Date?
    
    init(recordingId: UUID, priority: Priority = .normal, retryCount: Int = 0, lastAttemptAt: Date? = nil) {
        self.recordingId = recordingId
        self.priority = priority
        self.createdAt = Date()
        self.retryCount = retryCount
        self.lastAttemptAt = lastAttemptAt
        self.nextRetryAt = TranscriptionQueueItem.calculateNextRetryTime(retryCount: retryCount, lastAttempt: lastAttemptAt)
    }
    
    /// Priority levels for transcription queue items
    enum Priority: Int, Codable, CaseIterable, Comparable {
        case low = 0
        case normal = 1
        case high = 2
        case userRequested = 3
        
        var displayName: String {
            switch self {
            case .low:
                return "Low"
            case .normal:
                return "Normal"
            case .high:
                return "High"
            case .userRequested:
                return "User Requested"
            }
        }
        
        static func < (lhs: Priority, rhs: Priority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    /// Creates a new queue item with incremented retry count
    func withRetry() -> TranscriptionQueueItem {
        let newRetryCount = retryCount + 1
        let lastAttempt = Date()
        
        return TranscriptionQueueItem(
            recordingId: recordingId,
            priority: priority,
            retryCount: newRetryCount,
            lastAttemptAt: lastAttempt
        )
    }
    
    /// Checks if the item is ready for retry (past the retry delay)
    var isReadyForRetry: Bool {
        guard let nextRetry = nextRetryAt else { return true }
        return Date() >= nextRetry
    }
    
    /// Checks if the item has exceeded maximum retry attempts
    var hasExceededMaxRetries: Bool {
        return retryCount >= TranscriptionQueueItem.maxRetryAttempts
    }
    
    /// Maximum number of retry attempts before giving up
    static let maxRetryAttempts = 3
    
    /// Calculates the next retry time using exponential backoff
    private static func calculateNextRetryTime(retryCount: Int, lastAttempt: Date?) -> Date? {
        guard let lastAttempt = lastAttempt, retryCount > 0 else { return nil }
        
        // Exponential backoff: 1s, 2s, 4s, 8s, etc.
        let delaySeconds = pow(2.0, Double(retryCount - 1))
        let maxDelay = 60.0 // Cap at 1 minute
        let actualDelay = min(delaySeconds, maxDelay)
        
        return lastAttempt.addingTimeInterval(actualDelay)
    }
}

// MARK: - Equatable Implementation
extension TranscriptionQueueItem {
    static func == (lhs: TranscriptionQueueItem, rhs: TranscriptionQueueItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Comparable Implementation for Priority Sorting
extension TranscriptionQueueItem: Comparable {
    static func < (lhs: TranscriptionQueueItem, rhs: TranscriptionQueueItem) -> Bool {
        // Higher priority items come first
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        
        // For same priority, older items come first
        return lhs.createdAt < rhs.createdAt
    }
}