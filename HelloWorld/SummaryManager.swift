import Foundation
import Combine

// MARK: - Summary Manager

@MainActor
class SummaryManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isGenerating: Bool = false
    @Published var progress: Double = 0.0
    @Published var currentProvider: AIProvider?
    @Published var currentRecordingId: UUID?
    @Published var lastError: SummaryError?
    
    // MARK: - Private Properties
    
    private let openAIService: OpenAIService
    private let onDeviceService: OnDeviceAIService
    private let networkMonitor: NetworkMonitor
    private let cache: SummaryCache
    private let queue: SummaryQueue
    private var preferences: SummaryPreferences
    
    private var cancellables = Set<AnyCancellable>()
    private let maxConcurrentOperations = 2
    private var activeOperations: Set<UUID> = []
    
    // MARK: - Initialization
    
    init(networkMonitor: NetworkMonitor) {
        self.networkMonitor = networkMonitor
        self.openAIService = OpenAIService(networkMonitor: networkMonitor)
        self.onDeviceService = OnDeviceAIService()
        self.cache = SummaryCache()
        self.queue = SummaryQueue()
        self.preferences = SummaryPreferences.loadFromUserDefaults()
        
        setupNetworkMonitoring()
        setupQueueProcessing()
    }
    
    // MARK: - Public Methods
    
    /// Generates a summary for the given recording
    func generateSummary(
        for recording: Recording,
        type: SummaryType? = nil,
        length: SummaryLength? = nil,
        forceRegenerate: Bool = false
    ) async throws -> Summary {
        
        // Validate input
        guard recording.canSummarize else {
            throw SummaryError.transcriptionTooShort(wordCount: recording.transcriptionWordCount)
        }
        
        guard let transcription = recording.transcription else {
            throw SummaryError.unknownError("No transcription available")
        }
        
        // Use provided parameters or fall back to preferences
        let summaryType = type ?? preferences.defaultType
        let summaryLength = length ?? preferences.defaultLength
        
        // Check cache first (unless forcing regeneration)
        if !forceRegenerate,
           let cachedSummary = cache.retrieve(for: recording.id, type: summaryType, length: summaryLength) {
            return cachedSummary
        }
        
        // Check if we're already generating for this recording
        guard !activeOperations.contains(recording.id) else {
            throw SummaryError.unknownError("Summary generation already in progress for this recording")
        }
        
        // Check concurrent operations limit
        guard activeOperations.count < maxConcurrentOperations else {
            // Queue the request
            try await queue.enqueue(
                recordingId: recording.id,
                transcription: transcription,
                type: summaryType,
                length: summaryLength
            )
            throw SummaryError.unknownError("Request queued due to concurrent operation limit")
        }
        
        // Start generation
        activeOperations.insert(recording.id)
        isGenerating = true
        currentRecordingId = recording.id
        progress = 0.0
        lastError = nil
        
        defer {
            activeOperations.remove(recording.id)
            if activeOperations.isEmpty {
                isGenerating = false
                currentRecordingId = nil
                progress = 0.0
                currentProvider = nil
            }
        }
        
        do {
            // Select AI provider
            let provider = selectProvider(for: transcription, preferredType: summaryType)
            currentProvider = provider
            progress = 0.1
            
            // Generate summary
            let result = try await generateSummaryWithProvider(
                provider: provider,
                transcription: transcription,
                type: summaryType,
                length: summaryLength
            )
            
            progress = 0.9
            
            // Create summary object
            let summary = result.toSummary(
                recordingId: recording.id,
                type: summaryType,
                length: summaryLength
            )
            
            // Cache the result
            try cache.store(summary)
            
            progress = 1.0
            
            // Provide accessibility feedback
            HapticFeedbackManager.shared.transcriptionCompleted()
            AccessibilityAnnouncementManager.shared.announce("Summary generated successfully")
            
            return summary
            
        } catch let error as SummaryError {
            lastError = error
            
            // Try fallback provider if appropriate
            if error.isRetryable, let fallbackProvider = getFallbackProvider(for: currentProvider) {
                do {
                    currentProvider = fallbackProvider
                    progress = 0.5
                    
                    let result = try await generateSummaryWithProvider(
                        provider: fallbackProvider,
                        transcription: transcription,
                        type: summaryType,
                        length: summaryLength
                    )
                    
                    let summary = result.toSummary(
                        recordingId: recording.id,
                        type: summaryType,
                        length: summaryLength
                    )
                    
                    try cache.store(summary)
                    progress = 1.0
                    
                    HapticFeedbackManager.shared.transcriptionCompleted()
                    AccessibilityAnnouncementManager.shared.announce("Summary generated with fallback provider")
                    
                    return summary
                    
                } catch {
                    // Both providers failed
                    HapticFeedbackManager.shared.transcriptionFailed()
                    AccessibilityAnnouncementManager.shared.announce("Summary generation failed")
                    throw error
                }
            } else {
                // Queue for later if appropriate
                if shouldQueueOnFailure(error: error) {
                    try await queue.enqueue(
                        recordingId: recording.id,
                        transcription: transcription,
                        type: summaryType,
                        length: summaryLength
                    )
                }
                
                HapticFeedbackManager.shared.transcriptionFailed()
                AccessibilityAnnouncementManager.shared.announce("Summary generation failed")
                throw error
            }
        }
    }
    
    /// Gets a cached summary for the recording
    func getSummary(for recordingId: UUID, type: SummaryType? = nil, length: SummaryLength? = nil) -> Summary? {
        let summaryType = type ?? preferences.defaultType
        let summaryLength = length ?? preferences.defaultLength
        return cache.retrieve(for: recordingId, type: summaryType, length: summaryLength)
    }
    
    /// Deletes a summary for the recording
    func deleteSummary(for recordingId: UUID) {
        cache.remove(for: recordingId)
    }
    
    /// Updates summary preferences
    func updateSummaryPreferences(_ newPreferences: SummaryPreferences) {
        preferences = newPreferences
        preferences.saveToUserDefaults()
    }
    
    /// Gets current summary preferences
    func getSummaryPreferences() -> SummaryPreferences {
        return preferences
    }
    
    /// Estimates the cost for generating a summary
    func estimateCost(for recording: Recording, provider: AIProvider? = nil) -> Double? {
        guard let transcription = recording.transcription else { return nil }
        
        let selectedProvider = provider ?? selectProvider(for: transcription, preferredType: preferences.defaultType)
        
        switch selectedProvider {
        case .openAI:
            return openAIService.estimatedCost(for: transcription)
        case .onDevice:
            return onDeviceService.estimatedCost(for: transcription)
        case .claude:
            return nil // Not implemented yet
        }
    }
    
    /// Gets usage statistics for OpenAI
    func getOpenAIUsageStats() -> OpenAIUsageStats {
        return openAIService.getUsageStats()
    }
    
    /// Resets OpenAI usage statistics
    func resetOpenAIUsageStats() {
        openAIService.resetUsageStats()
    }
    
    /// Processes the summary queue manually
    func processQueue() async {
        await queue.processQueue { [weak self] item in
            guard let self = self else { return }
            
            do {
                let provider = self.selectProvider(for: item.transcription, preferredType: item.type)
                let result = try await self.generateSummaryWithProvider(
                    provider: provider,
                    transcription: item.transcription,
                    type: item.type,
                    length: item.length
                )
                
                let summary = result.toSummary(
                    recordingId: item.recordingId,
                    type: item.type,
                    length: item.length
                )
                
                try self.cache.store(summary)
                
                // Notify about successful processing
                NotificationCenter.default.post(
                    name: .summaryGenerated,
                    object: self,
                    userInfo: ["recordingId": item.recordingId, "summary": summary]
                )
                
            } catch {
                // Notify about failed processing
                NotificationCenter.default.post(
                    name: .summaryGenerationFailed,
                    object: self,
                    userInfo: ["recordingId": item.recordingId, "error": error]
                )
            }
        }
    }
    
    /// Gets the current queue status
    func getQueueStatus() -> SummaryQueueStatus {
        return queue.getStatus()
    }
    
    /// Clears the summary queue
    func clearQueue() {
        queue.clear()
    }
    
    // MARK: - Private Methods
    
    private func setupNetworkMonitoring() {
        networkMonitor.$isConnected
            .sink { [weak self] isConnected in
                if isConnected {
                    Task {
                        await self?.processQueue()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupQueueProcessing() {
        // Process queue every 5 minutes when online
        Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                if self?.networkMonitor.isConnected == true {
                    Task {
                        await self?.processQueue()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func selectProvider(for transcription: String, preferredType: SummaryType) -> AIProvider {
        // Check user preference first
        if let preferredProvider = preferences.preferredProvider,
           isProviderAvailable(preferredProvider) {
            return preferredProvider
        }
        
        // Auto-select based on conditions
        
        // If offline, use on-device
        if !networkMonitor.isConnected {
            return .onDevice
        }
        
        // If OpenAI is not available (no API key), use on-device
        if !openAIService.isAvailable() {
            return .onDevice
        }
        
        // For bullet points and key insights, OpenAI generally performs better
        if preferredType == .bulletPoints || preferredType == .keyInsights {
            return .openAI
        }
        
        // For very long transcriptions, prefer on-device to avoid costs
        let wordCount = transcription.split(separator: " ").count
        if wordCount > 1000 {
            return .onDevice
        }
        
        // Assess text quality and choose accordingly
        let qualityAssessment = onDeviceService.assessTextQuality(transcription)
        return qualityAssessment.recommendedProvider
    }
    
    private func isProviderAvailable(_ provider: AIProvider) -> Bool {
        switch provider {
        case .openAI:
            return openAIService.isAvailable()
        case .onDevice:
            return onDeviceService.isAvailable()
        case .claude:
            return false // Not implemented yet
        }
    }
    
    private func getFallbackProvider(for currentProvider: AIProvider?) -> AIProvider? {
        switch currentProvider {
        case .openAI:
            return .onDevice
        case .onDevice:
            return networkMonitor.isConnected ? .openAI : nil
        case .claude:
            return networkMonitor.isConnected ? .openAI : .onDevice
        case .none:
            return nil
        }
    }
    
    private func generateSummaryWithProvider(
        provider: AIProvider,
        transcription: String,
        type: SummaryType,
        length: SummaryLength
    ) async throws -> SummaryResult {
        
        switch provider {
        case .openAI:
            return try await openAIService.generateSummary(
                from: transcription,
                type: type,
                length: length
            )
        case .onDevice:
            return try await onDeviceService.generateSummary(
                from: transcription,
                type: type,
                length: length
            )
        case .claude:
            throw SummaryError.aiServiceUnavailable(provider: .claude)
        }
    }
    
    private func shouldQueueOnFailure(error: SummaryError) -> Bool {
        switch error {
        case .networkUnavailable, .aiServiceUnavailable, .rateLimitExceeded:
            return true
        case .transcriptionTooShort, .apiKeyMissing, .apiKeyInvalid, .contentTooLarge:
            return false
        case .quotaExceeded, .invalidResponse, .cacheError, .unknownError:
            return true
        }
    }
}

// MARK: - Summary Preferences Extension

extension SummaryPreferences {
    private static let userDefaultsKey = "SummaryPreferences"
    
    static func loadFromUserDefaults() -> SummaryPreferences {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let preferences = try? JSONDecoder().decode(SummaryPreferences.self, from: data) else {
            return .default
        }
        return preferences
    }
    
    func saveToUserDefaults() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let summaryGenerated = Notification.Name("summaryGenerated")
    static let summaryGenerationFailed = Notification.Name("summaryGenerationFailed")
    static let summaryQueueUpdated = Notification.Name("summaryQueueUpdated")
}

// MARK: - Summary Queue Status

struct SummaryQueueStatus {
    let pendingCount: Int
    let isProcessing: Bool
    let lastProcessedAt: Date?
    let nextProcessingAt: Date?
    
    var isEmpty: Bool {
        return pendingCount == 0
    }
    
    var statusDescription: String {
        if isProcessing {
            return "Processing queue..."
        } else if pendingCount > 0 {
            return "\(pendingCount) item\(pendingCount == 1 ? "" : "s") queued"
        } else {
            return "Queue empty"
        }
    }
}