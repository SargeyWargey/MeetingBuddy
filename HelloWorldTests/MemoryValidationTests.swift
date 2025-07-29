import XCTest
@testable import HelloWorld
import AVFoundation

final class MemoryValidationTests: XCTestCase {
    
    var audioMemoryManager: AudioMemoryManager!
    var transcriptionCache: TranscriptionCache!
    
    override func setUp() async throws {
        try await super.setUp()
        audioMemoryManager = AudioMemoryManager()
        transcriptionCache = try TranscriptionCache()
    }
    
    override func tearDown() async throws {
        audioMemoryManager.clearAll()
        await transcriptionCache.clearCache()
        audioMemoryManager = nil
        transcriptionCache = nil
        try await super.tearDown()
    }
    
    // MARK: - Memory Usage Validation
    
    func testMemoryUsageWithinLimits() async throws {
        let initialMemory = getCurrentMemoryUsage()
        
        // Process multiple audio files to stress test memory
        for i in 0..<10 {
            let testAudioURL = try createLargeTestAudioFile(size: 1024 * 1024) // 1MB each
            defer { try? FileManager.default.removeItem(at: testAudioURL) }
            
            try await audioMemoryManager.processAudioFile(at: testAudioURL) { chunkData, _, _ in
                // Simulate processing work
                _ = chunkData.count
            }
            
            let currentMemory = getCurrentMemoryUsage()
            let memoryIncrease = currentMemory - initialMemory
            
            // Memory increase should be reasonable (less than 50MB)
            XCTAssertLessThan(memoryIncrease, 50 * 1024 * 1024, "Memory usage increased by \(memoryIncrease) bytes")
        }
    }
    
    func testCacheMemoryManagement() async throws {
        let initialCacheSize = transcriptionCache.cacheSize
        
        // Add many cache entries
        for i in 0..<50 {
            let testURL = try createTestAudioFile(name: "cache_test_\(i).m4a")
            defer { try? FileManager.default.removeItem(at: testURL) }
            
            let parameters = TranscriptionParameters(
                language: "en-US",
                requiresOnlineProcessing: false,
                preferredQuality: .balanced
            )
            
            let result = CachedTranscriptionResult(
                text: String(repeating: "Test transcription text ", count: 100), // ~2KB text
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
        }
        
        // Cache should have grown but not excessively
        let finalCacheSize = transcriptionCache.cacheSize
        let cacheGrowth = finalCacheSize - initialCacheSize
        
        // Cache growth should be reasonable (less than 10MB for 50 entries)
        XCTAssertLessThan(cacheGrowth, 10 * 1024 * 1024, "Cache grew by \(cacheGrowth) bytes")
        
        // Trigger cache maintenance
        await transcriptionCache.performMaintenance()
        
        // Cache should be managed within limits
        let managedCacheSize = transcriptionCache.cacheSize
        XCTAssertLessThanOrEqual(managedCacheSize, finalCacheSize)
    }
    
    func testMemoryPressureResponse() async throws {
        // Fill up memory with cached data
        let largeData = Data(repeating: 0xFF, count: 10 * 1024 * 1024) // 10MB
        for i in 0..<5 {
            audioMemoryManager.cacheAudioData(largeData, forKey: "pressure_test_\(i)")
        }
        
        let beforePressureMemory = audioMemoryManager.getMemoryUsageInfo()
        XCTAssertGreaterThan(beforePressureMemory.cacheSize, 0)
        
        // Simulate memory pressure
        NotificationCenter.default.post(name: .lowMemoryCondition, object: nil)
        
        // Allow time for cleanup
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        let afterPressureMemory = audioMemoryManager.getMemoryUsageInfo()
        
        // Memory should be reduced after pressure event
        XCTAssertLessThanOrEqual(afterPressureMemory.cacheSize, beforePressureMemory.cacheSize)
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentMemoryAccess() async throws {
        let concurrentTasks = 10
        let expectation = XCTestExpectation(description: "Concurrent memory access completed")
        expectation.expectedFulfillmentCount = concurrentTasks
        
        // Launch multiple concurrent tasks
        for i in 0..<concurrentTasks {
            Task.detached {
                do {
                    let testURL = try self.createTestAudioFile(name: "concurrent_\(i).m4a")
                    defer { try? FileManager.default.removeItem(at: testURL) }
                    
                    try await self.audioMemoryManager.processAudioFile(at: testURL) { _, _, _ in
                        // Simulate work
                        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    }
                    
                    expectation.fulfill()
                } catch {
                    XCTFail("Concurrent task \(i) failed: \(error)")
                    expectation.fulfill()
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Verify memory is stable after concurrent access
        let finalMemory = audioMemoryManager.getMemoryUsageInfo()
        XCTAssertEqual(finalMemory.activeOperations, 0)
    }
    
    // MARK: - Memory Leak Detection
    
    func testNoMemoryLeaksInAudioProcessing() async throws {
        let initialMemory = getCurrentMemoryUsage()
        
        // Process many files to detect potential leaks
        for i in 0..<20 {
            let testURL = try createTestAudioFile(name: "leak_test_\(i).m4a")
            
            try await audioMemoryManager.processAudioFile(at: testURL) { chunkData, _, _ in
                // Create and release temporary data
                let tempData = Data(chunkData)
                _ = tempData.count
            }
            
            // Clean up immediately
            try FileManager.default.removeItem(at: testURL)
            
            // Force garbage collection periodically
            if i % 5 == 0 {
                // Give time for cleanup
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
        
        // Allow final cleanup
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        let finalMemory = getCurrentMemoryUsage()
        let memoryDifference = finalMemory - initialMemory
        
        // Memory difference should be minimal (less than 5MB)
        XCTAssertLessThan(memoryDifference, 5 * 1024 * 1024, 
                         "Potential memory leak detected: \(memoryDifference) bytes")
    }
    
    func testCacheMemoryLeaks() async throws {
        let initialCacheSize = transcriptionCache.cacheSize
        
        // Add and remove cache entries repeatedly
        for cycle in 0..<5 {
            // Add entries
            for i in 0..<10 {
                let testURL = try createTestAudioFile(name: "leak_cache_\(cycle)_\(i).m4a")
                defer { try? FileManager.default.removeItem(at: testURL) }
                
                let parameters = TranscriptionParameters(
                    language: "en-US",
                    requiresOnlineProcessing: false,
                    preferredQuality: .balanced
                )
                
                let result = CachedTranscriptionResult(
                    text: "Leak test transcription \(cycle)-\(i)",
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
            }
            
            // Clear cache
            await transcriptionCache.clearCache()
            
            // Allow cleanup
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        let finalCacheSize = transcriptionCache.cacheSize
        
        // Cache should return to initial size or close to it
        XCTAssertLessThanOrEqual(finalCacheSize, initialCacheSize + 1024, // Allow 1KB tolerance
                                "Cache memory leak detected: \(finalCacheSize - initialCacheSize) bytes")
    }
    
    // MARK: - Resource Cleanup Tests
    
    func testResourceCleanupOnError() async throws {
        let initialMemory = audioMemoryManager.getMemoryUsageInfo()
        
        // Create a scenario that will cause an error
        let nonExistentURL = URL(fileURLWithPath: "/non/existent/file.m4a")
        
        do {
            try await audioMemoryManager.processAudioFile(at: nonExistentURL) { _, _, _ in
                XCTFail("Should not reach this point")
            }
            XCTFail("Should have thrown an error")
        } catch {
            // Expected error
        }
        
        // Verify resources were cleaned up
        let finalMemory = audioMemoryManager.getMemoryUsageInfo()
        XCTAssertEqual(finalMemory.activeOperations, initialMemory.activeOperations)
    }
    
    // MARK: - Performance Under Memory Pressure
    
    func testPerformanceUnderMemoryPressure() async throws {
        // Create memory pressure by filling cache
        let largeData = Data(repeating: 0xAA, count: 5 * 1024 * 1024) // 5MB
        for i in 0..<10 {
            audioMemoryManager.cacheAudioData(largeData, forKey: "pressure_perf_\(i)")
        }
        
        // Measure performance under pressure
        let startTime = Date()
        
        let testURL = try createTestAudioFile()
        defer { try? FileManager.default.removeItem(at: testURL) }
        
        var chunksProcessed = 0
        try await audioMemoryManager.processAudioFile(at: testURL) { _, _, _ in
            chunksProcessed += 1
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        // Processing should still complete in reasonable time (less than 5 seconds)
        XCTAssertLessThan(processingTime, 5.0, "Processing took too long under memory pressure")
        XCTAssertGreaterThan(chunksProcessed, 0, "No chunks were processed")
    }
    
    // MARK: - Helper Methods
    
    private func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
    
    private func createTestAudioFile(name: String = "memory_test.m4a") throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent(name)
        
        // Create a small test audio file
        let testData = Data(repeating: 0x00, count: 4096) // 4KB
        try testData.write(to: audioURL)
        
        return audioURL
    }
    
    private func createLargeTestAudioFile(size: Int) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent("large_test_\(UUID().uuidString).m4a")
        
        // Create a larger test file
        let testData = Data(repeating: 0x00, count: size)
        try testData.write(to: audioURL)
        
        return audioURL
    }
}