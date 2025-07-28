import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif
import os.log

/// Manages memory optimization for audio file processing during transcription
class AudioMemoryManager {
    
    // MARK: - Constants
    
    private static let maxChunkSize: Int = 1024 * 1024 // 1MB chunks
    private static let maxConcurrentOperations = 2
    private static let memoryWarningThreshold: Int = 50 * 1024 * 1024 // 50MB
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.sargeywar.HelloWorld", category: "AudioMemoryManager")
    private let processingQueue = DispatchQueue(label: "audio.memory.processing", qos: .utility)
    private let semaphore = DispatchSemaphore(value: maxConcurrentOperations)
    
    private var activeOperations: Set<UUID> = []
    private var memoryCache: [String: CachedAudioData] = [:]
    private let cacheQueue = DispatchQueue(label: "audio.memory.cache", attributes: .concurrent)
    
    // MARK: - Memory Monitoring
    
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    init() {
        setupMemoryPressureMonitoring()
        setupMemoryWarningNotifications()
    }
    
    private func setupMemoryPressureMonitoring() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])
        memoryPressureSource?.setEventHandler { [weak self] in
            self?.handleMemoryPressure()
        }
        memoryPressureSource?.resume()
    }
    
    private func setupMemoryWarningNotifications() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        #else
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: .lowMemoryCondition,
            object: nil
        )
        #endif
    }
    
    @objc private func handleMemoryWarning() {
        logger.warning("Received memory warning - clearing audio cache")
        clearMemoryCache()
    }
    
    private func handleMemoryPressure() {
        logger.warning("Memory pressure detected - aggressive cache cleanup")
        clearMemoryCache()
        // Cancel non-critical audio operations
        cancelLowPriorityOperations()
    }
    
    // MARK: - Audio Processing with Memory Management
    
    /// Process audio file with memory-efficient streaming
    func processAudioFile(
        at url: URL,
        operationId: UUID = UUID(),
        chunkProcessor: @escaping (Data, Int, Int) async throws -> Void
    ) async throws {
        
        logger.info("Starting memory-managed audio processing for file: \(url.lastPathComponent)")
        
        // Check memory availability before starting
        try checkMemoryAvailability()
        
        // Acquire semaphore to limit concurrent operations
        await withCheckedContinuation { continuation in
            processingQueue.async {
                self.semaphore.wait()
                self.activeOperations.insert(operationId)
                continuation.resume()
            }
        }
        
        defer {
            activeOperations.remove(operationId)
            semaphore.signal()
        }
        
        do {
            let fileSize = try getFileSize(url: url)
            let chunkSize = min(Self.maxChunkSize, fileSize)
            
            logger.debug("Processing file size: \(fileSize) bytes in chunks of \(chunkSize) bytes")
            
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { fileHandle.closeFile() }
            
            var offset = 0
            var chunkIndex = 0
            let totalChunks = (fileSize + chunkSize - 1) / chunkSize
            
            while offset < fileSize {
                // Check for memory pressure during processing
                try checkMemoryAvailability()
                
                // Check if operation was cancelled
                guard activeOperations.contains(operationId) else {
                    throw AudioMemoryError.operationCancelled
                }
                
                let remainingBytes = fileSize - offset
                let currentChunkSize = min(chunkSize, remainingBytes)
                
                fileHandle.seek(toFileOffset: UInt64(offset))
                let chunkData = fileHandle.readData(ofLength: currentChunkSize)
                
                if chunkData.isEmpty {
                    break
                }
                
                // Process chunk with proper error handling
                try await chunkProcessor(chunkData, chunkIndex, totalChunks)
                
                offset += currentChunkSize
                chunkIndex += 1
                
                // Yield control to prevent blocking
                await Task.yield()
            }
            
            logger.info("Successfully processed audio file in \(chunkIndex) chunks")
            
        } catch {
            logger.error("Audio processing failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Audio Format Conversion with Memory Management
    
    /// Convert audio format with memory optimization
    func convertAudioFormat(
        inputURL: URL,
        outputFormat: AVAudioFormat,
        operationId: UUID = UUID()
    ) async throws -> Data {
        
        logger.info("Starting memory-managed audio format conversion")
        
        try checkMemoryAvailability()
        
        let audioFile = try AVAudioFile(forReading: inputURL)
        let inputFormat = audioFile.processingFormat
        
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioMemoryError.conversionFailed
        }
        
        let frameCapacity = AVAudioFrameCount(1024) // Small buffer for memory efficiency
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCapacity),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
            throw AudioMemoryError.bufferAllocationFailed
        }
        
        var convertedData = Data()
        var isComplete = false
        
        while !isComplete {
            // Check memory pressure during conversion
            try checkMemoryAvailability()
            
            // Read input chunk
            try audioFile.read(into: inputBuffer)
            
            if inputBuffer.frameLength == 0 {
                isComplete = true
                break
            }
            
            // Convert chunk
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return inputBuffer
            }
            
            if status == .error {
                throw error ?? AudioMemoryError.conversionFailed
            }
            
            // Append converted data
            if let channelData = outputBuffer.floatChannelData?[0] {
                let data = Data(bytes: channelData, count: Int(outputBuffer.frameLength) * MemoryLayout<Float>.size)
                convertedData.append(data)
            }
            
            // Reset buffers for next iteration
            inputBuffer.frameLength = 0
            outputBuffer.frameLength = 0
            
            await Task.yield()
        }
        
        logger.info("Audio format conversion completed, output size: \(convertedData.count) bytes")
        return convertedData
    }
    
    // MARK: - Memory Cache Management
    
    private struct CachedAudioData {
        let data: Data
        let timestamp: Date
        let accessCount: Int
        
        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 300 // 5 minutes
        }
    }
    
    func cacheAudioData(_ data: Data, forKey key: String) {
        cacheQueue.async(flags: .barrier) {
            self.memoryCache[key] = CachedAudioData(
                data: data,
                timestamp: Date(),
                accessCount: 1
            )
            
            // Clean up expired entries
            self.cleanExpiredCacheEntries()
        }
    }
    
    func getCachedAudioData(forKey key: String) -> Data? {
        return cacheQueue.sync {
            guard var cachedData = memoryCache[key], !cachedData.isExpired else {
                memoryCache.removeValue(forKey: key)
                return nil
            }
            
            // Update access count
            cachedData = CachedAudioData(
                data: cachedData.data,
                timestamp: cachedData.timestamp,
                accessCount: cachedData.accessCount + 1
            )
            memoryCache[key] = cachedData
            
            return cachedData.data
        }
    }
    
    private func cleanExpiredCacheEntries() {
        let expiredKeys = memoryCache.compactMap { key, value in
            value.isExpired ? key : nil
        }
        
        for key in expiredKeys {
            memoryCache.removeValue(forKey: key)
        }
        
        logger.debug("Cleaned \(expiredKeys.count) expired cache entries")
    }
    
    private func clearMemoryCache() {
        cacheQueue.async(flags: .barrier) {
            let clearedCount = self.memoryCache.count
            self.memoryCache.removeAll()
            self.logger.info("Cleared memory cache (\(clearedCount) entries)")
        }
    }
    
    // MARK: - Memory Monitoring Utilities
    
    private func checkMemoryAvailability() throws {
        var memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let memoryUsage = Int(memoryInfo.resident_size)
            if memoryUsage > Self.memoryWarningThreshold {
                logger.warning("High memory usage detected: \(memoryUsage) bytes")
                throw AudioMemoryError.memoryPressure
            }
        }
    }
    
    private func getFileSize(url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int ?? 0
    }
    
    private func cancelLowPriorityOperations() {
        // Remove half of active operations (keeping most recent)
        let operationsToCancel = Array(activeOperations.prefix(activeOperations.count / 2))
        for operationId in operationsToCancel {
            activeOperations.remove(operationId)
        }
        logger.info("Cancelled \(operationsToCancel.count) low-priority operations due to memory pressure")
    }
    
    // MARK: - Public Interface
    
    func getMemoryUsageInfo() -> (cacheSize: Int, activeOperations: Int) {
        let cacheSize = cacheQueue.sync {
            memoryCache.values.reduce(0) { $0 + $1.data.count }
        }
        return (cacheSize: cacheSize, activeOperations: activeOperations.count)
    }
    
    func clearAll() {
        clearMemoryCache()
        activeOperations.removeAll()
    }
    
    deinit {
        memoryPressureSource?.cancel()
        NotificationCenter.default.removeObserver(self)
        clearAll()
    }
}

// MARK: - Audio Memory Error Types

enum AudioMemoryError: LocalizedError {
    case memoryPressure
    case operationCancelled
    case conversionFailed
    case bufferAllocationFailed
    case fileReadError
    
    var errorDescription: String? {
        switch self {
        case .memoryPressure:
            return "Insufficient memory available for audio processing"
        case .operationCancelled:
            return "Audio processing operation was cancelled"
        case .conversionFailed:
            return "Audio format conversion failed"
        case .bufferAllocationFailed:
            return "Failed to allocate audio buffer"
        case .fileReadError:
            return "Failed to read audio file"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .memoryPressure:
            return "Close other apps and try again"
        case .operationCancelled:
            return "Restart the transcription process"
        case .conversionFailed:
            return "Check audio file format and try again"
        case .bufferAllocationFailed:
            return "Restart the app and try again"
        case .fileReadError:
            return "Ensure the audio file exists and is accessible"
        }
    }
}