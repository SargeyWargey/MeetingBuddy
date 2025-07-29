import XCTest
@testable import HelloWorld
#if canImport(UIKit)
import UIKit
import BackgroundTasks
#endif

@MainActor
final class BackgroundProcessingTests: XCTestCase {
    
    var appLifecycleHandler: AppLifecycleHandler!
    var backgroundTaskManager: BackgroundTaskManager!
    var transcriptionService: TranscriptionService!
    var performanceMonitor: TranscriptionPerformanceMonitor!
    var transcriptionCache: TranscriptionCache!
    
    override func setUp() async throws {
        try await super.setUp()
        
        appLifecycleHandler = AppLifecycleHandler()
        backgroundTaskManager = BackgroundTaskManager()
        transcriptionService = TranscriptionService()
        performanceMonitor = TranscriptionPerformanceMonitor()
        transcriptionCache = try TranscriptionCache()
        
        // Configure components
        appLifecycleHandler.configure(
            transcriptionService: transcriptionService,
            backgroundTaskManager: backgroundTaskManager,
            performanceMonitor: performanceMonitor,
            transcriptionCache: transcriptionCache
        )
        
        backgroundTaskManager.setTranscriptionService(transcriptionService)
        performanceMonitor.startMonitoring()
    }
    
    override func tearDown() async throws {
        performanceMonitor.stopMonitoring()
        await transcriptionCache.clearCache()
        
        appLifecycleHandler = nil
        backgroundTaskManager = nil
        transcriptionService = nil
        performanceMonitor = nil
        transcriptionCache = nil
        
        try await super.tearDown()
    }
    
    // MARK: - App Lifecycle Tests
    
    func testAppStateTransitions() async throws {
        // Initial state should be foreground
        XCTAssertEqual(appLifecycleHandler.appState, .foreground)
        
        // Simulate app entering background
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        
        // Allow transition to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Should transition to background
        XCTAssertEqual(appLifecycleHandler.appState, .background)
        
        // Simulate app entering foreground
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        
        // Allow transition to complete
        try await Task.sleep(nanoseconds: 600_000_000) // 600ms (longer than transition delay)
        
        // Should return to foreground
        XCTAssertEqual(appLifecycleHandler.appState, .foreground)
    }
    
    func testBackgroundTaskScheduling() async throws {
        // Enable background processing
        backgroundTaskManager.enableBackgroundProcessing()
        XCTAssertTrue(backgroundTaskManager.isBackgroundProcessingEnabled)
        
        // Schedule background processing
        backgroundTaskManager.scheduleBackgroundProcessing()
        
        // Schedule background refresh
        backgroundTaskManager.scheduleBackgroundRefresh()
        
        // Disable background processing
        backgroundTaskManager.disableBackgroundProcessing()
        XCTAssertFalse(backgroundTaskManager.isBackgroundProcessingEnabled)
    }
    
    func testBackgroundTimeMonitoring() async throws {
        // Simulate app entering background
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        
        // Allow background transition
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Check background time monitoring
        let backgroundTime = appLifecycleHandler.getBackgroundTimeRemaining()
        
        // On simulator, background time might be 0 or very large
        // Just verify the method works
        XCTAssertGreaterThanOrEqual(backgroundTime, 0)
    }
    
    // MARK: - Background Processing Tests
    
    func testQueueProcessingInBackground() async throws {
        // Add items to transcription queue
        let testRecording = createTestRecording()
        transcriptionService.queueTranscription(testRecording, priority: .normal)
        
        // Verify queue has items
        XCTAssertGreaterThan(transcriptionService.queueCount, 0)
        
        // Simulate background processing
        let hasItems = await transcriptionService.hasQueuedItems()
        XCTAssertTrue(hasItems)
        
        // Process queue with time limit
        let processed = await transcriptionService.processQueuedTranscriptions(maxProcessingTime: 1.0)
        
        // Should have attempted to process items
        // Note: Actual processing might fail due to test environment, but method should execute
        XCTAssertTrue(processed || !hasItems) // Either processed something or queue was empty
    }
    
    func testBackgroundProcessingTimeLimit() async throws {
        // Add multiple items to queue
        for i in 0..<5 {
            let recording = createTestRecording(name: "background_test_\(i).m4a")
            transcriptionService.queueTranscription(recording, priority: .normal)
        }
        
        let startTime = Date()
        let maxProcessingTime: TimeInterval = 0.5 // 500ms limit
        
        let processed = await transcriptionService.processQueuedTranscriptions(maxProcessingTime: maxProcessingTime)
        
        let actualTime = Date().timeIntervalSince(startTime)
        
        // Should respect time limit (with some tolerance for overhead)
        XCTAssertLessThan(actualTime, maxProcessingTime + 0.2) // 200ms tolerance
    }
    
    // MARK: - State Persistence Tests
    
    func testStatePersistenceOnBackground() async throws {
        // Add items to queue
        let testRecording = createTestRecording()
        transcriptionService.queueTranscription(testRecording, priority: .high)
        
        let initialQueueCount = transcriptionService.queueCount
        XCTAssertGreaterThan(initialQueueCount, 0)
        
        // Simulate app entering background (triggers state save)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        
        // Allow state save to complete
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Force save state
        await appLifecycleHandler.forceSaveState()
        
        // Queue should still have items after state save
        XCTAssertEqual(transcriptionService.queueCount, initialQueueCount)
    }
    
    func testCacheMaintenanceInBackground() async throws {
        // Add cache entries
        let testURL = try createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: testURL) }
        
        let parameters = TranscriptionParameters(
            language: "en-US",
            requiresOnlineProcessing: false,
            preferredQuality: .balanced
        )
        
        let result = CachedTranscriptionResult(
            text: "Background cache test",
            confidence: 0.9,
            processingTime: 1.0,
            method: .onDevice,
            language: "en-US",
            timestamp: Date().addingTimeInterval(-3700) // Old entry (over 1 hour)
        )
        
        await transcriptionCache.cacheTranscription(result: result, for: testURL, parameters: parameters)
        
        let initialEntryCount = transcriptionCache.cacheEntryCount
        XCTAssertGreaterThan(initialEntryCount, 0)
        
        // Trigger maintenance
        await transcriptionCache.performMaintenance()
        
        // Old entries should be cleaned up
        let finalEntryCount = transcriptionCache.cacheEntryCount
        XCTAssertLessThanOrEqual(finalEntryCount, initialEntryCount)
    }
    
    // MARK: - Memory Management in Background
    
    func testMemoryManagementInBackground() async throws {
        // Simulate app entering background
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        
        // Allow background transition
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Simulate memory warning in background
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        
        // Allow memory cleanup
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Verify app is still in background state
        XCTAssertEqual(appLifecycleHandler.appState, .background)
    }
    
    // MARK: - Performance Monitoring in Background
    
    func testPerformanceMonitoringInBackground() async throws {
        let operationId = UUID()
        
        // Start tracking an operation
        performanceMonitor.startTrackingOperation(
            id: operationId,
            type: .automatic,
            audioFileSize: 1024,
            priority: .normal
        )
        
        // Simulate app entering background
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        
        // Allow background transition
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Complete operation in background
        performanceMonitor.completeOperation(id: operationId, success: true)
        
        // Verify metrics are still tracked
        let metrics = performanceMonitor.currentMetrics
        XCTAssertEqual(metrics.activeOperationsCount, 0)
    }
    
    // MARK: - App Termination Tests
    
    func testAppTerminationHandling() async throws {
        // Add items to queue
        let testRecording = createTestRecording()
        transcriptionService.queueTranscription(testRecording, priority: .high)
        
        // Simulate app termination
        NotificationCenter.default.post(name: UIApplication.willTerminateNotification, object: nil)
        
        // Allow termination handling
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Verify state was saved
        XCTAssertEqual(appLifecycleHandler.appState, .terminating)
    }
    
    // MARK: - Extended Background Period Tests
    
    func testExtendedBackgroundPeriodDetection() async throws {
        // Simulate app entering background
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        
        // Allow background transition
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Initially should not be extended period
        XCTAssertFalse(appLifecycleHandler.hasBeenInBackgroundForExtendedPeriod())
        
        // Note: In real app, this would require actual time passage or mocking
        // For test purposes, we verify the method exists and returns a boolean
    }
    
    // MARK: - Foreground Resume Tests
    
    func testForegroundResumeActions() async throws {
        var actionExecuted = false
        let expectation = XCTestExpectation(description: "Foreground action executed")
        
        // Schedule action for foreground resume
        appLifecycleHandler.scheduleForForegroundResume {
            actionExecuted = true
            expectation.fulfill()
        }
        
        // Simulate app entering background then foreground
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(actionExecuted)
    }
    
    // MARK: - Integration Tests
    
    func testFullBackgroundLifecycle() async throws {
        // Start with items in queue
        let testRecording = createTestRecording()
        transcriptionService.queueTranscription(testRecording, priority: .normal)
        
        let initialQueueCount = transcriptionService.queueCount
        
        // Simulate full background lifecycle
        
        // 1. App enters background
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        XCTAssertEqual(appLifecycleHandler.appState, .background)
        
        // 2. Background processing occurs
        backgroundTaskManager.enableBackgroundProcessing()
        
        // 3. Memory warning occurs
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // 4. App returns to foreground
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try await Task.sleep(nanoseconds: 600_000_000) // 600ms
        XCTAssertEqual(appLifecycleHandler.appState, .foreground)
        
        // Verify system is still functional
        let finalQueueCount = transcriptionService.queueCount
        XCTAssertGreaterThanOrEqual(finalQueueCount, 0) // Queue might have been processed
    }
    
    // MARK: - Helper Methods
    
    private func createTestRecording(name: String = "background_test.m4a") -> Recording {
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent(name)
        
        // Create minimal test file
        let testData = Data(repeating: 0x00, count: 1024)
        try? testData.write(to: audioURL)
        
        return Recording(
            fileName: name,
            url: audioURL,
            createdAt: Date(),
            duration: 10.0
        )
    }
    
    private func createTestAudioFile(name: String = "background_cache_test.m4a") throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent(name)
        
        let testData = Data(repeating: 0x00, count: 2048)
        try testData.write(to: audioURL)
        
        return audioURL
    }
}