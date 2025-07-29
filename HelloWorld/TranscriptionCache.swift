import Foundation
import CryptoKit
import os.log

/// High-performance caching system for transcription results to avoid reprocessing
@MainActor
class TranscriptionCache: ObservableObject {
    
    // MARK: - Constants
    
    private static let cacheDirectoryName = "TranscriptionCache"
    private static let maxCacheSize: Int64 = 50 * 1024 * 1024 // 50MB
    private static let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    private static let compressionThreshold = 1024 // 1KB
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.sargeywar.HelloWorld", category: "TranscriptionCache")
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let metadataFile: URL
    
    @Published private(set) var cacheSize: Int64 = 0
    @Published private(set) var cacheEntryCount = 0
    
    private var metadata: CacheMetadata = CacheMetadata()
    private let cacheQueue = DispatchQueue(label: "transcription.cache", qos: .utility, attributes: .concurrent)
    
    // MARK: - Initialization
    
    init() throws {
        // Create cache directory
        let documentsURL = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        cacheDirectory = documentsURL.appendingPathComponent(Self.cacheDirectoryName)
        metadataFile = cacheDirectory.appendingPathComponent("metadata.json")
        
        try createCacheDirectoryIfNeeded()
        
        // Initialize async operations after main initialization
        Task { @MainActor in
            await self.loadMetadata()
            await self.updateCacheStats()
            self.setupCleanupTimer()
            self.logger.info("TranscriptionCache initialized with \(self.cacheEntryCount) entries (\(self.cacheSize) bytes)")
        }
    }
    
    private func createCacheDirectoryIfNeeded() throws {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Cache Key Generation
    
    private func generateCacheKey(for audioURL: URL, with parameters: TranscriptionParameters) -> String {
        let audioData = (try? Data(contentsOf: audioURL, options: .mappedIfSafe)) ?? Data()
        let audioHash = SHA256.hash(data: audioData)
        let parametersData = try? JSONEncoder().encode(parameters)
        let parametersHash = SHA256.hash(data: parametersData ?? Data())
        
        var combinedData = Data()
        combinedData.append(contentsOf: audioHash)
        combinedData.append(contentsOf: parametersHash)
        let combinedHash = SHA256.hash(data: combinedData)
        return combinedHash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Cache Operations
    
    /// Retrieve cached transcription result
    func getCachedTranscription(for audioURL: URL, parameters: TranscriptionParameters) async -> CachedTranscriptionResult? {
        let cacheKey = generateCacheKey(for: audioURL, with: parameters)
        
        // Check metadata on main actor
        guard let entry = metadata.entries[cacheKey] else {
            return nil
        }
        
        // Check if entry is expired
        if Date().timeIntervalSince(entry.lastAccessed) > Self.maxCacheAge {
            await removeEntry(cacheKey: cacheKey)
            return nil
        }
        
        return await withCheckedContinuation { (continuation: CheckedContinuation<CachedTranscriptionResult?, Never>) in
            cacheQueue.async {
                do {
                    let cacheFile = self.cacheDirectory.appendingPathComponent("\(cacheKey).cache")
                    guard self.fileManager.fileExists(atPath: cacheFile.path) else {
                        // Metadata exists but file is missing - clean up
                        Task { @MainActor in
                            await self.removeEntry(cacheKey: cacheKey)
                        }
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    let data = try Data(contentsOf: cacheFile)
                    let decompressedData = entry.isCompressed ? try self.decompress(data) : data
                    let result = try JSONDecoder().decode(CachedTranscriptionResult.self, from: decompressedData)
                    
                    // Update access time
                    Task { @MainActor in
                        await self.updateAccessTime(cacheKey: cacheKey)
                    }
                    
                    self.logger.debug("Cache hit for key: \(cacheKey)")
                    continuation.resume(returning: result)
                    
                } catch {
                    self.logger.error("Failed to read cache entry: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    /// Store transcription result in cache
    func cacheTranscription(
        result: CachedTranscriptionResult,
        for audioURL: URL,
        parameters: TranscriptionParameters
    ) async {
        let cacheKey = generateCacheKey(for: audioURL, with: parameters)
        
        await withCheckedContinuation { continuation in
            cacheQueue.async(flags: .barrier) {
                do {
                    let data = try JSONEncoder().encode(result)
                    let shouldCompress = data.count > Self.compressionThreshold
                    let finalData = shouldCompress ? try self.compress(data) : data
                    
                    let cacheFile = self.cacheDirectory.appendingPathComponent("\(cacheKey).cache")
                    try finalData.write(to: cacheFile)
                    
                    let entry = CacheEntry(
                        key: cacheKey,
                        size: Int64(finalData.count),
                        created: Date(),
                        lastAccessed: Date(),
                        isCompressed: shouldCompress,
                        audioFileSize: self.getFileSize(url: audioURL),
                        parameters: parameters
                    )
                    
                    Task { @MainActor in
                        await self.addEntry(entry)
                        await self.enforceMaxCacheSize()
                    }
                    
                    self.logger.debug("Cached transcription for key: \(cacheKey), size: \(finalData.count) bytes")
                    continuation.resume()
                    
                } catch {
                    self.logger.error("Failed to cache transcription: \(error.localizedDescription)")
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Cache Management
    
    private func addEntry(_ entry: CacheEntry) async {
        metadata.entries[entry.key] = entry
        await updateCacheStats()
        await saveMetadata()
    }
    
    private func removeEntry(cacheKey: String) async {
        guard let entry = metadata.entries[cacheKey] else { return }
        
        let cacheFile = cacheDirectory.appendingPathComponent("\(cacheKey).cache")
        try? fileManager.removeItem(at: cacheFile)
        
        metadata.entries.removeValue(forKey: cacheKey)
        await updateCacheStats()
        await saveMetadata()
        
        logger.debug("Removed cache entry: \(cacheKey)")
    }
    
    private func updateAccessTime(cacheKey: String) async {
        guard var entry = metadata.entries[cacheKey] else { return }
        entry.lastAccessed = Date()
        metadata.entries[cacheKey] = entry
        await saveMetadata()
    }
    
    private func enforceMaxCacheSize() async {
        guard cacheSize > Self.maxCacheSize else { return }
        
        // Sort entries by last accessed time (LRU eviction)
        let sortedEntries = metadata.entries.values.sorted { $0.lastAccessed < $1.lastAccessed }
        
        var currentSize = cacheSize
        var entriesToRemove: [String] = []
        
        for entry in sortedEntries {
            if currentSize <= Self.maxCacheSize * 80 / 100 { // Remove until 80% of max
                break
            }
            entriesToRemove.append(entry.key)
            currentSize -= entry.size
        }
        
        for key in entriesToRemove {
            await removeEntry(cacheKey: key)
        }
        
        if !entriesToRemove.isEmpty {
            logger.info("Evicted \(entriesToRemove.count) cache entries to manage size")
        }
    }
    
    private func updateCacheStats() async {
        cacheSize = metadata.entries.values.reduce(0) { $0 + $1.size }
        cacheEntryCount = metadata.entries.count
    }
    
    // MARK: - Metadata Persistence
    
    private func loadMetadata() async {
        let loadedMetadata = await withCheckedContinuation { continuation in
            cacheQueue.async {
                do {
                    if self.fileManager.fileExists(atPath: self.metadataFile.path) {
                        let data = try Data(contentsOf: self.metadataFile)
                        let metadata = try JSONDecoder().decode(CacheMetadata.self, from: data)
                        continuation.resume(returning: metadata)
                    } else {
                        continuation.resume(returning: CacheMetadata())
                    }
                } catch {
                    self.logger.error("Failed to load cache metadata: \(error.localizedDescription)")
                    continuation.resume(returning: CacheMetadata())
                }
            }
        }
        self.metadata = loadedMetadata
    }
    
    func saveMetadata() async {
        let currentMetadata = self.metadata
        await withCheckedContinuation { continuation in
            cacheQueue.async(flags: .barrier) {
                do {
                    let data = try JSONEncoder().encode(currentMetadata)
                    try data.write(to: self.metadataFile)
                    continuation.resume()
                } catch {
                    self.logger.error("Failed to save cache metadata: \(error.localizedDescription)")
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Compression Utilities
    
    private func compress(_ data: Data) throws -> Data {
        return try (data as NSData).compressed(using: .lzfse) as Data
    }
    
    private func decompress(_ data: Data) throws -> Data {
        return try (data as NSData).decompressed(using: .lzfse) as Data
    }
    
    // MARK: - Cleanup and Maintenance
    
    private func setupCleanupTimer() {
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performMaintenance()
            }
        }
    }
    
    
    func performMaintenance() async {
        logger.debug("Performing cache maintenance")
        
        // Remove expired entries
        let now = Date()
        var expiredKeys: [String] = []
        
        for (key, entry) in metadata.entries {
            if now.timeIntervalSince(entry.lastAccessed) > Self.maxCacheAge {
                expiredKeys.append(key)
            }
        }
        
        for key in expiredKeys {
            await removeEntry(cacheKey: key)
        }
        
        // Enforce size limits
        await enforceMaxCacheSize()
        
        if !expiredKeys.isEmpty {
            logger.info("Cache maintenance: removed \(expiredKeys.count) expired entries")
        }
    }
    
    // MARK: - Public Interface
    
    func clearCache() async {
        try? fileManager.removeItem(at: cacheDirectory)
        try? createCacheDirectoryIfNeeded()
        metadata = CacheMetadata()
        await updateCacheStats()
        logger.info("Cache cleared")
    }
    
    func getCacheStatistics() -> CacheStatistics {
        let totalSize = metadata.entries.values.reduce(0) { $0 + $1.size }
        let oldestEntry = metadata.entries.values.min { $0.created < $1.created }?.created
        let newestEntry = metadata.entries.values.max { $0.created < $1.created }?.created
        
        return CacheStatistics(
            entryCount: metadata.entries.count,
            totalSize: totalSize,
            hitRate: calculateHitRate(),
            oldestEntry: oldestEntry,
            newestEntry: newestEntry
        )
    }
    
    // Add missing clearTemporaryData method
    func clearTemporaryData() async {
        // Clear temporary cache entries older than 1 hour
        let oneHourAgo = Date().addingTimeInterval(-3600)
        var keysToRemove: [String] = []
        
        for (key, entry) in metadata.entries {
            if entry.created < oneHourAgo {
                keysToRemove.append(key)
            }
        }
        
        for key in keysToRemove {
            await removeEntry(cacheKey: key)
        }
    }
    
    private func calculateHitRate() -> Double {
        // This would be enhanced with actual hit/miss tracking
        return 0.75 // Placeholder
    }
    
    private func getFileSize(url: URL) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return 0 }
        return attributes[.size] as? Int64 ?? 0
    }
}

// MARK: - Data Models

struct CachedTranscriptionResult: Codable {
    let text: String
    let confidence: Float
    let processingTime: TimeInterval
    let method: TranscriptionMethod
    let language: String?
    let timestamp: Date
    
    enum TranscriptionMethod: String, Codable {
        case onDevice
        case cloud
        case hybrid
    }
}

struct TranscriptionParameters: Codable, Hashable {
    let language: String?
    let requiresOnlineProcessing: Bool
    let preferredQuality: TranscriptionQuality
    
    enum TranscriptionQuality: String, Codable {
        case fast
        case balanced
        case accurate
    }
}

private struct CacheMetadata: Codable {
    var entries: [String: CacheEntry] = [:]
    var version: Int = 1
}

private struct CacheEntry: Codable {
    let key: String
    let size: Int64
    let created: Date
    var lastAccessed: Date
    let isCompressed: Bool
    let audioFileSize: Int64
    let parameters: TranscriptionParameters
}

struct CacheStatistics {
    let entryCount: Int
    let totalSize: Int64
    let hitRate: Double
    let oldestEntry: Date?
    let newestEntry: Date?
}