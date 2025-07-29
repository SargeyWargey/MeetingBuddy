import Foundation

// MARK: - Summary Queue

class SummaryQueue {
    
    // MARK: - Constants
    
    private let queueFileName = "summary_queue.json"
    private let maxQueueSize = 100
    private let processingTimeout: TimeInterval = 300 // 5 minutes
    
    // MARK: - Properties
    
    private let queueFile: URL
    private var queueData: QueueData
    private let queue = DispatchQueue(label: "SummaryQueue", qos: .utility)
    private var isProcessing = false
    
    // MARK: - Initialization
    
    init() {
        // Create queue file path
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.queueFile = documentsPath.appendingPathComponent(queueFileName)
        
        // Load existing queue data
        self.queueData = Self.loadQueueData(from: queueFile)
        
        // Clean up any stale processing items
        cleanupStaleItems()
    }
    
    // MARK: - Public Methods
    
    /// Enqueues a summary generation request
    func enqueue(
        recordingId: UUID,
        transcription: String,
        type: SummaryType,
        length: SummaryLength,
        priority: QueuePriority = .normal
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    // Check if item already exists
                    if self.queueData.items.contains(where: { $0.recordingId == recordingId && $0.type == type && $0.length == length }) {
                        continuation.resume(throwing: SummaryError.unknownError("Item already in queue"))
                        return
                    }
                    
                    // Check queue size limit
                    if self.queueData.items.count >= self.maxQueueSize {
                        // Remove oldest low-priority item if possible
                        if let oldestLowPriorityIndex = self.queueData.items.enumerated().first(where: { $0.element.priority == .low })?.offset {
                            self.queueData.items.remove(at: oldestLowPriorityIndex)
                        } else {
                            continuation.resume(throwing: SummaryError.unknownError("Queue is full"))
                            return
                        }
                    }
                    
                    // Create queue item
                    let item = SummaryQueueItem(
                        id: UUID(),
                        recordingId: recordingId,
                        transcription: transcription,
                        type: type,
                        length: length,
                        priority: priority,
                        createdAt: Date(),
                        attempts: 0,
                        status: .pending
                    )
                    
                    // Insert based on priority
                    self.insertItemByPriority(item)
                    
                    // Save queue
                    try self.saveQueueData()
                    
                    // Notify about queue update
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .summaryQueueUpdated, object: self)
                    }
                    
                    continuation.resume()
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Processes the queue with the provided processing function
    func processQueue(_ processor: @escaping (SummaryQueueItem) async throws -> Void) async {
        await withCheckedContinuation { continuation in
            queue.async {
                guard !self.isProcessing else {
                    continuation.resume()
                    return
                }
                
                self.isProcessing = true
                self.queueData.lastProcessedAt = Date()
                
                Task {
                    await self.processQueueItems(processor)
                    
                    self.queue.async {
                        self.isProcessing = false
                        try? self.saveQueueData()
                        
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .summaryQueueUpdated, object: self)
                        }
                        
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    /// Gets the current queue status
    func getStatus() -> SummaryQueueStatus {
        return queue.sync {
            return SummaryQueueStatus(
                pendingCount: queueData.items.filter { $0.status == .pending }.count,
                isProcessing: isProcessing,
                lastProcessedAt: queueData.lastProcessedAt,
                nextProcessingAt: calculateNextProcessingTime()
            )
        }
    }
    
    /// Clears all items from the queue
    func clear() {
        queue.sync {
            queueData.items.removeAll()
            try? saveQueueData()
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .summaryQueueUpdated, object: self)
            }
        }
    }
    
    /// Removes a specific item from the queue
    func removeItem(withId itemId: UUID) {
        queue.sync {
            queueData.items.removeAll { $0.id == itemId }
            try? saveQueueData()
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .summaryQueueUpdated, object: self)
            }
        }
    }
    
    /// Gets all queue items (for debugging/monitoring)
    func getAllItems() -> [SummaryQueueItem] {
        return queue.sync {
            return queueData.items
        }
    }
    
    /// Gets queue statistics
    func getStatistics() -> QueueStatistics {
        return queue.sync {
            let now = Date()
            let pendingItems = queueData.items.filter { $0.status == .pending }
            let failedItems = queueData.items.filter { $0.status == .failed }
            
            let averageWaitTime: TimeInterval
            if !pendingItems.isEmpty {
                let totalWaitTime = pendingItems.reduce(0) { $0 + now.timeIntervalSince($1.createdAt) }
                averageWaitTime = totalWaitTime / Double(pendingItems.count)
            } else {
                averageWaitTime = 0
            }
            
            return QueueStatistics(
                totalItems: queueData.items.count,
                pendingItems: pendingItems.count,
                processingItems: queueData.items.filter { $0.status == .processing }.count,
                failedItems: failedItems.count,
                averageWaitTime: averageWaitTime,
                oldestPendingItem: pendingItems.min(by: { $0.createdAt < $1.createdAt })?.createdAt
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func insertItemByPriority(_ item: SummaryQueueItem) {
        // Find the correct position based on priority
        var insertIndex = queueData.items.count
        
        for (index, existingItem) in queueData.items.enumerated() {
            if item.priority.rawValue > existingItem.priority.rawValue {
                insertIndex = index
                break
            }
        }
        
        queueData.items.insert(item, at: insertIndex)
    }
    
    private func processQueueItems(_ processor: @escaping (SummaryQueueItem) async throws -> Void) async {
        let pendingItems = queue.sync {
            return queueData.items.filter { $0.status == .pending }
        }
        
        for item in pendingItems {
            // Update item status to processing
            queue.sync {
                if let index = queueData.items.firstIndex(where: { $0.id == item.id }) {
                    queueData.items[index].status = .processing
                    queueData.items[index].lastAttemptAt = Date()
                }
            }
            
            do {
                // Process the item
                try await processor(item)
                
                // Remove successful item from queue
                queue.sync {
                    queueData.items.removeAll { $0.id == item.id }
                }
                
            } catch {
                // Handle failed processing
                queue.sync {
                    if let index = queueData.items.firstIndex(where: { $0.id == item.id }) {
                        queueData.items[index].attempts += 1
                        queueData.items[index].lastError = error.localizedDescription
                        
                        // Mark as failed if max attempts reached
                        if queueData.items[index].attempts >= 3 {
                            queueData.items[index].status = .failed
                        } else {
                            queueData.items[index].status = .pending
                        }
                    }
                }
                
                // Add delay before processing next item on failure
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            }
        }
    }
    
    private func cleanupStaleItems() {
        let now = Date()
        let staleThreshold = now.addingTimeInterval(-processingTimeout)
        
        for index in queueData.items.indices.reversed() {
            let item = queueData.items[index]
            
            // Reset stale processing items to pending
            if item.status == .processing,
               let lastAttempt = item.lastAttemptAt,
               lastAttempt < staleThreshold {
                queueData.items[index].status = .pending
            }
            
            // Remove very old failed items (older than 7 days)
            if item.status == .failed,
               now.timeIntervalSince(item.createdAt) > 7 * 24 * 60 * 60 {
                queueData.items.remove(at: index)
            }
        }
        
        try? saveQueueData()
    }
    
    private func calculateNextProcessingTime() -> Date? {
        guard !queueData.items.isEmpty else { return nil }
        
        // If there are pending items, next processing could be immediate
        if queueData.items.contains(where: { $0.status == .pending }) {
            return Date()
        }
        
        // Otherwise, estimate based on failed items with backoff
        let failedItems = queueData.items.filter { $0.status == .failed }
        guard let nextRetryItem = failedItems.min(by: { $0.lastAttemptAt ?? $0.createdAt < $1.lastAttemptAt ?? $1.createdAt }) else {
            return nil
        }
        
        let backoffDelay = min(300.0 * pow(2.0, Double(nextRetryItem.attempts)), 3600.0) // Max 1 hour
        return (nextRetryItem.lastAttemptAt ?? nextRetryItem.createdAt).addingTimeInterval(backoffDelay)
    }
    
    private func saveQueueData() throws {
        let data = try JSONEncoder().encode(queueData)
        try data.write(to: queueFile)
    }
    
    private static func loadQueueData(from url: URL) -> QueueData {
        guard let data = try? Data(contentsOf: url),
              let queueData = try? JSONDecoder().decode(QueueData.self, from: data) else {
            return QueueData()
        }
        return queueData
    }
}

// MARK: - Queue Data Models

private struct QueueData: Codable {
    var items: [SummaryQueueItem] = []
    var lastProcessedAt: Date?
}

// MARK: - Summary Queue Item

struct SummaryQueueItem: Codable, Identifiable {
    let id: UUID
    let recordingId: UUID
    let transcription: String
    let type: SummaryType
    let length: SummaryLength
    let priority: QueuePriority
    let createdAt: Date
    var attempts: Int
    var status: QueueItemStatus
    var lastAttemptAt: Date?
    var lastError: String?
    
    var displayTitle: String {
        return "Summary (\(type.displayName), \(length.displayName))"
    }
    
    var waitTime: TimeInterval {
        return Date().timeIntervalSince(createdAt)
    }
    
    var formattedWaitTime: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: waitTime) ?? "0m"
    }
}

// MARK: - Queue Priority

enum QueuePriority: Int, Codable, CaseIterable {
    case low = 0
    case normal = 1
    case high = 2
    case urgent = 3
    
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }
}

// MARK: - Queue Item Status

enum QueueItemStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case processing = "processing"
    case failed = "failed"
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .processing: return "Processing"
        case .failed: return "Failed"
        }
    }
    
    var icon: String {
        switch self {
        case .pending: return "clock"
        case .processing: return "gear"
        case .failed: return "xmark.circle"
        }
    }
    
    var color: String {
        switch self {
        case .pending: return "orange"
        case .processing: return "blue"
        case .failed: return "red"
        }
    }
}

// MARK: - Queue Statistics

struct QueueStatistics {
    let totalItems: Int
    let pendingItems: Int
    let processingItems: Int
    let failedItems: Int
    let averageWaitTime: TimeInterval
    let oldestPendingItem: Date?
    
    var formattedAverageWaitTime: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: averageWaitTime) ?? "0m"
    }
    
    var successRate: Double {
        guard totalItems > 0 else { return 1.0 }
        let successfulItems = totalItems - failedItems
        return Double(successfulItems) / Double(totalItems)
    }
}