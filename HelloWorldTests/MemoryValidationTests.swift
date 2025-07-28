import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import HelloWorld

/// Memory validation tests for transcription system components
struct MemoryValidationTests {
    
    // MARK: - Test Constants
    
    private static let memoryLeakThreshold: Double = 5.0 // 5MB
    private static let maxMemoryIncrease: Double = 20.0 // 20MB
    private static let stabilizationDelay: UInt64 = 500_000_000 // 500ms
    
    // MARK: - Memory Measurement Utilities
    
    private func measureMemory<T>(
        operation: () async throws -> T,
        description: String
    ) async throws -> (result: T, memoryDelta: Double) {
        
        // Force garbage collection before measurement
        await forceGarbageCollection()
        let initialMemory = getCurrentMemoryUsage()
        
        // Execute operation
        let result = try await operation()
        
        // Allow memory to stabilize
        await Task.sleep(nanoseconds: Self.stabilizationDelay)
        await forceGarbageCollection()
        
        let finalMemory = getCurrentMemoryUsage()
        let memoryDelta = finalMemory - initialMemory
        
        print("Memory measurement for \(description): \(String(format: "%.2f", memoryDelta))MB")
        
        return (result: result, memoryDelta: memoryDelta)
    }
    
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
    
    private func forceGarbageCollection() async {
        // Force autoreleasepool drain and give system time to clean up
        await Task.yield()
        autoreleasepool {
            // Empty pool to force cleanup
        }
        await Task.sleep(nanoseconds: 50_000_000) // 50ms
    }
    
    private func createTestAudioFile(sizeInKB: Int) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("memory_test_\(UUID().uuidString).m4a")
        
        let data = Data(repeating: 0, count: sizeInKB * 1024)
        try data.write(to: tempURL)
        
        return tempURL
    }
    
    private func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
    // MARK: - Audio Memory Manager Validation
    
    @Test func testAudioMemoryManagerNoLeaks() async throws {
        let (_, memoryDelta) = try await measureMemory(
            operation: {
                let manager = AudioMemoryManager()
                let testFile = try createTestAudioFile(sizeInKB: 500) // 500KB
                defer { cleanup(url: testFile) }
                
                // Process file multiple times
                for _ in 0..<5 {
                    try await manager.processAudioFile(at: testFile) { data, chunkIndex, totalChunks in
                        // Simulate processing
                        await Task.yield()
                    }
                }
                
                return manager
            },
            description: "AudioMemoryManager multiple processing cycles"
        )
        
        #expect(memoryDelta < Self.memoryLeakThreshold, 
               "AudioMemoryManager should not leak memory: \(memoryDelta)MB increase")
    }
    
    @Test func testAudioMemoryManagerCacheCleanup() async throws {
        let (manager, initialDelta) = try await measureMemory(
            operation: {
                let manager = AudioMemoryManager()
                
                // Fill cache with data
                for i in 0..<10 {
                    let testData = Data(repeating: UInt8(i), count: 1024 * 100) // 100KB each
                    manager.cacheAudioData(testData, forKey: "test_key_\(i)")
                }
                
                return manager
            },
            description: "AudioMemoryManager cache filling"
        )
        
        // Now clear the cache and measure memory reduction
        let (_, cleanupDelta) = try await measureMemory(
            operation: {
                manager.clearAll()
                return ()
            },
            description: "AudioMemoryManager cache cleanup"
        )
        
        #expect(initialDelta > 0, "Cache filling should increase memory")
        #expect(cleanupDelta <= 0, "Cache cleanup should not increase memory")
    }
    
    @Test func testAudioFormatConversionMemoryUsage() async throws {
        let (_, memoryDelta) = try await measureMemory(
            operation: {
                let manager = AudioMemoryManager()
                let testFile = try createTestAudioFile(sizeInKB: 1000) // 1MB
                defer { cleanup(url: testFile) }
                
                // This would test format conversion if we had proper audio format setup
                // For now, test the memory management during file processing
                try await manager.processAudioFile(at: testFile) { data, chunkIndex, totalChunks in
                    // Simulate format conversion work
                    let processedData = data.map { $0 ^ 0xFF } // Simple transformation
                    _ = processedData // Use the data
                    await Task.yield()
                }
                
                return manager
            },
            description: "Audio format conversion memory usage"
        )
        
        #expect(memoryDelta < Self.maxMemoryIncrease, 
               "Format conversion should not use excessive memory: \(memoryDelta)MB")
    }
    
    // MARK: - Transcription Cache Validation
    
    @Test func testTranscriptionCacheMemoryBounds() async throws {
        let (cache, memoryDelta) = try await measureMemory(
            operation: {
                let cache = try TranscriptionCache()
                let parameters = TranscriptionParameters(
                    language: "en-US",
                    requiresOnlineProcessing: false,
                    preferredQuality: .balanced
                )
                
                // Add many cache entries
                for i in 0..<50 {
                    let testURL = try createTestAudioFile(sizeInKB: 100)
                    defer { cleanup(url: testURL) }
                    
                    let result = CachedTranscriptionResult(
                        text: String(repeating: "Test transcription text ", count: 100), // ~2KB text
                        confidence: 0.9,
                        processingTime: 1.0,
                        method: .onDevice,
                        language: "en-US",
                        timestamp: Date()
                    )
                    
                    await cache.cacheTranscription(result: result, for: testURL, parameters: parameters)
                }
                
                return cache
            },
            description: "TranscriptionCache with 50 entries"
        )
        
        // Cache should enforce size limits and not grow unbounded
        let stats = cache.getCacheStatistics()
        #expect(memoryDelta < 30.0, "Cache should limit memory usage: \(memoryDelta)MB")
        #expect(stats.totalSize > 0, "Cache should contain data")
    }
    
    @Test func testCacheEvictionEffectiveness() async throws {
        let cache = try TranscriptionCache()
        
        // Fill cache beyond typical limits
        let (_, fillMemoryDelta) = try await measureMemory(
            operation: {
                let parameters = TranscriptionParameters(
                    language: "en-US",
                    requiresOnlineProcessing: false,
                    preferredQuality: .balanced
                )
                
                for i in 0..<100 {
                    let testURL = try createTestAudioFile(sizeInKB: 50)
                    defer { cleanup(url: testURL) }
                    
                    let result = CachedTranscriptionResult(
                        text: String(repeating: "Large transcription text for memory test ", count: 50),
                        confidence: 0.9,
                        processingTime: 1.0,
                        method: .onDevice,
                        language: "en-US",
                        timestamp: Date(timeIntervalSinceNow: -Double(i * 60)) // Older entries
                    )
                    
                    await cache.cacheTranscription(result: result, for: testURL, parameters: parameters)
                }
                return ()
            },
            description: "Cache overfilling"
        )
        
        // Force cache maintenance/cleanup
        let (_, cleanupMemoryDelta) = try await measureMemory(
            operation: {
                await cache.performMaintenance()
                return ()
            },
            description: "Cache maintenance"
        )
        
        let finalStats = cache.getCacheStatistics()
        
        #expect(fillMemoryDelta > 0, "Filling cache should increase memory")
        #expect(finalStats.entryCount < 100, "Cache should evict old entries")
        #expect(cleanupMemoryDelta <= 0, "Maintenance should not increase memory")
    }
    
    // MARK: - UI Thread Optimizer Validation
    
    @Test func testUIThreadOptimizerMemoryEfficiency() async throws {
        let (_, memoryDelta) = try await measureMemory(
            operation: {
                let optimizer = UIThreadOptimizer()
                
                // Schedule many UI updates
                for i in 0..<1000 {
                    await optimizer.scheduleUpdate(
                        UIUpdateOperation(
                            priority: .medium,
                            estimatedDuration: 0.001
                        ) {
                            // Simulate UI work that could create temporary objects
                            let temporaryData = Array(0..<100).map { "Item \($0 + i)" }
                            _ = temporaryData.joined(separator: ", ")
                        }
                    )
                }
                
                // Allow all updates to complete
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                return optimizer
            },
            description: "UIThreadOptimizer with 1000 updates"
        )
        
        #expect(memoryDelta < Self.maxMemoryIncrease, 
               "UI optimizer should not accumulate memory: \(memoryDelta)MB")
    }
    
    @Test func testBackgroundWorkMemoryIsolation() async throws {
        let (_, memoryDelta) = try await measureMemory(
            operation: {
                let optimizer = UIThreadOptimizer()
                
                // Execute multiple background tasks that could leak memory
                await withTaskGroup(of: Void.self) { group in
                    for i in 0..<10 {
                        group.addTask {
                            await withCheckedContinuation { continuation in
                                optimizer.executeOnBackground(
                                    work: {
                                        // Simulate memory-intensive work
                                        let largeArray = Array(0..<10000).map { "Background item \($0 + i)" }
                                        return largeArray.count
                                    },
                                    completion: { result in
                                        continuation.resume()
                                    }
                                )
                            }
                        }
                    }
                }
                
                return optimizer
            },
            description: "Background work memory isolation"
        )
        
        #expect(memoryDelta < Self.memoryLeakThreshold, 
               "Background work should not leak to main thread: \(memoryDelta)MB")
    }
    
    // MARK: - Performance Monitor Validation
    
    @Test func testPerformanceMonitorDataManagement() async throws {
        let (monitor, memoryDelta) = try await measureMemory(
            operation: {
                let monitor = TranscriptionPerformanceMonitor()
                monitor.startMonitoring()
                
                // Generate lots of performance data
                for i in 0..<200 {
                    let operationId = UUID()
                    monitor.startTrackingOperation(
                        id: operationId,
                        type: .automatic,
                        audioFileSize: Int64(1024 * i),
                        priority: .normal
                    )
                    
                    // Simulate operation progress
                    monitor.updateOperationProgress(id: operationId, progress: 0.5, currentPhase: "Processing")
                    monitor.completeOperation(id: operationId, success: true, resultSize: 512)
                }
                
                // Multiple queue sessions
                for _ in 0..<20 {
                    monitor.startQueueProcessingSession()
                    monitor.endQueueProcessingSession(totalItemsProcessed: 10, remainingItems: 0)
                }
                
                monitor.stopMonitoring()
                return monitor
            },
            description: "PerformanceMonitor with extensive data"
        )
        
        #expect(memoryDelta < Self.maxMemoryIncrease, 
               "Performance monitor should manage data size: \(memoryDelta)MB")
        
        // Verify data bounds
        let metrics = monitor.currentMetrics
        #expect(metrics.totalItemsProcessed >= 0, "Metrics should be valid")
    }
    
    // MARK: - Background Task Manager Validation
    
    @Test func testBackgroundTaskManagerCleanup() async throws {
        let (_, memoryDelta) = try await measureMemory(
            operation: {
                let backgroundManager = BackgroundTaskManager()
                
                // Schedule and cancel many background tasks
                for _ in 0..<50 {
                    backgroundManager.scheduleBackgroundProcessing()
                    backgroundManager.scheduleBackgroundRefresh()
                }
                
                // Disable and cleanup
                backgroundManager.disableBackgroundProcessing()
                
                return backgroundManager
            },
            description: "BackgroundTaskManager cleanup"
        )
        
        #expect(memoryDelta < Self.memoryLeakThreshold, 
               "Background task manager should cleanup properly: \(memoryDelta)MB")
    }
    
    // MARK: - App Lifecycle Handler Validation
    
    @Test func testAppLifecycleHandlerMemoryManagement() async throws {
        let (_, memoryDelta) = try await measureMemory(
            operation: {
                let lifecycleHandler = AppLifecycleHandler()
                
                // Simulate app lifecycle events
                for _ in 0..<10 {
                    // Simulate background/foreground cycles
                    #if canImport(UIKit)
                    NotificationCenter.default.post(
                        name: UIApplication.didEnterBackgroundNotification,
                        object: nil
                    )
                    
                    await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    
                    NotificationCenter.default.post(
                        name: UIApplication.willEnterForegroundNotification,
                        object: nil
                    )
                    #endif
                    
                    await Task.sleep(nanoseconds: 100_000_000) // 100ms
                }
                
                return lifecycleHandler
            },
            description: "AppLifecycleHandler event cycles"
        )
        
        #expect(memoryDelta < Self.memoryLeakThreshold, 
               "Lifecycle handler should not leak during state changes: \(memoryDelta)MB")
    }
    
    // MARK: - Integration Memory Tests
    
    @Test func testIntegratedSystemMemoryBehavior() async throws {
        let (_, memoryDelta) = try await measureMemory(
            operation: {
                // Initialize all major components
                let memoryManager = AudioMemoryManager()
                let cache = try TranscriptionCache()
                let uiOptimizer = UIThreadOptimizer()
                let performanceMonitor = TranscriptionPerformanceMonitor()
                let backgroundManager = BackgroundTaskManager()
                let lifecycleHandler = AppLifecycleHandler()
                
                // Simulate integrated workflow
                let testFile = try createTestAudioFile(sizeInKB: 500)
                defer { cleanup(url: testFile) }
                
                // Process audio
                try await memoryManager.processAudioFile(at: testFile) { data, chunkIndex, totalChunks in
                    // Simulate transcription processing
                    let operationId = UUID()
                    performanceMonitor.startTrackingOperation(
                        id: operationId,
                        type: .automatic,
                        audioFileSize: Int64(data.count),
                        priority: .normal
                    )
                    
                    await Task.yield()
                    performanceMonitor.completeOperation(id: operationId, success: true)
                }
                
                // Cache results
                let parameters = TranscriptionParameters(
                    language: "en-US",
                    requiresOnlineProcessing: false,
                    preferredQuality: .balanced
                )
                
                let result = CachedTranscriptionResult(
                    text: "Integrated test transcription",
                    confidence: 0.9,
                    processingTime: 1.0,
                    method: .onDevice,
                    language: "en-US",
                    timestamp: Date()
                )
                
                await cache.cacheTranscription(result: result, for: testFile, parameters: parameters)
                
                // Simulate UI updates
                for _ in 0..<20 {
                    await uiOptimizer.scheduleUpdate(UIUpdateOperation {
                        await Task.yield()
                    })
                }
                
                return (memoryManager, cache, uiOptimizer, performanceMonitor, backgroundManager, lifecycleHandler)
            },
            description: "Integrated system workflow"
        )
        
        #expect(memoryDelta < 50.0, 
               "Integrated system should maintain reasonable memory usage: \(memoryDelta)MB")
    }
    
    // MARK: - Stress Test Memory Validation
    
    @Test func testMemoryUnderStress() async throws {
        let (_, memoryDelta) = try await measureMemory(
            operation: {
                let memoryManager = AudioMemoryManager()
                
                // Create multiple concurrent operations
                await withTaskGroup(of: Void.self) { group in
                    for i in 0..<20 {
                        group.addTask {
                            do {
                                let testFile = try self.createTestAudioFile(sizeInKB: 200)
                                defer { self.cleanup(url: testFile) }
                                
                                try await memoryManager.processAudioFile(at: testFile) { data, chunkIndex, totalChunks in
                                    // Simulate processing with temporary allocations
                                    let processedData = data.map { byte in
                                        String(format: "%02x", byte)
                                    }
                                    _ = processedData.joined() // Use the data
                                    await Task.yield()
                                }
                            } catch {
                                // Handle errors in stress test
                            }
                        }
                    }
                }
                
                return memoryManager
            },
            description: "Memory stress test with 20 concurrent operations"
        )
        
        #expect(memoryDelta < 100.0, 
               "System should handle stress without excessive memory growth: \(memoryDelta)MB")
    }
    
    // MARK: - Memory Recovery Tests
    
    @Test func testMemoryRecoveryAfterWarning() async throws {
        // Measure memory before simulating warning
        await forceGarbageCollection()
        let beforeWarningMemory = getCurrentMemoryUsage()
        
        // Create components and fill them with data
        let memoryManager = AudioMemoryManager()
        let cache = try TranscriptionCache()
        
        // Fill with test data
        for i in 0..<20 {
            let testData = Data(repeating: UInt8(i), count: 1024 * 50) // 50KB each
            memoryManager.cacheAudioData(testData, forKey: "stress_key_\(i)")
        }
        
        let afterFillingMemory = getCurrentMemoryUsage()
        
        // Simulate memory warning
        NotificationCenter.default.post(
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        // Allow cleanup to occur
        await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        await forceGarbageCollection()
        
        let afterWarningMemory = getCurrentMemoryUsage()
        
        #expect(afterFillingMemory > beforeWarningMemory, "Memory should increase when filling caches")
        #expect(afterWarningMemory < afterFillingMemory, "Memory should decrease after warning cleanup")
        
        let recoveryRatio = (afterFillingMemory - afterWarningMemory) / (afterFillingMemory - beforeWarningMemory)
        #expect(recoveryRatio > 0.3, "Should recover at least 30% of allocated memory")
    }
}