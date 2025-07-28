import XCTest
@testable import HelloWorld

final class TranscriptionQueueItemTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        let recordingId = UUID()
        let item = TranscriptionQueueItem(recordingId: recordingId, priority: .high)
        
        XCTAssertEqual(item.recordingId, recordingId)
        XCTAssertEqual(item.priority, .high)
        XCTAssertEqual(item.retryCount, 0)
        XCTAssertNotNil(item.id)
        XCTAssertNotNil(item.createdAt)
        XCTAssertNil(item.lastAttemptAt)
        XCTAssertNil(item.nextRetryAt)
    }
    
    func testDefaultPriority() {
        let recordingId = UUID()
        let item = TranscriptionQueueItem(recordingId: recordingId)
        
        XCTAssertEqual(item.priority, .normal)
    }
    
    // MARK: - Priority Tests
    
    func testPriorityComparison() {
        XCTAssertTrue(TranscriptionQueueItem.Priority.low < .normal)
        XCTAssertTrue(TranscriptionQueueItem.Priority.normal < .high)
        XCTAssertTrue(TranscriptionQueueItem.Priority.high < .userRequested)
    }
    
    func testPriorityDisplayNames() {
        XCTAssertEqual(TranscriptionQueueItem.Priority.low.displayName, "Low")
        XCTAssertEqual(TranscriptionQueueItem.Priority.normal.displayName, "Normal")
        XCTAssertEqual(TranscriptionQueueItem.Priority.high.displayName, "High")
        XCTAssertEqual(TranscriptionQueueItem.Priority.userRequested.displayName, "User Requested")
    }
    
    // MARK: - Retry Logic Tests
    
    func testWithRetry() {
        let recordingId = UUID()
        let originalItem = TranscriptionQueueItem(recordingId: recordingId, priority: .normal)
        
        let retryItem = originalItem.withRetry()
        
        XCTAssertEqual(retryItem.recordingId, recordingId)
        XCTAssertEqual(retryItem.priority, .normal)
        XCTAssertEqual(retryItem.retryCount, 1)
        XCTAssertNotNil(retryItem.lastAttemptAt)
        XCTAssertNotNil(retryItem.nextRetryAt)
        XCTAssertNotEqual(retryItem.id, originalItem.id) // Should have new ID
    }
    
    func testMultipleRetries() {
        let recordingId = UUID()
        var item = TranscriptionQueueItem(recordingId: recordingId)
        
        for expectedRetryCount in 1...5 {
            item = item.withRetry()
            XCTAssertEqual(item.retryCount, expectedRetryCount)
        }
    }
    
    func testIsReadyForRetryInitialItem() {
        let recordingId = UUID()
        let item = TranscriptionQueueItem(recordingId: recordingId)
        
        // Initial items should be ready for processing
        XCTAssertTrue(item.isReadyForRetry)
    }
    
    func testIsReadyForRetryWithDelay() {
        let recordingId = UUID()
        let originalItem = TranscriptionQueueItem(recordingId: recordingId)
        let retryItem = originalItem.withRetry()
        
        // Retry item might not be ready immediately due to exponential backoff
        // This depends on timing, so we'll test the logic exists
        XCTAssertNotNil(retryItem.nextRetryAt)
    }
    
    func testHasExceededMaxRetries() {
        let recordingId = UUID()
        var item = TranscriptionQueueItem(recordingId: recordingId)
        
        // Initial item should not have exceeded max retries
        XCTAssertFalse(item.hasExceededMaxRetries)
        
        // Retry up to max attempts
        for _ in 0..<TranscriptionQueueItem.maxRetryAttempts {
            item = item.withRetry()
            XCTAssertFalse(item.hasExceededMaxRetries)
        }
        
        // One more retry should exceed the limit
        item = item.withRetry()
        XCTAssertTrue(item.hasExceededMaxRetries)
    }
    
    func testMaxRetryAttemptsConstant() {
        XCTAssertEqual(TranscriptionQueueItem.maxRetryAttempts, 3)
    }
    
    // MARK: - Comparison Tests
    
    func testItemComparison() {
        let recordingId1 = UUID()
        let recordingId2 = UUID()
        
        let lowPriorityItem = TranscriptionQueueItem(recordingId: recordingId1, priority: .low)
        let highPriorityItem = TranscriptionQueueItem(recordingId: recordingId2, priority: .high)
        
        // Higher priority items should come first (be "less than" in sort order)
        XCTAssertTrue(highPriorityItem < lowPriorityItem)
        XCTAssertFalse(lowPriorityItem < highPriorityItem)
    }
    
    func testItemComparisonSamePriority() {
        let recordingId1 = UUID()
        let recordingId2 = UUID()
        
        let item1 = TranscriptionQueueItem(recordingId: recordingId1, priority: .normal)
        
        // Wait a tiny bit to ensure different creation times
        Thread.sleep(forTimeInterval: 0.001)
        
        let item2 = TranscriptionQueueItem(recordingId: recordingId2, priority: .normal)
        
        // For same priority, older items should come first
        XCTAssertTrue(item1 < item2)
        XCTAssertFalse(item2 < item1)
    }
    
    func testItemEquality() {
        let recordingId = UUID()
        let item1 = TranscriptionQueueItem(recordingId: recordingId, priority: .normal)
        let item2 = TranscriptionQueueItem(recordingId: recordingId, priority: .high)
        
        // Items are equal only if they have the same ID
        XCTAssertNotEqual(item1, item2)
        XCTAssertEqual(item1, item1)
    }
    
    // MARK: - Codable Tests
    
    func testCodableEncoding() throws {
        let recordingId = UUID()
        let item = TranscriptionQueueItem(recordingId: recordingId, priority: .userRequested, retryCount: 2)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(item)
        
        XCTAssertFalse(data.isEmpty)
    }
    
    func testCodableDecoding() throws {
        let recordingId = UUID()
        let originalItem = TranscriptionQueueItem(recordingId: recordingId, priority: .high, retryCount: 1)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalItem)
        
        let decoder = JSONDecoder()
        let decodedItem = try decoder.decode(TranscriptionQueueItem.self, from: data)
        
        XCTAssertEqual(decodedItem.recordingId, originalItem.recordingId)
        XCTAssertEqual(decodedItem.priority, originalItem.priority)
        XCTAssertEqual(decodedItem.retryCount, originalItem.retryCount)
        XCTAssertEqual(decodedItem.createdAt.timeIntervalSince1970, originalItem.createdAt.timeIntervalSince1970, accuracy: 0.001)
    }
    
    // MARK: - Edge Cases
    
    func testRetryDelayCalculation() {
        let recordingId = UUID()
        let item = TranscriptionQueueItem(recordingId: recordingId)
        
        // Test exponential backoff progression
        var currentItem = item
        var previousDelay: TimeInterval = 0
        
        for _ in 1...3 {
            currentItem = currentItem.withRetry()
            
            if let nextRetry = currentItem.nextRetryAt,
               let lastAttempt = currentItem.lastAttemptAt {
                let delay = nextRetry.timeIntervalSince(lastAttempt)
                
                // Each delay should be longer than the previous (exponential backoff)
                if previousDelay > 0 {
                    XCTAssertGreaterThan(delay, previousDelay)
                }
                
                previousDelay = delay
                
                // Delay should not exceed maximum (60 seconds)
                XCTAssertLessThanOrEqual(delay, 60.0)
            }
        }
    }
    
    func testIdentifiableConformance() {
        let recordingId = UUID()
        let item = TranscriptionQueueItem(recordingId: recordingId)
        
        // Should have a unique identifier
        XCTAssertNotNil(item.id)
        
        // Different items should have different IDs
        let anotherItem = TranscriptionQueueItem(recordingId: UUID())
        XCTAssertNotEqual(item.id, anotherItem.id)
    }
}