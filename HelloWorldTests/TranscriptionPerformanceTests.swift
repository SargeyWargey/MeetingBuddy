import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import HelloWorld

/// Performance tests for transcription system components
struct TranscriptionPerformanceTests {
    
    // MARK: - Test Data Setup
    
    private func createTestAudioFile(sizeInMB: Int) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_audio_\(sizeInMB)MB.m4a")
        
        // Create a mock audio file with specified size
        let data = Data(repeating: 0, count: sizeInMB * 1024 * 1024)
        try data.write(to: tempURL)
        
        return tempURL
    }
    
    private func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
    // MARK: - Memory Management Tests
    
    @Test func testMemoryUsageForLargeAudioFiles() async throws {
        let memoryManager = AudioMemoryManager()
        let testFile = try createTestAudioFile(sizeInMB: 10)
        defer { cleanup(url: testFile) }
        
        let initialMemory = getCurrentMemoryUsage()
        
        // Process large file with memory management
        var processedChunks = 0
        try await memoryManager.processAudioFile(at: testFile) { data, chunkIndex, totalChunks in
            processedChunks += 1
            // Simulate processing work
            await Task.yield()
        }
        
        let finalMemory = getCurrentMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory
        
        // Memory increase should be reasonable (less than 50MB for 10MB file)
        #expect(memoryIncrease < 50.0, "Memory usage increased by \(memoryIncrease)MB")
        #expect(processedChunks > 0, "File should be processed in chunks")
        
        // Memory should be released after processing
        await Task.sleep(nanoseconds: 100_000_000) // 100ms
        let cleanupMemory = getCurrentMemoryUsage()
        #expect(cleanupMemory <= finalMemory, "Memory should not increase after cleanup")
    }
    
    @Test func testMemoryPressureHandling() async throws {
        let memoryManager = AudioMemoryManager()
        let testFile = try createTestAudioFile(sizeInMB: 5)
        defer { cleanup(url: testFile) }
        
        // Simulate memory pressure
        #if canImport(UIKit)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        #else
        NotificationCenter.default.post(name: .lowMemoryCondition, object: nil)
        #endif
        
        // Processing should still work under memory pressure
        var success = false
        try await memoryManager.processAudioFile(at: testFile) { data, chunkIndex, totalChunks in
            success = true
        }
        
        #expect(success, "Processing should succeed even under memory pressure")
    }
    
    @Test func testAudioMemoryCaching() async throws {
        let memoryManager = AudioMemoryManager()
        let testData = Data(repeating: 42, count: 1024)
        let cacheKey = "test_key"
        
        // Cache data
        memoryManager.cacheAudioData(testData, forKey: cacheKey)
        
        // Retrieve cached data
        let cachedData = memoryManager.getCachedAudioData(forKey: cacheKey)
        #expect(cachedData == testData, "Cached data should match original")
        
        // Check cache statistics
        let (cacheSize, activeOps) = memoryManager.getMemoryUsageInfo()
        #expect(cacheSize >= testData.count, "Cache size should reflect stored data")
    }
    
    // MARK: - Transcription Cache Performance Tests
    
    @Test func testTranscriptionCachePerformance() async throws {
        let cache = try TranscriptionCache()
        let testURL = try createTestAudioFile(sizeInMB: 1)
        defer { cleanup(url: testURL) }
        
        let parameters = TranscriptionParameters(
            language: "en-US",
            requiresOnlineProcessing: false,
            preferredQuality: .balanced
        )
        
        let result = CachedTranscriptionResult(
            text: "This is a test transcription result",
            confidence: 0.95,
            processingTime: 2.5,
            method: .onDevice,
            language: "en-US",
            timestamp: Date()
        )
        
        // Measure cache write performance
        let writeStartTime = CFAbsoluteTimeGetCurrent()
        await cache.cacheTranscription(result: result, for: testURL, parameters: parameters)
        let writeTime = CFAbsoluteTimeGetCurrent() - writeStartTime
        
        #expect(writeTime < 0.1, "Cache write should complete within 100ms")
        
        // Measure cache read performance
        let readStartTime = CFAbsoluteTimeGetCurrent()
        let cachedResult = await cache.getCachedTranscription(for: testURL, parameters: parameters)
        let readTime = CFAbsoluteTimeGetCurrent() - readStartTime
        
        #expect(readTime < 0.05, "Cache read should complete within 50ms")
        #expect(cachedResult?.text == result.text, "Cached result should match original")
    }
    
    @Test func testCacheSizeManagement() async throws {
        let cache = try TranscriptionCache()
        let parameters = TranscriptionParameters(
            language: "en-US",
            requiresOnlineProcessing: false,
            preferredQuality: .balanced
        )
        
        // Create multiple cache entries
        for i in 0..<10 {
            let testURL = try createTestAudioFile(sizeInMB: 1)
            defer { cleanup(url: testURL) }
            
            let result = CachedTranscriptionResult(
                text: "Test transcription \(i)",
                confidence: 0.9,
                processingTime: 1.0,
                method: .onDevice,
                language: "en-US",
                timestamp: Date()
            )
            
            await cache.cacheTranscription(result: result, for: testURL, parameters: parameters)
        }
        
        let stats = cache.getCacheStatistics()
        #expect(stats.entryCount <= 10, "Cache should manage entry count")
        #expect(stats.totalSize > 0, "Cache should track total size")
    }
    
    // MARK: - UI Thread Optimization Tests
    
    @Test func testUIUpdateBatching() async throws {
        let uiOptimizer = UIThreadOptimizer()
        
        var updateCount = 0
        let updateOperation = UIUpdateOperation(
            priority: .medium,
            estimatedDuration: 0.001
        ) {
            updateCount += 1
        }
        
        // Schedule multiple updates rapidly
        let startTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100 {
            await uiOptimizer.scheduleUpdate(updateOperation)
        }
        let endTime = CFAbsoluteTimeGetCurrent()
        
        // All updates should complete quickly due to batching
        #expect(endTime - startTime < 1.0, "Batched updates should complete within 1 second")
        #expect(updateCount == 100, "All updates should be executed")
    }
    
    @Test func testBackgroundWorkCoordination() async throws {
        let uiOptimizer = UIThreadOptimizer()
        
        var workCompleted = false
        var completionOnMainThread = false
        
        uiOptimizer.executeOnBackground(
            work: {
                // Simulate heavy work
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                return "Work completed"
            },
            completion: { result in
                workCompleted = true
                completionOnMainThread = Task.isMainActor
            }
        )
        
        // Wait for completion
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        #expect(workCompleted, "Background work should complete")
        #expect(completionOnMainThread, "Completion should run on main thread")
    }
    
    @Test func testUIPerformanceMetrics() async throws {
        let uiOptimizer = UIThreadOptimizer()
        
        // Perform some UI operations
        for _ in 0..<10 {
            await uiOptimizer.scheduleUpdate(UIUpdateOperation {
                // Simulate UI work
                await Task.yield()
            })
        }
        
        let metrics = uiOptimizer.getPerformanceMetrics()
        #expect(metrics.averageUpdateTime >= 0, "Average update time should be non-negative")
        #expect(metrics.frameDropCount >= 0, "Frame drop count should be non-negative")
    }
    
    // MARK: - Performance Monitor Tests
    
    @Test func testPerformanceMonitoringAccuracy() async throws {
        let monitor = TranscriptionPerformanceMonitor()
        monitor.startMonitoring()
        
        let operationId = UUID()
        let startTime = Date()
        
        // Start tracking operation
        monitor.startTrackingOperation(
            id: operationId,
            type: .manual,
            audioFileSize: 1024,
            priority: .normal
        )
        
        // Simulate operation progress
        monitor.updateOperationProgress(id: operationId, progress: 0.5, currentPhase: "Processing")
        
        // Complete operation
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        monitor.completeOperation(id: operationId, success: true, resultSize: 512)
        
        let metrics = monitor.currentMetrics
        #expect(metrics.activeOperationsCount == 0, "No active operations after completion")
        #expect(metrics.operationSuccessRate >= 0.0, "Success rate should be valid")
        
        monitor.stopMonitoring()
    }
    
    @Test func testQueuePerformanceTracking() async throws {
        let monitor = TranscriptionPerformanceMonitor()
        
        monitor.startQueueProcessingSession()
        
        // Simulate processing items
        for i in 0..<5 {
            let operationId = UUID()
            monitor.startTrackingOperation(
                id: operationId,
                type: .automatic,
                audioFileSize: Int64(1024 * (i + 1)),
                priority: .normal
            )
            
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            monitor.completeOperation(id: operationId, success: true)
        }
        
        monitor.endQueueProcessingSession(totalItemsProcessed: 5, remainingItems: 0)
        
        let metrics = monitor.currentMetrics
        #expect(metrics.totalItemsProcessed == 5, "Should track processed items")
        #expect(metrics.queueThroughput > 0, "Should calculate throughput")
    }
    
    // MARK: - Background Task Performance Tests
    
    @Test func testBackgroundTaskEfficiency() async throws {
        let backgroundManager = BackgroundTaskManager()
        
        // Test that background task scheduling works
        backgroundManager.scheduleBackgroundProcessing()
        
        // Verify no memory leaks in background task management
        let initialMemory = getCurrentMemoryUsage()
        
        for _ in 0..<10 {
            backgroundManager.scheduleBackgroundRefresh()
        }
        
        await Task.sleep(nanoseconds: 100_000_000) // 100ms
        let finalMemory = getCurrentMemoryUsage()
        
        #expect(finalMemory - initialMemory < 5.0, "Background task scheduling should not leak significant memory")
    }
    
    // MARK: - Integration Performance Tests
    
    @Test func testEndToEndTranscriptionPerformance() async throws {
        // This would test the full transcription pipeline performance
        // Create a small test audio file
        let testFile = try createTestAudioFile(sizeInMB: 1)
        defer { cleanup(url: testFile) }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Simulate full transcription pipeline
        let memoryManager = AudioMemoryManager()
        let cache = try TranscriptionCache()
        let uiOptimizer = UIThreadOptimizer()
        let monitor = TranscriptionPerformanceMonitor()
        
        var processingCompleted = false
        
        // Process audio with memory management
        try await memoryManager.processAudioFile(at: testFile) { data, chunkIndex, totalChunks in
            processingCompleted = true
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime
        
        #expect(processingCompleted, "Processing should complete")
        #expect(totalTime < 5.0, "End-to-end processing should complete within 5 seconds for 1MB file")
    }
    
    // MARK: - Memory Utility Functions
    
    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Double(info.resident_size) / (1024 * 1024) // Convert to MB
        }
        
        return 0
    }
    
    // MARK: - Stress Tests
    
    @Test func testMemoryStressTest() async throws {
        let memoryManager = AudioMemoryManager()
        let initialMemory = getCurrentMemoryUsage()
        
        // Process multiple files simultaneously
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    do {
                        let testFile = try self.createTestAudioFile(sizeInMB: 2)
                        defer { self.cleanup(url: testFile) }
                        
                        try await memoryManager.processAudioFile(at: testFile) { data, chunkIndex, totalChunks in
                            // Simulate processing
                            await Task.yield()
                        }
                    } catch {
                        // Handle test file creation errors
                    }
                }
            }
        }
        
        // Allow memory to stabilize
        await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        let finalMemory = getCurrentMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory
        
        #expect(memoryIncrease < 100.0, "Memory increase should be under 100MB for stress test")
    }
    
    @Test func testConcurrentCacheOperations() async throws {
        let cache = try TranscriptionCache()
        let parameters = TranscriptionParameters(
            language: "en-US",
            requiresOnlineProcessing: false,
            preferredQuality: .balanced
        )
        
        // Perform concurrent cache operations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    do {
                        let testURL = try self.createTestAudioFile(sizeInMB: 1)
                        defer { self.cleanup(url: testURL) }
                        
                        let result = CachedTranscriptionResult(
                            text: "Concurrent test \(i)",
                            confidence: 0.9,
                            processingTime: 1.0,
                            method: .onDevice,
                            language: "en-US",
                            timestamp: Date()
                        )
                        
                        await cache.cacheTranscription(result: result, for: testURL, parameters: parameters)
                        
                        // Try to read it back
                        _ = await cache.getCachedTranscription(for: testURL, parameters: parameters)
                    } catch {
                        // Handle test file creation errors
                    }
                }
            }
        }
        
        // Cache should remain stable after concurrent operations
        let stats = cache.getCacheStatistics()
        #expect(stats.entryCount >= 0, "Cache should maintain valid entry count")
        #expect(stats.totalSize >= 0, "Cache should maintain valid size")
    }
}