import Foundation

/// Manages a persistent queue of transcription requests with priority-based processing
@MainActor
class TranscriptionQueue: ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var items: [TranscriptionQueueItem] = []
    @Published private(set) var isProcessing = false
    
    // MARK: - Private Properties
    private let userDefaults = UserDefaults.standard
    private let queueKey = "TranscriptionQueue"
    private let maxQueueSize = 100
    
    // MARK: - Initialization
    init() {
        loadQueue()
    }
    
    // MARK: - Public Methods
    
    /// Adds a new transcription request to the queue
    func enqueue(recordingId: UUID, priority: TranscriptionQueueItem.Priority = .normal) {
        // Check if item already exists in queue
        if items.contains(where: { $0.recordingId == recordingId }) {
            return
        }
        
        // Check queue size limit
        if items.count >= maxQueueSize {
            // Remove oldest low priority item to make space
            if let oldestLowPriorityIndex = items.lastIndex(where: { $0.priority == .low }) {
                items.remove(at: oldestLowPriorityIndex)
            } else {
                // If no low priority items, remove oldest normal priority
                if let oldestNormalIndex = items.lastIndex(where: { $0.priority == .normal }) {
                    items.remove(at: oldestNormalIndex)
                }
            }
        }
        
        let queueItem = TranscriptionQueueItem(recordingId: recordingId, priority: priority)
        items.append(queueItem)
        sortQueue()
        saveQueue()
    }
    
    /// Removes the next item from the queue for processing
    func dequeue() -> TranscriptionQueueItem? {
        // Find the next ready item (highest priority and ready for retry)
        guard let index = items.firstIndex(where: { $0.isReadyForRetry && !$0.hasExceededMaxRetries }) else {
            return nil
        }
        
        let item = items.remove(at: index)
        saveQueue()
        return item
    }
    
    /// Removes a specific recording from the queue
    func remove(recordingId: UUID) {
        items.removeAll { $0.recordingId == recordingId }
        saveQueue()
    }
    
    /// Adds a failed item back to the queue with retry logic
    func requeueWithRetry(_ item: TranscriptionQueueItem) {
        let retryItem = item.withRetry()
        
        // Only requeue if not exceeded max retries
        if !retryItem.hasExceededMaxRetries {
            items.append(retryItem)
            sortQueue()
            saveQueue()
        }
    }
    
    /// Clears all items from the queue
    func clear() {
        items.removeAll()
        saveQueue()
    }
    
    /// Returns the count of items in the queue
    var count: Int {
        return items.count
    }
    
    /// Returns the count of items ready for processing
    var readyCount: Int {
        return items.count { $0.isReadyForRetry && !$0.hasExceededMaxRetries }
    }
    
    /// Returns items grouped by priority
    var itemsByPriority: [TranscriptionQueueItem.Priority: [TranscriptionQueueItem]] {
        return Dictionary(grouping: items) { $0.priority }
    }
    
    /// Checks if a specific recording is in the queue
    func contains(recordingId: UUID) -> Bool {
        return items.contains { $0.recordingId == recordingId }
    }
    
    /// Gets the queue position for a specific recording (1-based)
    func position(for recordingId: UUID) -> Int? {
        guard let index = items.firstIndex(where: { $0.recordingId == recordingId }) else {
            return nil
        }
        return index + 1
    }
    
    /// Updates the priority of an existing queue item
    func updatePriority(recordingId: UUID, priority: TranscriptionQueueItem.Priority) {
        guard let index = items.firstIndex(where: { $0.recordingId == recordingId }) else {
            return
        }
        
        let existingItem = items[index]
        let updatedItem = TranscriptionQueueItem(
            recordingId: recordingId,
            priority: priority,
            retryCount: existingItem.retryCount,
            lastAttemptAt: existingItem.lastAttemptAt
        )
        
        items[index] = updatedItem
        sortQueue()
        saveQueue()
    }
    
    /// Removes expired items that have exceeded retry limits
    func cleanupExpiredItems() {
        let originalCount = items.count
        items.removeAll { $0.hasExceededMaxRetries }
        
        if items.count != originalCount {
            saveQueue()
        }
    }
    
    // MARK: - Private Methods
    
    /// Sorts the queue by priority and creation time
    private func sortQueue() {
        items.sort()
    }
    
    /// Saves the queue to UserDefaults
    private func saveQueue() {
        do {
            let data = try JSONEncoder().encode(items)
            userDefaults.set(data, forKey: queueKey)
        } catch {
            print("Failed to save transcription queue: \(error)")
        }
    }
    
    /// Loads the queue from UserDefaults
    private func loadQueue() {
        guard let data = userDefaults.data(forKey: queueKey) else {
            return
        }
        
        do {
            items = try JSONDecoder().decode([TranscriptionQueueItem].self, from: data)
            sortQueue()
            cleanupExpiredItems()
        } catch {
            print("Failed to load transcription queue: \(error)")
            // Reset to empty queue if loading fails
            items = []
        }
    }
}

// MARK: - Queue Statistics
extension TranscriptionQueue {
    /// Statistics about the current queue state
    struct QueueStatistics {
        let totalItems: Int
        let readyItems: Int
        let retryingItems: Int
        let userRequestedItems: Int
        let highPriorityItems: Int
        let normalPriorityItems: Int
        let lowPriorityItems: Int
    }
    
    /// Returns current queue statistics
    var statistics: QueueStatistics {
        return QueueStatistics(
            totalItems: items.count,
            readyItems: readyCount,
            retryingItems: items.count { $0.retryCount > 0 },
            userRequestedItems: items.count { $0.priority == .userRequested },
            highPriorityItems: items.count { $0.priority == .high },
            normalPriorityItems: items.count { $0.priority == .normal },
            lowPriorityItems: items.count { $0.priority == .low }
        )
    }
}