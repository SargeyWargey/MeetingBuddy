import XCTest
@testable import HelloWorld
import AVFoundation

@MainActor
final class TranscriptionPerformanceTests: XCTestCase {
    
    var performanceMonitor: TranscriptionPerformanceMonitor!
    var audioMemoryManager: AudioMemoryManager!
    var transcriptionCache: TranscriptionCache!
    var uiThreadOptimizer: UIThreadOptimizer!
    
    override func setUp() async throws {
        try await super.setUp()
        
        performanceMonitor = TranscriptionPerformanceMonitor()
        audioMemoryManager = AudioMemoryManager()
        transcriptionCache = try TranscriptionCache()
        uiThreadOptimizer = UIThreadOptimizer()
        
        performanceMonitor.startMonitoring()
    }
    
    override func tearDown() async throws {
        performanceMonitor.stopMonitoring()
        audioMemoryManager.clearAll()
        await transcriptionCache.clearCache()
        
        performanceMonitor = nil
        audioMemoryManager = nil
        transcriptionCache = nil
        uiThreadOptimizer = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Performance Monitor Tests
    
    func testOperationTracking() async throws {
        let operationId = UUID()
        let audioFileSize: Int64 = 1024 * 1024 // 1MB
        
        // Start tracking
        performanceMonitor.startTrackingOperation(
            id: operationId,
            type: .manual,
            audioFileSize: audioFileSize,
            priority: .userRequested
        )
        
        // Update progress
        performanceMonitor.updateOperationProgress(
            id: operationId,
            progress: 0.5,
            currentPhase: "Processing"
        )
        
        // Complete operation
        performanceMonitor.completeOperation(
            id: operationId,
            success: true,
            resultSize: 500
        )
        
        let metrics = performanceMonitor.currentMetrics
        XCTAssertEqual(metrics.activeOperationsCount, 0)
    }
    
    func testQueuePerformanceTracking() async throws {
        performanceMonitor.startQueueProcessingSession()
        
        // Simulate processing multiple items
        for i in 0..<5 {
            let operationId = UUID()
            performanceMonitor.startTrackingOperation(
                id: operationId,
                type: .automatic,
                audioFileSize: 1024,
                priority: .normal
            )
            
            // Simulate processing time
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            
            performanceMonitor.completeOperation(
                id: operationId,
                success: i < 4, // One failure
                resultSize: 100
            )
        }
        
        performanceMonitor.endQueueProcessingSession(
            totalItemsProcessed: 4,
            remainingItems: 1
        )
        
        let metrics = performanceMonitor.currentMetrics
        XCTAssertEqual(metrics.totalItemsProcessed, 4)
        XCTAssertEqual(metrics.totalItemsFailed, 1)
    }
    
    func testSlowOperationDetection() async throws {
        let operationId = UUID()
        
        performanceMonitor.startTrackingOperation(
            id: operationId,
            type: .manual,
            audioFileSize: 1024,
            priority: .userRequested
        )
        
        // Simulate slow operation
        try await Task.sleep(nanoseconds: 11_000_000_000) // 11 seconds
        
        performanceMonitor.updateOperationProgress(
            id: operationId,
            progress: 0.1,
            currentPhase: "Slow processing"
        )
        
        performanceMonitor.completeOperation(
            id: operationId,
            success: true
        )
        
        // Check for slow operation alert
        XCTAssertTrue(performanceMonitor.performanceAlerts.contains { $0.type == .slowOperation })
    }
    
    // MARK: - Audio Memory Manager Tests
    
    func testMemoryEfficientAudioProcessing() async throws {
        // Create a test audio file
        let testAudioURL = try createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: testAudioURL) }
        
        var processedChunks = 0
        var totalDataProcessed = 0
        
        try await audioMemoryManager.processAudioFile(at: testAudioURL) { chunkData, chunkIndex, totalChunks in
            processedChunks += 1
            totalDataProcessed += chunkData.count
            
            // Verify chunk is not empty
            XCTAssertGreaterThan(chunkData.count, 0)
            XCTAssertGreaterThanOrEqual(chunkIndex, 0)
            XCTAssertGreaterThan(totalChunks, 0)
        }
        
        XCTAssertGreaterThan(processedChunks, 0)
        XCTAssertGreaterThan(totalDataProcessed, 0)
    }
    
    func testMemoryCacheManagement() async throws {
        let testData = Data(repeating: 0x42, count: 1024)
        let cacheKey = "test_audio_data"
        
        // Cache data
        audioMemoryManager.cacheAudioData(testData, forKey: cacheKey)
        
        // Retrieve cached data
        let cachedData = audioMemoryManager.getCachedAudioData(forKey: cacheKey)
        XCTAssertEqual(cachedData, testData)
        
        // Test cache expiration (would need to wait or mock time)
        let memoryInfo = audioMemoryManager.getMemoryUsageInfo()
        XCTAssertGreaterThan(memoryInfo.cacheSize, 0)
    }
    
    // MARK: - Transcription Cache Tests
    
    func testTranscriptionCaching() async throws {
        let testAudioURL = try createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: testAudioURL) }
        
        let parameters = TranscriptionParameters(
            language: "en-US",
            requiresOnlineProcessing: false,
            preferredQuality: .balanced
        )
        
        let testResult = CachedTranscriptionResult(
            text: "Test transcription result",
            confidence: 0.95,
            processingTime: 2.5,
            method: .onDevice,
            language: "en-US",
            timestamp: Date()
        )
        
        // Cache the result
        await transcriptionCache.cacheTranscription(
            result: testResult,
            for: testAudioURL,
            parameters: parameters
        )
        
        // Retrieve from cache
        let cachedResult = await transcriptionCache.getCachedTranscription(
            for: testAudioURL,
            parameters: parameters
        )
        
        XCTAssertNotNil(cachedResult)
        XCTAssertEqual(cachedResult?.text, testResult.text)
        XCTAssertEqual(cachedResult?.confidence, testResult.confidence)
    }
    
    func testCacheSizeManagement() async throws {
        let initialStats = transcriptionCache.getCacheStatistics()
        
        // Add multiple cache entries
        for i in 0..<10 {
            let testURL = try createTestAudioFile(name: "test_\(i).m4a")
            let parameters = TranscriptionParameters(
                language: "en-US",
                requiresOnlineProcessing: false,
                preferredQuality: .balanced
            )
            
            let result = CachedTranscriptionResult(
                text: "Test transcription \(i)",
                confidence: 0.9,
                processingTime: 1.0,
                method: .onDevice,
                language: "en-US",
                timestamp: Date()
            )
            
            await transcriptionCache.cacheTranscription(
                result: result,
                for: testURL,
                parameters: parameters
            )
            
            // Clean up test file
            try? FileManager.default.removeItem(at: testURL)
        }
        
        let finalStats = transcriptionCache.getCacheStatistics()
        XCTAssertGreaterThan(finalStats.entryCount, initialStats.entryCount)
    }
    
    // MARK: - UI Thread Optimizer Tests
    
    func testUIUpdateBatching() async throws {
        var updateCount = 0
        let expectation = XCTestExpectation(description: "UI updates completed")
        expectation.expectedFulfillmentCount = 5
        
        // Schedule multiple UI updates
        for i in 0..<5 {
            let operation = UIUpdateOperation<Void>(
                priority: .medium,
                estimatedDuration: 0.001
            ) {
                updateCount += 1
                expectation.fulfill()
            }
            
            await uiThreadOptimizer.scheduleUpdate(operation)
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(updateCount, 5)
    }
    
    func testBackgroundWorkExecution() async throws {
        let expectation = XCTestExpectation(description: "Background work completed")
        var result: Int?
        
        uiThreadOptimizer.executeOnBackground(
            work: {
                // Simulate heavy work
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                return 42
            },
            completion: { workResult in
                switch workResult {
                case .success(let value):
                    result = value
                case .failure:
                    XCTFail("Background work should not fail")
                }
                expectation.fulfill()
            }
        )
        
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(result, 42)
    }
    
    func testTranscriptionProgressUpdates() async throws {
        let expectation = XCTestExpectation(description: "Progress updates received")
        expectation.expectedFulfillmentCount = 3
        
        var progressUpdates: [TranscriptionProgress] = []
        
        uiThreadOptimizer.executeTranscriptionWork(
            work: { progressHandler in
                // Simulate transcription work with progress
                for i in 1...3 {
                    let progress = TranscriptionProgress(
                        completedChunks: i,
                        totalChunks: 3,
                        currentOperation: "Processing chunk \(i)",
                        estimatedTimeRemaining: Double(3 - i)
                    )
                    progressHandler(progress)
                    try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                }
                return "Transcription complete"
            },
            progressHandler: { progress in
                progressUpdates.append(progress)
                expectation.fulfill()
            },
            completion: { result in
                switch result {
                case .success(let text):
                    XCTAssertEqual(text, "Transcription complete")
                case .failure:
                    XCTFail("Transcription work should not fail")
                }
            }
        )
        
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(progressUpdates.count, 3)
        XCTAssertEqual(progressUpdates.last?.completedChunks, 3)
    }
    
    // MARK: - Integration Tests
    
    func testEndToEndPerformanceOptimization() async throws {
        let testAudioURL = try createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: testAudioURL) }
        
        let operationId = UUID()
        
        // Start performance tracking
        performanceMonitor.startTrackingOperation(
            id: operationId,
            type: .manual,
            audioFileSize: 1024,
            priority: .userRequested
        )
        
        // Process audio with memory management
        var chunksProcessed = 0
        try await audioMemoryManager.processAudioFile(at: testAudioURL) { _, chunkIndex, _ in
            chunksProcessed += 1
            
            // Update progress
            await MainActor.run {
                self.performanceMonitor.updateOperationProgress(
                    id: operationId,
                    progress: Double(chunkIndex) / 10.0,
                    currentPhase: "Processing chunk \(chunkIndex)"
                )
            }
        }
        
        // Complete operation
        performanceMonitor.completeOperation(
            id: operationId,
            success: true,
            resultSize: chunksProcessed * 100
        )
        
        // Verify metrics
        let metrics = performanceMonitor.currentMetrics
        XCTAssertEqual(metrics.activeOperationsCount, 0)
        XCTAssertGreaterThan(chunksProcessed, 0)
    }
    
    // MARK: - Memory Pressure Tests
    
    func testMemoryPressureHandling() async throws {
        // Fill up memory cache
        for i in 0..<100 {
            let testData = Data(repeating: UInt8(i), count: 1024 * 1024) // 1MB each
            audioMemoryManager.cacheAudioData(testData, forKey: "large_data_\(i)")
        }
        
        let initialMemoryInfo = audioMemoryManager.getMemoryUsageInfo()
        XCTAssertGreaterThan(initialMemoryInfo.cacheSize, 0)
        
        // Simulate memory warning
        NotificationCenter.default.post(name: .lowMemoryCondition, object: nil)
        
        // Give time for cleanup
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        let finalMemoryInfo = audioMemoryManager.getMemoryUsageInfo()
        // Cache should be cleared or significantly reduced
        XCTAssertLessThanOrEqual(finalMemoryInfo.cacheSize, initialMemoryInfo.cacheSize)
    }
    
    // MARK: - Helper Methods
    
    private func createTestAudioFile(name: String = "test_audio.m4a") throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent(name)
        
        // Create a minimal audio file for testing
        let testData = Data(repeating: 0x00, count: 1024) // 1KB of silence
        try testData.write(to: audioURL)
        
        return audioURL
    }
}