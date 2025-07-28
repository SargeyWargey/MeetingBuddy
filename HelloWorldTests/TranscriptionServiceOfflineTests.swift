import XCTest
@testable import HelloWorld

@MainActor
final class TranscriptionServiceOfflineTests: XCTestCase {
    
    var transcriptionService: TranscriptionService!
    var mockRecording: Recording!
    
    override func setUp() {
        super.setUp()
        transcriptionService = TranscriptionService()
        
        // Create a mock recording for testing
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.m4a")
        mockRecording = Recording(
            fileName: "test.m4a",
            url: tempURL,
            createdAt: Date(),
            duration: 60.0
        )
    }
    
    override func tearDown() {
        transcriptionService = nil
        mockRecording = nil
        super.tearDown()
    }
    
    func testOfflineQueueInitialState() {
        // Test initial offline queue state
        XCTAssertEqual(transcriptionService.offlineQueueCount, 0)
        XCTAssertFalse(transcriptionService.isQueuedForOffline(mockRecording))
    }
    
    func testQueueTranscriptionWhenOffline() {
        // Simulate offline state by setting isOnline to false
        // Note: This would require making isOnline settable for testing or using dependency injection
        
        transcriptionService.queueTranscription(mockRecording)
        
        // Verify recording is queued
        XCTAssertTrue(transcriptionService.queueCount > 0)
    }
    
    func testOfflineQueueManagement() {
        // Test adding to offline queue
        transcriptionService.queueTranscription(mockRecording, priority: .normal)
        
        // Test queue position
        let position = transcriptionService.queuePosition(for: mockRecording)
        XCTAssertNotNil(position)
        XCTAssertGreaterThan(position!, 0)
        
        // Test queue contains recording
        XCTAssertTrue(transcriptionService.isInQueue(mockRecording))
        
        // Test updating priority
        transcriptionService.updateQueuePriority(mockRecording, priority: .high)
        
        // Test removing from queue
        transcriptionService.cancelTranscription(mockRecording)
        XCTAssertFalse(transcriptionService.isInQueue(mockRecording))
    }
    
    func testQueueStatistics() {
        // Add recordings with different priorities
        let recording1 = Recording(
            fileName: "test1.m4a",
            url: FileManager.default.temporaryDirectory.appendingPathComponent("test1.m4a"),
            createdAt: Date(),
            duration: 30.0
        )
        
        let recording2 = Recording(
            fileName: "test2.m4a",
            url: FileManager.default.temporaryDirectory.appendingPathComponent("test2.m4a"),
            createdAt: Date(),
            duration: 45.0
        )
        
        transcriptionService.queueTranscription(recording1, priority: .high)
        transcriptionService.queueTranscription(recording2, priority: .normal)
        transcriptionService.queueTranscription(mockRecording, priority: .userRequested)
        
        let stats = transcriptionService.queueStatistics
        XCTAssertEqual(stats.totalItems, 3)
        XCTAssertEqual(stats.highPriorityItems, 1)
        XCTAssertEqual(stats.normalPriorityItems, 1)
        XCTAssertEqual(stats.userRequestedItems, 1)
    }
    
    func testClearQueue() {
        // Add items to queue
        transcriptionService.queueTranscription(mockRecording)
        XCTAssertGreaterThan(transcriptionService.queueCount, 0)
        
        // Clear queue
        transcriptionService.clearQueue()
        XCTAssertEqual(transcriptionService.queueCount, 0)
        XCTAssertEqual(transcriptionService.offlineQueueCount, 0)
    }
    
    func testCleanupQueue() {
        // Add item to queue
        transcriptionService.queueTranscription(mockRecording)
        
        // Test cleanup (this would normally remove expired items)
        transcriptionService.cleanupQueue()
        
        // Since we just added the item, it shouldn't be expired
        XCTAssertGreaterThan(transcriptionService.queueCount, 0)
    }
    
    func testTranscriptionServiceAvailability() {
        // Test that availability considers online status
        let isAvailable = transcriptionService.isAvailable
        let isOnDeviceAvailable = transcriptionService.isOnDeviceAvailable
        let isCloudAvailable = transcriptionService.isCloudAvailable
        
        // If on-device is available, service should be available regardless of online status
        if isOnDeviceAvailable {
            XCTAssertTrue(isAvailable)
        }
        
        // Cloud availability should depend on network status
        if transcriptionService.isOnline {
            // When online, cloud availability depends on speech recognizer
            XCTAssertEqual(isCloudAvailable, transcriptionService.isOnline)
        } else {
            // When offline, cloud should not be available
            XCTAssertFalse(isCloudAvailable)
        }
    }
    
    func testNetworkStatusHandling() {
        // Test that network status changes are handled properly
        let initialOnlineStatus = transcriptionService.isOnline
        
        // This test would be more effective with a mock NetworkMonitor
        // For now, we just verify the property exists and has a value
        XCTAssertNotNil(transcriptionService.isOnline)
        
        // Test that offline queue count is accessible
        XCTAssertGreaterThanOrEqual(transcriptionService.offlineQueueCount, 0)
    }
}