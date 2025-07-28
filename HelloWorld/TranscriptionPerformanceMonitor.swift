import Foundation
#if canImport(UIKit)
import UIKit
#endif
import os.log
import Combine

/// Monitors and optimizes transcription queue processing performance
@MainActor
class TranscriptionPerformanceMonitor: ObservableObject {
    
    // MARK: - Constants
    
    private static let metricsCollectionInterval: TimeInterval = 5.0
    private static let performanceWindowSize = 100
    private static let slowOperationThreshold: TimeInterval = 10.0
    private static let memoryWarningThreshold = 75 // MB
    
    // MARK: - Published Properties
    
    @Published private(set) var currentMetrics = PerformanceMetrics()
    @Published private(set) var isMonitoring = false
    @Published private(set) var performanceAlerts: [PerformanceAlert] = []
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.sargeywar.HelloWorld", category: "TranscriptionPerformanceMonitor")
    
    private var metricsTimer: Timer?
    private var operationHistory: [OperationMetric] = []
    private var queueMetrics: [QueueMetric] = []
    private var memorySnapshots: [MemorySnapshot] = []
    
    private let metricsQueue = DispatchQueue(label: "performance.metrics", qos: .utility)
    private var cancellables = Set<AnyCancellable>()
    
    // Performance tracking
    private var activeOperations: [UUID: OperationTracker] = [:]
    private var completedOperations: [OperationMetric] = []
    
    // Queue performance tracking
    private var queueProcessingStartTime: Date?
    private var processedItemsCount = 0
    private var failedItemsCount = 0
    
    // MARK: - Initialization
    
    init() {
        setupMetricsCollection()
        setupMemoryMonitoring()
        logger.info("TranscriptionPerformanceMonitor initialized")
    }
    
    private func setupMetricsCollection() {
        metricsTimer = Timer.scheduledTimer(withTimeInterval: Self.metricsCollectionInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.collectMetrics()
            }
        }
    }
    
    private func setupMemoryMonitoring() {
        #if canImport(UIKit)
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.handleMemoryWarning()
                }
            }
            .store(in: &cancellables)
        #else
        // On macOS, we'll create a custom memory warning notification
        NotificationCenter.default.publisher(for: .lowMemoryCondition)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.handleMemoryWarning()
                }
            }
            .store(in: &cancellables)
        #endif
    }
    
    // MARK: - Operation Tracking
    
    /// Start tracking a transcription operation
    func startTrackingOperation(
        id: UUID,
        type: TranscriptionOperationType,
        audioFileSize: Int64,
        priority: TranscriptionPriority
    ) {
        let tracker = OperationTracker(
            id: id,
            type: type,
            audioFileSize: audioFileSize,
            priority: priority,
            startTime: Date()
        )
        
        activeOperations[id] = tracker
        logger.debug("Started tracking operation: \(id.uuidString), type: \(type.rawValue)")
    }
    
    /// Update operation progress
    func updateOperationProgress(id: UUID, progress: Double, currentPhase: String) {
        guard var tracker = activeOperations[id] else { return }
        
        tracker.progress = progress
        tracker.currentPhase = currentPhase
        tracker.lastUpdateTime = Date()
        activeOperations[id] = tracker
        
        // Check for slow operations
        let duration = Date().timeIntervalSince(tracker.startTime)
        if duration > Self.slowOperationThreshold && !tracker.hasSlowWarning {
            tracker.hasSlowWarning = true
            activeOperations[id] = tracker
            
            let alert = PerformanceAlert(
                type: .slowOperation,
                message: "Transcription operation taking longer than expected",
                operationId: id,
                timestamp: Date()
            )
            performanceAlerts.append(alert)
            logger.warning("Slow operation detected: \(id) - \(duration)s")
        }
    }
    
    /// Complete operation tracking
    func completeOperation(id: UUID, success: Bool, resultSize: Int? = nil, error: Error? = nil) {
        guard let tracker = activeOperations.removeValue(forKey: id) else { return }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(tracker.startTime)
        
        let metric = OperationMetric(
            id: id,
            type: tracker.type,
            audioFileSize: tracker.audioFileSize,
            priority: tracker.priority,
            duration: duration,
            success: success,
            resultSize: resultSize,
            memoryUsage: getCurrentMemoryUsage(),
            error: error?.localizedDescription,
            timestamp: tracker.startTime
        )
        
        operationHistory.append(metric)
        
        // Trim history to keep within window size
        if operationHistory.count > Self.performanceWindowSize {
            operationHistory.removeFirst()
        }
        
        logger.info("Completed operation: \(id), duration: \(duration)s, success: \(success)")
        
        // Update queue metrics if this was a queued operation
        if success {
            processedItemsCount += 1
        } else {
            failedItemsCount += 1
        }
    }
    
    // MARK: - Queue Performance Tracking
    
    /// Start monitoring queue processing session
    func startQueueProcessingSession() {
        queueProcessingStartTime = Date()
        processedItemsCount = 0
        failedItemsCount = 0
        logger.debug("Started queue processing session")
    }
    
    /// End queue processing session
    func endQueueProcessingSession(totalItemsProcessed: Int, remainingItems: Int) {
        guard let startTime = queueProcessingStartTime else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        let throughput = totalItemsProcessed > 0 ? duration / Double(totalItemsProcessed) : 0
        
        let queueMetric = QueueMetric(
            sessionDuration: duration,
            itemsProcessed: processedItemsCount,
            itemsFailed: failedItemsCount,
            remainingItems: remainingItems,
            averageProcessingTime: throughput,
            memoryUsage: getCurrentMemoryUsage(),
            timestamp: startTime
        )
        
        queueMetrics.append(queueMetric)
        
        // Trim queue metrics
        if queueMetrics.count > Self.performanceWindowSize {
            queueMetrics.removeFirst()
        }
        
        queueProcessingStartTime = nil
        
        logger.info("Queue session completed: \(self.processedItemsCount) processed, \(self.failedItemsCount) failed, \(duration)s")
        
        // Generate performance alerts if needed
        Task { @MainActor in
            await self.checkQueuePerformance(metric: queueMetric)
        }
    }
    
    // MARK: - Metrics Collection
    
    private func collectMetrics() async {
        let memoryUsage = getCurrentMemoryUsage()
        let memorySnapshot = MemorySnapshot(
            usage: memoryUsage,
            timestamp: Date()
        )
        
        memorySnapshots.append(memorySnapshot)
        
        // Trim memory snapshots
        if memorySnapshots.count > Self.performanceWindowSize {
            memorySnapshots.removeFirst()
        }
        
        // Update current metrics
        currentMetrics = calculateCurrentMetrics()
        
        logger.debug("Collected metrics - Memory: \(memoryUsage)MB, Active ops: \(self.activeOperations.count)")
    }
    
    private func calculateCurrentMetrics() -> PerformanceMetrics {
        let recentOperations = operationHistory.suffix(20)
        let recentQueueMetrics = queueMetrics.suffix(10)
        let recentMemorySnapshots = memorySnapshots.suffix(20)
        
        // Calculate operation metrics
        let avgOperationDuration = recentOperations.isEmpty ? 0 :
            recentOperations.reduce(0) { $0 + $1.duration } / Double(recentOperations.count)
        
        let successRate = recentOperations.isEmpty ? 1.0 :
            Double(recentOperations.filter { $0.success }.count) / Double(recentOperations.count)
        
        // Calculate queue metrics
        let avgThroughput = recentQueueMetrics.isEmpty ? 0 :
            recentQueueMetrics.reduce(0) { $0 + $1.averageProcessingTime } / Double(recentQueueMetrics.count)
        
        let totalProcessed = recentQueueMetrics.reduce(0) { $0 + $1.itemsProcessed }
        let totalFailed = recentQueueMetrics.reduce(0) { $0 + $1.itemsFailed }
        
        // Calculate memory metrics
        let avgMemoryUsage = recentMemorySnapshots.isEmpty ? 0 :
            recentMemorySnapshots.reduce(0) { $0 + $1.usage } / Double(recentMemorySnapshots.count)
        
        let peakMemoryUsage = recentMemorySnapshots.max { $0.usage < $1.usage }?.usage ?? 0
        
        return PerformanceMetrics(
            averageOperationDuration: avgOperationDuration,
            operationSuccessRate: successRate,
            activeOperationsCount: activeOperations.count,
            queueThroughput: avgThroughput,
            totalItemsProcessed: totalProcessed,
            totalItemsFailed: totalFailed,
            averageMemoryUsage: avgMemoryUsage,
            peakMemoryUsage: peakMemoryUsage,
            alertCount: performanceAlerts.count
        )
    }
    
    // MARK: - Performance Analysis
    
    private func checkQueuePerformance(metric: QueueMetric) async {
        // Check for performance degradation
        if metric.averageProcessingTime > 30.0 { // 30 seconds per item
            let alert = PerformanceAlert(
                type: .slowQueue,
                message: "Queue processing is slower than expected (\(metric.averageProcessingTime)s per item)",
                operationId: nil,
                timestamp: Date()
            )
            performanceAlerts.append(alert)
        }
        
        // Check failure rate
        let failureRate = Double(metric.itemsFailed) / Double(metric.itemsProcessed + metric.itemsFailed)
        if failureRate > 0.2 { // More than 20% failures
            let alert = PerformanceAlert(
                type: .highFailureRate,
                message: "High failure rate detected: \(Int(failureRate * 100))%",
                operationId: nil,
                timestamp: Date()
            )
            performanceAlerts.append(alert)
        }
        
        // Trim alerts
        if performanceAlerts.count > 20 {
            performanceAlerts.removeFirst(performanceAlerts.count - 20)
        }
    }
    
    private func handleMemoryWarning() async {
        let currentUsage = getCurrentMemoryUsage()
        
        let alert = PerformanceAlert(
            type: .memoryWarning,
            message: "Memory warning received (usage: \(currentUsage)MB)",
            operationId: nil,
            timestamp: Date()
        )
        performanceAlerts.append(alert)
        
        logger.warning("Memory warning - current usage: \(currentUsage)MB")
        
        // Clear old metrics to free memory
        if operationHistory.count > 50 {
            operationHistory.removeFirst(operationHistory.count - 50)
        }
        if queueMetrics.count > 50 {
            queueMetrics.removeFirst(queueMetrics.count - 50)
        }
        if memorySnapshots.count > 50 {
            memorySnapshots.removeFirst(memorySnapshots.count - 50)
        }
    }
    
    // MARK: - Memory Utilities
    
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
    
    // MARK: - Public Interface
    
    func startMonitoring() {
        isMonitoring = true
        logger.info("Performance monitoring started")
    }
    
    func stopMonitoring() {
        isMonitoring = false
        metricsTimer?.invalidate()
        logger.info("Performance monitoring stopped")
    }
    
    func clearAlerts() {
        performanceAlerts.removeAll()
    }
    
    func getDetailedReport() -> PerformanceReport {
        return PerformanceReport(
            metrics: currentMetrics,
            recentOperations: Array(operationHistory.suffix(10)),
            recentQueueMetrics: Array(queueMetrics.suffix(5)),
            alerts: performanceAlerts,
            generatedAt: Date()
        )
    }
    
    func exportMetrics() -> Data? {
        let exportData = MetricsExport(
            operations: operationHistory,
            queueMetrics: queueMetrics,
            memorySnapshots: memorySnapshots,
            alerts: performanceAlerts,
            exportedAt: Date()
        )
        
        return try? JSONEncoder().encode(exportData)
    }
    
    deinit {
        metricsTimer?.invalidate()
        cancellables.removeAll()
    }
}

// MARK: - Supporting Types

private struct OperationTracker {
    let id: UUID
    let type: TranscriptionOperationType
    let audioFileSize: Int64
    let priority: TranscriptionPriority
    let startTime: Date
    var progress: Double = 0
    var currentPhase: String = "Starting"
    var lastUpdateTime: Date
    var hasSlowWarning = false
    
    init(id: UUID, type: TranscriptionOperationType, audioFileSize: Int64, priority: TranscriptionPriority, startTime: Date) {
        self.id = id
        self.type = type
        self.audioFileSize = audioFileSize
        self.priority = priority
        self.startTime = startTime
        self.lastUpdateTime = startTime
    }
}

struct OperationMetric: Codable {
    let id: UUID
    let type: TranscriptionOperationType
    let audioFileSize: Int64
    let priority: TranscriptionPriority
    let duration: TimeInterval
    let success: Bool
    let resultSize: Int?
    let memoryUsage: Double
    let error: String?
    let timestamp: Date
}

struct QueueMetric: Codable {
    let sessionDuration: TimeInterval
    let itemsProcessed: Int
    let itemsFailed: Int
    let remainingItems: Int
    let averageProcessingTime: TimeInterval
    let memoryUsage: Double
    let timestamp: Date
}

struct MemorySnapshot: Codable {
    let usage: Double
    let timestamp: Date
}

struct PerformanceMetrics {
    let averageOperationDuration: TimeInterval
    let operationSuccessRate: Double
    let activeOperationsCount: Int
    let queueThroughput: TimeInterval
    let totalItemsProcessed: Int
    let totalItemsFailed: Int
    let averageMemoryUsage: Double
    let peakMemoryUsage: Double
    let alertCount: Int
    
    init() {
        self.averageOperationDuration = 0
        self.operationSuccessRate = 1.0
        self.activeOperationsCount = 0
        self.queueThroughput = 0
        self.totalItemsProcessed = 0
        self.totalItemsFailed = 0
        self.averageMemoryUsage = 0
        self.peakMemoryUsage = 0
        self.alertCount = 0
    }
    
    init(averageOperationDuration: TimeInterval, operationSuccessRate: Double, activeOperationsCount: Int, queueThroughput: TimeInterval, totalItemsProcessed: Int, totalItemsFailed: Int, averageMemoryUsage: Double, peakMemoryUsage: Double, alertCount: Int) {
        self.averageOperationDuration = averageOperationDuration
        self.operationSuccessRate = operationSuccessRate
        self.activeOperationsCount = activeOperationsCount
        self.queueThroughput = queueThroughput
        self.totalItemsProcessed = totalItemsProcessed
        self.totalItemsFailed = totalItemsFailed
        self.averageMemoryUsage = averageMemoryUsage
        self.peakMemoryUsage = peakMemoryUsage
        self.alertCount = alertCount
    }
}

struct PerformanceAlert: Codable {
    let type: AlertType
    let message: String
    let operationId: UUID?
    let timestamp: Date
    
    enum AlertType: String, Codable {
        case slowOperation
        case slowQueue
        case highFailureRate
        case memoryWarning
        case networkIssue
    }
}

struct PerformanceReport {
    let metrics: PerformanceMetrics
    let recentOperations: [OperationMetric]
    let recentQueueMetrics: [QueueMetric]
    let alerts: [PerformanceAlert]
    let generatedAt: Date
}

private struct MetricsExport: Codable {
    let operations: [OperationMetric]
    let queueMetrics: [QueueMetric]
    let memorySnapshots: [MemorySnapshot]
    let alerts: [PerformanceAlert]
    let exportedAt: Date
}

enum TranscriptionOperationType: String, Codable {
    case automatic
    case manual
    case retry
    case batch
}

enum TranscriptionPriority: String, Codable {
    case low
    case normal
    case high
    case userRequested
}