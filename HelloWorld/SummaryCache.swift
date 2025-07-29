import Foundation

// MARK: - Summary Cache

class SummaryCache {
    
    // MARK: - Constants
    
    private let maxCacheSize: Int = 100 * 1024 * 1024 // 100 MB
    private let maxAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    private let cacheDirectoryName = "SummaryCache"
    
    // MARK: - Properties
    
    private let cacheDirectory: URL
    private let metadataFile: URL
    private var metadata: CacheMetadata
    private let queue = DispatchQueue(label: "SummaryCache", qos: .utility)
    
    // MARK: - Initialization
    
    init() {
        // Create cache directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.cacheDirectory = documentsPath.appendingPathComponent(cacheDirectoryName)
        self.metadataFile = cacheDirectory.appendingPathComponent("metadata.json")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Load metadata
        self.metadata = Self.loadMetadata(from: metadataFile)
        
        // Perform initial cleanup
        Task {
            await cleanup()
        }
    }
    
    // MARK: - Public Methods
    
    /// Stores a summary in the cache
    func store(_ summary: Summary) throws {
        try queue.sync {
            let cacheKey = generateCacheKey(
                recordingId: summary.recordingId,
                type: summary.type,
                length: summary.length
            )
            
            let summaryFile = cacheDirectory.appendingPathComponent("\(cacheKey).json")
            
            // Encode and write summary
            let data = try JSONEncoder().encode(summary)
            try data.write(to: summaryFile)
            
            // Update metadata
            let entry = CacheEntry(
                key: cacheKey,
                recordingId: summary.recordingId,
                type: summary.type,
                length: summary.length,
                createdAt: Date(),
                fileSize: data.count,
                lastAccessed: Date()
            )
            
            metadata.entries[cacheKey] = entry
            metadata.totalSize += data.count
            
            // Save metadata
            try saveMetadata()
            
            // Cleanup if needed
            Task {
                await cleanupIfNeeded()
            }
        }
    }
    
    /// Retrieves a summary from the cache
    func retrieve(for recordingId: UUID, type: SummaryType, length: SummaryLength) -> Summary? {
        return queue.sync {
            let cacheKey = generateCacheKey(recordingId: recordingId, type: type, length: length)
            
            guard let entry = metadata.entries[cacheKey] else {
                return nil
            }
            
            // Check if entry is expired
            if Date().timeIntervalSince(entry.createdAt) > maxAge {
                // Remove expired entry
                removeEntry(for: cacheKey)
                return nil
            }
            
            let summaryFile = cacheDirectory.appendingPathComponent("\(cacheKey).json")
            
            guard let data = try? Data(contentsOf: summaryFile),
                  let summary = try? JSONDecoder().decode(Summary.self, from: data) else {
                // Remove corrupted entry
                removeEntry(for: cacheKey)
                return nil
            }
            
            // Update last accessed time
            metadata.entries[cacheKey]?.lastAccessed = Date()
            try? saveMetadata()
            
            return summary
        }
    }
    
    /// Removes a summary from the cache
    func remove(for recordingId: UUID) {
        queue.sync {
            let keysToRemove = metadata.entries.compactMap { key, entry in
                entry.recordingId == recordingId ? key : nil
            }
            
            for key in keysToRemove {
                removeEntry(for: key)
            }
            
            try? saveMetadata()
        }
    }
    
    /// Removes all summaries from the cache
    func removeAll() {
        queue.sync {
            // Remove all files
            for (key, _) in metadata.entries {
                let summaryFile = cacheDirectory.appendingPathComponent("\(key).json")
                try? FileManager.default.removeItem(at: summaryFile)
            }
            
            // Clear metadata
            metadata.entries.removeAll()
            metadata.totalSize = 0
            
            try? saveMetadata()
        }
    }
    
    /// Gets cache statistics
    func getStatistics() -> SummaryCacheStatistics {
        return queue.sync {
            let now = Date()
            let recentEntries = metadata.entries.values.filter { entry in
                now.timeIntervalSince(entry.lastAccessed) < 7 * 24 * 60 * 60 // 7 days
            }
            
            return SummaryCacheStatistics(
                totalEntries: metadata.entries.count,
                totalSize: metadata.totalSize,
                recentlyAccessedCount: recentEntries.count,
                oldestEntry: metadata.entries.values.min(by: { $0.createdAt < $1.createdAt })?.createdAt,
                newestEntry: metadata.entries.values.max(by: { $0.createdAt < $1.createdAt })?.createdAt
            )
        }
    }
    
    /// Performs cache cleanup
    func cleanup() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.performCleanup()
                continuation.resume()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func generateCacheKey(recordingId: UUID, type: SummaryType, length: SummaryLength) -> String {
        return "\(recordingId.uuidString)_\(type.rawValue)_\(length.rawValue)"
    }
    
    private func removeEntry(for key: String) {
        guard let entry = metadata.entries[key] else { return }
        
        let summaryFile = cacheDirectory.appendingPathComponent("\(key).json")
        try? FileManager.default.removeItem(at: summaryFile)
        
        metadata.entries.removeValue(forKey: key)
        metadata.totalSize -= entry.fileSize
    }
    
    private func saveMetadata() throws {
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataFile)
    }
    
    private static func loadMetadata(from url: URL) -> CacheMetadata {
        guard let data = try? Data(contentsOf: url),
              let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: data) else {
            return CacheMetadata()
        }
        return metadata
    }
    
    private func cleanupIfNeeded() async {
        await withCheckedContinuation { continuation in
            queue.async {
                if self.metadata.totalSize > self.maxCacheSize {
                    self.performCleanup()
                }
                continuation.resume()
            }
        }
    }
    
    private func performCleanup() {
        let now = Date()
        var removedSize = 0
        
        // Remove expired entries
        let expiredKeys = metadata.entries.compactMap { key, entry in
            now.timeIntervalSince(entry.createdAt) > maxAge ? key : nil
        }
        
        for key in expiredKeys {
            if let entry = metadata.entries[key] {
                removedSize += entry.fileSize
            }
            removeEntry(for: key)
        }
        
        // If still over limit, remove least recently used entries
        if metadata.totalSize > maxCacheSize {
            let sortedEntries = metadata.entries.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
            
            for (key, entry) in sortedEntries {
                removeEntry(for: key)
                removedSize += entry.fileSize
                
                if metadata.totalSize <= maxCacheSize * 3 / 4 { // Remove until 75% of max size
                    break
                }
            }
        }
        
        // Save updated metadata
        try? saveMetadata()
        
        if removedSize > 0 {
            print("SummaryCache: Cleaned up \(ByteCountFormatter.string(fromByteCount: Int64(removedSize), countStyle: .file))")
        }
    }
}

// MARK: - Cache Data Models

private struct CacheMetadata: Codable {
    var entries: [String: CacheEntry] = [:]
    var totalSize: Int = 0
}

private struct CacheEntry: Codable {
    let key: String
    let recordingId: UUID
    let type: SummaryType
    let length: SummaryLength
    let createdAt: Date
    let fileSize: Int
    var lastAccessed: Date
}

// MARK: - Cache Statistics

struct SummaryCacheStatistics {
    let totalEntries: Int
    let totalSize: Int
    let recentlyAccessedCount: Int
    let oldestEntry: Date?
    let newestEntry: Date?
    
    var formattedSize: String {
        return ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }
    
    var hitRate: Double {
        guard totalEntries > 0 else { return 0.0 }
        return Double(recentlyAccessedCount) / Double(totalEntries)
    }
    
    var averageEntrySize: Int {
        guard totalEntries > 0 else { return 0 }
        return totalSize / totalEntries
    }
}