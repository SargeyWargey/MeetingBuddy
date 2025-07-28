import Foundation
import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif
import os.log

/// Optimizes UI updates and threading for transcription processing
@MainActor
class UIThreadOptimizer: ObservableObject {
    
    // MARK: - Constants
    
    private static let batchUpdateInterval: TimeInterval = 0.1 // 100ms batching
    private static let heavyWorkThreshold: TimeInterval = 0.016 // 16ms (60fps)
    private static let maxBatchSize = 50
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.sargeywar.HelloWorld", category: "UIThreadOptimizer")
    
    // Batching mechanisms
    private var pendingUpdates: [AnyUIUpdateOperation] = []
    private var batchTimer: Timer?
    private var updateScheduler = PassthroughSubject<Void, Never>()
    
    // Performance tracking
    @Published private(set) var isOptimizingUpdates = false
    @Published private(set) var frameDropCount = 0
    @Published private(set) var averageUpdateTime: TimeInterval = 0
    
    private var updateTimes: [TimeInterval] = []
    private var lastFrameTime = CACurrentMediaTime()
    
    // Threading coordination
    private let backgroundQueue = DispatchQueue(label: "ui.background.processing", qos: .userInitiated)
    private let coordinatorQueue = DispatchQueue(label: "ui.coordinator", qos: .userInteractive)
    
    // MARK: - Initialization
    
    init() {
        setupUpdateScheduler()
        setupFrameRateMonitoring()
        logger.info("UIThreadOptimizer initialized")
    }
    
    private func setupUpdateScheduler() {
        updateScheduler
            .collect(.byTime(DispatchQueue.main, .milliseconds(Int(Self.batchUpdateInterval * 1000))))
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.processBatchedUpdates()
                }
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - UI Update Optimization
    
    /// Schedule a UI update with automatic batching and thread optimization
    func scheduleUpdate<T>(_ operation: UIUpdateOperation<T>) async {
        let startTime = CACurrentMediaTime()
        
        // Check if this is a heavy operation that should be batched
        if operation.estimatedDuration > Self.heavyWorkThreshold {
            await batchUpdate(operation)
        } else {
            let anyOperation = AnyUIUpdateOperation(operation)
            await executeUpdate(anyOperation)
        }
        
        let duration = CACurrentMediaTime() - startTime
        await trackUpdatePerformance(duration: duration)
    }
    
    private func batchUpdate<T>(_ operation: UIUpdateOperation<T>) async {
        pendingUpdates.append(AnyUIUpdateOperation(operation))
        
        if pendingUpdates.count >= Self.maxBatchSize {
            await processBatchedUpdates()
        } else {
            updateScheduler.send(())
        }
    }
    
    private func executeUpdate(_ operation: AnyUIUpdateOperation) async {
        do {
            await operation.execute()
        } catch {
            logger.error("UI update failed: \(error.localizedDescription)")
        }
    }
    
    private func processBatchedUpdates() async {
        guard !pendingUpdates.isEmpty else { return }
        
        isOptimizingUpdates = true
        defer { isOptimizingUpdates = false }
        
        let updates = pendingUpdates
        pendingUpdates.removeAll()
        
        logger.debug("Processing \(updates.count) batched UI updates")
        
        // Group updates by priority and type
        let prioritizedUpdates = updates.sorted { $0.priority.rawValue > $1.priority.rawValue }
        
        // Process high-priority updates immediately
        let highPriorityUpdates = prioritizedUpdates.filter { $0.priority == .high }
        for update in highPriorityUpdates {
            await executeUpdate(update)
        }
        
        // Process remaining updates with yield points
        let remainingUpdates = prioritizedUpdates.filter { $0.priority != .high }
        for (index, update) in remainingUpdates.enumerated() {
            await executeUpdate(update)
            
            // Yield control every few updates to prevent blocking
            if index % 10 == 9 {
                await Task.yield()
            }
        }
    }
    
    // MARK: - Background Processing Coordination
    
    /// Execute heavy work on background thread with UI-safe completion
    func executeOnBackground<T>(
        work: @escaping () async throws -> T,
        completion: @MainActor @escaping (Result<T, Error>) -> Void
    ) {
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let result = try await work()
                await MainActor.run {
                    completion(.success(result))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
                self?.logger.error("Background work failed: \(error.localizedDescription)")
            }
        }
    }
    
    /// Execute transcription processing with progress updates
    func executeTranscriptionWork<T>(
        work: @escaping (@escaping (TranscriptionProgress) -> Void) async throws -> T,
        progressHandler: @MainActor @escaping (TranscriptionProgress) -> Void,
        completion: @MainActor @escaping (Result<T, Error>) -> Void
    ) {
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let result = try await work { progress in
                    // Throttle progress updates to avoid overwhelming UI
                    Task { @MainActor [weak self] in
                        await self?.scheduleUpdate(
                            UIUpdateOperation(
                                priority: .medium,
                                estimatedDuration: 0.001
                            ) {
                                progressHandler(progress)
                            }
                        )
                    }
                }
                
                await MainActor.run {
                    completion(.success(result))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
                self?.logger.error("Transcription work failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Smart List Updates
    
    /// Optimize list updates for recordings with transcription changes
    func updateRecordingsList(
        currentRecordings: [Recording],
        updatedRecordings: [Recording],
        listUpdateHandler: @MainActor @escaping ([RecordingListUpdate]) -> Void
    ) async {
        
        await executeOnBackground(
            work: {
                return self.calculateListDifferences(
                    current: currentRecordings,
                    updated: updatedRecordings
                )
            },
            completion: { result in
                switch result {
                case .success(let updates):
                    // Apply updates with animation coordination
                    Task { @MainActor in
                        await self.scheduleUpdate(
                            UIUpdateOperation(
                                priority: .high,
                                estimatedDuration: Double(updates.count) * 0.001
                            ) {
                                listUpdateHandler(updates)
                            }
                        )
                    }
                case .failure(let error):
                    self.logger.error("List diff calculation failed: \(error)")
                }
            }
        )
    }
    
    private func calculateListDifferences(
        current: [Recording],
        updated: [Recording]
    ) -> [RecordingListUpdate] {
        var updates: [RecordingListUpdate] = []
        
        let currentDict = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        let updatedDict = Dictionary(uniqueKeysWithValues: updated.map { ($0.id, $0) })
        
        // Find insertions and updates
        for (id, updatedRecording) in updatedDict {
            if let currentRecording = currentDict[id] {
                // Check if transcription changed
                if currentRecording.transcription != updatedRecording.transcription ||
                   currentRecording.transcriptionStatus != updatedRecording.transcriptionStatus {
                    updates.append(.update(recording: updatedRecording))
                }
            } else {
                updates.append(.insert(recording: updatedRecording))
            }
        }
        
        // Find deletions
        for (id, _) in currentDict {
            if updatedDict[id] == nil {
                updates.append(.delete(recordingId: id))
            }
        }
        
        return updates
    }
    
    // MARK: - Animation Coordination
    
    /// Coordinate animations with transcription updates
    func coordinateAnimation<T>(
        duration: TimeInterval = 0.3,
        updates: @MainActor @escaping () -> T
    ) async -> T {
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                let result = await withAnimation(
                    .easeInOut(duration: duration)
                ) {
                    updates()
                }
                continuation.resume(returning: result)
            }
        }
    }
    
    // MARK: - Performance Monitoring
    
    private func setupFrameRateMonitoring() {
        // Use a timer instead of CADisplayLink for macOS compatibility
        Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.frameUpdate()
        }
    }
    
    private func frameUpdate() {
        let currentTime = CACurrentMediaTime()
        let frameDuration = currentTime - lastFrameTime
        
        // Detect dropped frames (assuming 60fps target)
        if frameDuration > 0.02 { // 20ms indicates dropped frame
            frameDropCount += 1
        }
        
        lastFrameTime = currentTime
    }
    
    private func trackUpdatePerformance(duration: TimeInterval) async {
        updateTimes.append(duration)
        
        // Keep only recent samples
        if updateTimes.count > 100 {
            updateTimes.removeFirst()
        }
        
        averageUpdateTime = updateTimes.reduce(0, +) / Double(updateTimes.count)
        
        if duration > Self.heavyWorkThreshold {
            logger.warning("Slow UI update detected: \(duration * 1000)ms")
        }
    }
    
    // MARK: - Public Interface
    
    func getPerformanceMetrics() -> UIPerformanceMetrics {
        return UIPerformanceMetrics(
            averageUpdateTime: averageUpdateTime,
            frameDropCount: frameDropCount,
            pendingUpdatesCount: pendingUpdates.count,
            isOptimizing: isOptimizingUpdates
        )
    }
    
    func resetPerformanceMetrics() {
        frameDropCount = 0
        updateTimes.removeAll()
        averageUpdateTime = 0
    }
    
    deinit {
        batchTimer?.invalidate()
        cancellables.removeAll()
    }
}

// MARK: - Supporting Types

struct UIUpdateOperation<T> {
    let priority: UIUpdatePriority
    let estimatedDuration: TimeInterval
    let execute: () async -> T
    
    init(
        priority: UIUpdatePriority = .medium,
        estimatedDuration: TimeInterval = 0.001,
        execute: @escaping () async -> T
    ) {
        self.priority = priority
        self.estimatedDuration = estimatedDuration
        self.execute = execute
    }
}

// Type-erased version for storage
private struct AnyUIUpdateOperation {
    let priority: UIUpdatePriority
    let estimatedDuration: TimeInterval
    let execute: () async -> Void
    
    init<T>(_ operation: UIUpdateOperation<T>) {
        self.priority = operation.priority
        self.estimatedDuration = operation.estimatedDuration
        self.execute = {
            _ = await operation.execute()
        }
    }
}

enum UIUpdatePriority: Int, CaseIterable {
    case low = 1
    case medium = 2
    case high = 3
}

enum RecordingListUpdate {
    case insert(recording: Recording)
    case update(recording: Recording)
    case delete(recordingId: UUID)
}

struct TranscriptionProgress {
    let completedChunks: Int
    let totalChunks: Int
    let currentOperation: String
    let estimatedTimeRemaining: TimeInterval?
    
    var percentage: Double {
        guard totalChunks > 0 else { return 0 }
        return Double(completedChunks) / Double(totalChunks)
    }
}

struct UIPerformanceMetrics {
    let averageUpdateTime: TimeInterval
    let frameDropCount: Int
    let pendingUpdatesCount: Int
    let isOptimizing: Bool
    
    var frameDropRate: Double {
        // This would be enhanced with more sophisticated tracking
        return Double(frameDropCount) / 1000.0 // Placeholder calculation
    }
}

