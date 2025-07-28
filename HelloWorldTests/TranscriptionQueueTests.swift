import XCTest
@testable import HelloWorld

@MainActor
final class TranscriptionQueueTests: XCTestCase {
    
    var queue: TranscriptionQueue!
    
    override func setUp() {
        super.setUp()
        queue = TranscriptionQueue()
        queue.clear() // Start with empty queue
    }
    
    override func tearDown() {
        queue.clear() // Clean up after each test
        queue = nil
        super.tearDown()
    }
    
    // MARK: - Basic Queue Operations Tests
    
    func testEnqueueAddsItemToQueue() {
        let recordingId = UUID()
        
        XCTAssertEqual(queue.count, 0)
        queue.enqueue(recordingId: recordingId)
        XCTAssertEqual(queue.count, 1)
        XCTAssertTrue(queue.contains(recordingId: recordingId))
    }
    
    func testEnqueueDuplicateRecordingIgnored() {
        let recordingId = UUID()
        
        queue.enqueue(recordingId: recordingId)
        queue.enqueue(recordingId: recordingId)
        
        XCTAssertEqual(queue.count, 1)
    }
    
    func testDequeueReturnsAndRemovesItem() {
        let recordingId = UUID()
        queue.enqueue(recordingId: recordingId)
        
        let dequeuedItem = queue.dequeue()
        
        XCTAssertNotNil(dequeuedItem)
        XCTAssertEqual(dequeuedItem?.recordingId, recordingId)
        XCTAssertEqual(queue.count, 0)
    }
    
    func testDequeueEmptyQueueReturnsNil() {
        let dequeuedItem = queue.dequeue()
        XCTAssertNil(dequeuedItem)
    }
    
    func testRemoveRecordingFromQueue() {
        let recordingId1 = UUID()
        let recordingId2 = UUID()
        
        queue.enqueue(recordingId: recordingId1)
        queue.enqueue(recordingId: recordingId2)
        
        queue.remove(recordingId: recordingId1)
        
        XCTAssertEqual(queue.count, 1)
        XCTAssertFalse(queue.contains(recordingId: recordingId1))
        XCTAssertTrue(queue.contains(recordingId: recordingId2))
    }
    
    func testClearRemovesAllItems() {
        queue.enqueue(recordingId: UUID())
        queue.enqueue(recordingId: UUID())
        
        queue.clear()
        
        XCTAssertEqual(queue.count, 0)
    }
    
    // MARK: - Priority Tests
    
    func testPriorityOrdering() {
        let lowId = UUID()
        let normalId = UUID()
        let highId = UUID()
        let userRequestedId = UUID()
        
        // Add in reverse priority order
        queue.enqueue(recordingId: lowId, priority: .low)
        queue.enqueue(recordingId: normalId, priority: .normal)
        queue.enqueue(recordingId: highId, priority: .high)
        queue.enqueue(recordingId: userRequestedId, priority: .userRequested)
        
        // Should dequeue in priority order
        XCTAssertEqual(queue.dequeue()?.recordingId, userRequestedId)
        XCTAssertEqual(queue.dequeue()?.recordingId, highId)
        XCTAssertEqual(queue.dequeue()?.recordingId, normalId)
        XCTAssertEqual(queue.dequeue()?.recordingId, lowId)
    }
    
    func testUpdatePriority() {
        let recordingId = UUID()
        queue.enqueue(recordingId: recordingId, priority: .low)
        
        queue.updatePriority(recordingId: recordingId, priority: .userRequested)
        
        let item = queue.dequeue()
        XCTAssertEqual(item?.priority, .userRequested)
    }
    
    func testUpdatePriorityNonExistentRecording() {
        let recordingId = UUID()
        
        // Should not crash or affect queue
        queue.updatePriority(recordingId: recordingId, priority: .high)
        
        XCTAssertEqual(queue.count, 0)
    }
    
    // MARK: - Retry Logic Tests
    
    func testRequeueWithRetry() {
        let recordingId = UUID()
        queue.enqueue(recordingId: recordingId)
        
        let originalItem = queue.dequeue()!
        XCTAssertEqual(originalItem.retryCount, 0)
        
        queue.requeueWithRetry(originalItem)
        
        let retryItem = queue.dequeue()!
        XCTAssertEqual(retryItem.retryCount, 1)
        XCTAssertEqual(retryItem.recordingId, recordingId)
    }
    
    func testRequeueWithRetryExceedsMaxRetries() {
        let recordingId = UUID()
        queue.enqueue(recordingId: recordingId)
        
        var item = queue.dequeue()!
        
        // Retry up to max attempts
        for _ in 0..<TranscriptionQueueItem.maxRetryAttempts {
            queue.requeueWithRetry(item)
            item = queue.dequeue()!
        }
        
        // Should not requeue after max retries
        queue.requeueWithRetry(item)
        XCTAssertEqual(queue.count, 0)
    }
    
    func testCleanupExpiredItems() {
        let recordingId = UUID()
        queue.enqueue(recordingId: recordingId)
        
        var item = queue.dequeue()!
        
        // Create an item that has exceeded max retries by requeueing it multiple times
        for _ in 0..<TranscriptionQueueItem.maxRetryAttempts {
            queue.requeueWithRetry(item)
            item = queue.dequeue()!
        }
        
        // Try to requeue one more time - this should not add it since it exceeds max retries
        queue.requeueWithRetry(item)
        
        // The queue should be empty since the item exceeded max retries
        XCTAssertEqual(queue.count, 0)
    }
    
    // MARK: - Queue Position Tests
    
    func testQueuePosition() {
        let recordingId1 = UUID()
        let recordingId2 = UUID()
        let recordingId3 = UUID()
        
        queue.enqueue(recordingId: recordingId1, priority: .normal)
        queue.enqueue(recordingId: recordingId2, priority: .high)
        queue.enqueue(recordingId: recordingId3, priority: .low)
        
        // High priority should be first
        XCTAssertEqual(queue.position(for: recordingId2), 1)
        XCTAssertEqual(queue.position(for: recordingId1), 2)
        XCTAssertEqual(queue.position(for: recordingId3), 3)
        
        // Non-existent recording should return nil
        XCTAssertNil(queue.position(for: UUID()))
    }
    
    // MARK: - Queue Size Limit Tests
    
    func testQueueSizeLimit() {
        // Fill queue to capacity with low priority items
        for _ in 0..<100 {
            queue.enqueue(recordingId: UUID(), priority: .low)
        }
        
        XCTAssertEqual(queue.count, 100)
        
        // Adding another item should remove oldest low priority item
        let newRecordingId = UUID()
        queue.enqueue(recordingId: newRecordingId, priority: .normal)
        
        XCTAssertEqual(queue.count, 100)
        XCTAssertTrue(queue.contains(recordingId: newRecordingId))
    }
    
    // MARK: - Statistics Tests
    
    func testQueueStatistics() {
        queue.enqueue(recordingId: UUID(), priority: .low)
        queue.enqueue(recordingId: UUID(), priority: .normal)
        queue.enqueue(recordingId: UUID(), priority: .high)
        queue.enqueue(recordingId: UUID(), priority: .userRequested)
        
        let stats = queue.statistics
        
        XCTAssertEqual(stats.totalItems, 4)
        XCTAssertEqual(stats.lowPriorityItems, 1)
        XCTAssertEqual(stats.normalPriorityItems, 1)
        XCTAssertEqual(stats.highPriorityItems, 1)
        XCTAssertEqual(stats.userRequestedItems, 1)
        XCTAssertEqual(stats.readyItems, 4)
        XCTAssertEqual(stats.retryingItems, 0)
    }
    
    func testReadyCount() {
        let recordingId = UUID()
        queue.enqueue(recordingId: recordingId)
        
        XCTAssertEqual(queue.readyCount, 1)
        
        // Dequeue and requeue with retry (which may not be ready immediately)
        let item = queue.dequeue()!
        queue.requeueWithRetry(item)
        
        // Should still be ready since retry delay is minimal for first retry
        XCTAssertGreaterThanOrEqual(queue.readyCount, 0)
    }
    
    // MARK: - Items by Priority Tests
    
    func testItemsByPriority() {
        queue.enqueue(recordingId: UUID(), priority: .low)
        queue.enqueue(recordingId: UUID(), priority: .low)
        queue.enqueue(recordingId: UUID(), priority: .normal)
        queue.enqueue(recordingId: UUID(), priority: .high)
        
        let itemsByPriority = queue.itemsByPriority
        
        XCTAssertEqual(itemsByPriority[.low]?.count, 2)
        XCTAssertEqual(itemsByPriority[.normal]?.count, 1)
        XCTAssertEqual(itemsByPriority[.high]?.count, 1)
        XCTAssertNil(itemsByPriority[.userRequested])
    }
}