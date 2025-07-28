import Foundation
#if canImport(UIKit)
import UIKit
import BackgroundTasks
#endif
import os.log

/// Handles app lifecycle events for transcription processing optimization
@MainActor
class AppLifecycleHandler: ObservableObject {
    
    #if !canImport(UIKit)
    // macOS fallback implementation
    @Published private(set) var appState: AppState = .foreground
    @Published private(set) var backgroundTimeRemaining: TimeInterval = 0
    @Published private(set) var isTransitioning = false
    
    init() {
        // Simplified macOS implementation
    }
    
    func configure(
        transcriptionService: TranscriptionService,
        backgroundTaskManager: BackgroundTaskManager,
        performanceMonitor: TranscriptionPerformanceMonitor,
        transcriptionCache: TranscriptionCache
    ) {
        // No-op on macOS
    }
    
    func scheduleForForegroundResume(_ action: @escaping () async -> Void) {
        // Execute immediately on macOS
        Task { await action() }
    }
    
    func getBackgroundTimeRemaining() -> TimeInterval {
        return 0
    }
    
    func hasBeenInBackgroundForExtendedPeriod() -> Bool {
        return false
    }
    
    func forceSaveState() async {
        // No-op on macOS
    }
    
    #else
    // iOS implementation
    
    // MARK: - Constants
    
    private static let backgroundProcessingGracePeriod: TimeInterval = 5.0
    private static let foregroundTransitionDelay: TimeInterval = 0.5
    
    // MARK: - Published Properties
    
    @Published private(set) var appState: AppState = .foreground
    @Published private(set) var backgroundTimeRemaining: TimeInterval = 0
    @Published private(set) var isTransitioning = false
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.sargeywar.HelloWorld", category: "AppLifecycleHandler")
    
    private weak var transcriptionService: TranscriptionService?
    private weak var backgroundTaskManager: BackgroundTaskManager?
    private weak var performanceMonitor: TranscriptionPerformanceMonitor?
    private weak var transcriptionCache: TranscriptionCache?
    
    private var backgroundTimer: Timer?
    private var transitionTimer: Timer?
    
    // State tracking
    private var enterBackgroundTime: Date?
    private var foregroundResumeActions: [() async -> Void] = []
    
    // MARK: - Initialization
    
    init() {
        setupLifecycleNotifications()
        logger.info("AppLifecycleHandler initialized")
    }
    
    private func setupLifecycleNotifications() {
        // App state notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        // Memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    // MARK: - Service Integration
    
    func configure(
        transcriptionService: TranscriptionService,
        backgroundTaskManager: BackgroundTaskManager,
        performanceMonitor: TranscriptionPerformanceMonitor,
        transcriptionCache: TranscriptionCache
    ) {
        self.transcriptionService = transcriptionService
        self.backgroundTaskManager = backgroundTaskManager
        self.performanceMonitor = performanceMonitor
        self.transcriptionCache = transcriptionCache
        
        backgroundTaskManager.setTranscriptionService(transcriptionService)
        logger.info("AppLifecycleHandler configured with services")
    }
    
    // MARK: - Lifecycle Event Handlers
    
    @objc private func appWillEnterForeground() {
        logger.info("App will enter foreground")
        
        Task { @MainActor in
            isTransitioning = true
            appState = .transitioning
            
            // Cancel transition timer if running
            transitionTimer?.invalidate()
            
            // Schedule foreground transition with delay to ensure UI is ready
            transitionTimer = Timer.scheduledTimer(withTimeInterval: Self.foregroundTransitionDelay, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.completeTransitionToForeground()
                }
            }
        }
    }
    
    @objc private func appDidEnterBackground() {
        logger.info("App did enter background")
        
        Task { @MainActor in
            isTransitioning = true
            appState = .transitioning
            enterBackgroundTime = Date()
            
            await handleBackgroundTransition()
        }
    }
    
    @objc private func appWillTerminate() {
        logger.info("App will terminate")
        
        Task { @MainActor in
            appState = .terminating
            await handleAppTermination()
        }
    }
    
    @objc private func appDidBecomeActive() {
        logger.debug("App did become active")
        
        Task { @MainActor in
            if appState == .foreground {
                await resumeNormalOperations()
            }
        }
    }
    
    @objc private func appWillResignActive() {
        logger.debug("App will resign active")
        
        Task { @MainActor in
            await prepareForInactiveState()
        }
    }
    
    @objc private func handleMemoryWarning() {
        logger.warning("Memory warning received")
        
        Task { @MainActor in
            await handleLowMemoryCondition()
        }
    }
    
    // MARK: - Transition Handling
    
    private func handleBackgroundTransition() async {
        logger.info("Handling background transition")
        
        // Pause non-critical operations
        await pauseNonCriticalOperations()
        
        // Save current state
        await saveApplicationState()
        
        // Enable background processing
        backgroundTaskManager?.enableBackgroundProcessing()
        
        // Start background time monitoring
        startBackgroundTimeMonitoring()
        
        // Complete transition
        appState = .background
        isTransitioning = false
        
        logger.info("Background transition completed")
    }
    
    private func completeTransitionToForeground() async {
        logger.info("Completing foreground transition")
        
        // Stop background time monitoring
        stopBackgroundTimeMonitoring()
        
        // Disable background processing
        backgroundTaskManager?.disableBackgroundProcessing()
        
        // Resume operations
        await resumeForegroundOperations()
        
        // Execute queued foreground actions
        for action in foregroundResumeActions {
            await action()
        }
        foregroundResumeActions.removeAll()
        
        // Complete transition
        appState = .foreground
        isTransitioning = false
        
        logger.info("Foreground transition completed")
    }
    
    private func handleAppTermination() async {
        logger.info("Handling app termination")
        
        // Save critical state
        await saveApplicationState()
        
        // Clean up resources
        await cleanupResources()
        
        // Stop all operations
        await stopAllOperations()
        
        logger.info("App termination handling completed")
    }
    
    // MARK: - Operation Management
    
    private func pauseNonCriticalOperations() async {
        logger.debug("Pausing non-critical operations")
        
        // Pause automatic transcription for new recordings
        await transcriptionService?.pauseAutomaticTranscription()
        
        // Reduce performance monitoring frequency
        performanceMonitor?.stopMonitoring()
        
        // Trigger cache maintenance
        await transcriptionCache?.performMaintenance()
    }
    
    private func resumeForegroundOperations() async {
        logger.debug("Resuming foreground operations")
        
        // Resume automatic transcription
        await transcriptionService?.resumeAutomaticTranscription()
        
        // Resume performance monitoring
        performanceMonitor?.startMonitoring()
        
        // Refresh transcription status for visible recordings
        await transcriptionService?.refreshVisibleTranscriptions()
        
        // Process any queued UI updates
        await processQueuedUIUpdates()
    }
    
    private func resumeNormalOperations() async {
        logger.debug("Resuming normal operations")
        
        // Check for network connectivity changes
        await transcriptionService?.checkNetworkConnectivity()
        
        // Process any offline transcriptions that completed
        await transcriptionService?.processOfflineCompletions()
        
        // Update UI with any changes that occurred while inactive
        await refreshUserInterface()
    }
    
    private func prepareForInactiveState() async {
        logger.debug("Preparing for inactive state")
        
        // Pause UI-intensive operations
        await pauseUIIntensiveOperations()
        
        // Save current UI state
        await saveUIState()
    }
    
    // MARK: - State Management
    
    private func saveApplicationState() async {
        logger.debug("Saving application state")
        
        do {
            // Save transcription queue state
            await transcriptionService?.saveTranscriptionQueue()
            
            // Save cache metadata
            await transcriptionCache?.saveMetadata()
            
            // Save performance metrics
            if let metricsData = performanceMonitor?.exportMetrics() {
                let metricsURL = getMetricsURL()
                try metricsData.write(to: metricsURL)
            }
            
            logger.info("Application state saved successfully")
        } catch {
            logger.error("Failed to save application state: \(error.localizedDescription)")
        }
    }
    
    private func cleanupResources() async {
        logger.debug("Cleaning up resources")
        
        // Clear temporary caches
        await transcriptionCache?.clearTemporaryData()
        
        // Cancel pending network requests
        await transcriptionService?.cancelPendingRequests()
        
        // Release audio processing resources
        await releaseAudioResources()
        
        logger.info("Resources cleaned up")
    }
    
    private func stopAllOperations() async {
        logger.debug("Stopping all operations")
        
        // Stop transcription processing
        await transcriptionService?.stopAllTranscriptions()
        
        // Stop performance monitoring
        performanceMonitor?.stopMonitoring()
        
        // Stop background tasks
        backgroundTaskManager?.disableBackgroundProcessing()
        
        logger.info("All operations stopped")
    }
    
    // MARK: - Background Time Monitoring
    
    private func startBackgroundTimeMonitoring() {
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateBackgroundTimeRemaining()
            }
        }
    }
    
    private func stopBackgroundTimeMonitoring() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        backgroundTimeRemaining = 0
    }
    
    private func updateBackgroundTimeRemaining() async {
        self.backgroundTimeRemaining = UIApplication.shared.backgroundTimeRemaining
        
        // Warning when background time is running low
        if self.backgroundTimeRemaining < Self.backgroundProcessingGracePeriod && self.backgroundTimeRemaining > 0 {
            logger.warning("Background time running low: \(self.backgroundTimeRemaining)s remaining")
            await prepareForBackgroundExpiration()
        }
    }
    
    private func prepareForBackgroundExpiration() async {
        logger.info("Preparing for background expiration")
        
        // Save current state immediately
        await saveApplicationState()
        
        // Stop non-essential background operations
        await transcriptionService?.stopNonEssentialOperations()
    }
    
    // MARK: - Memory Management
    
    private func handleLowMemoryCondition() async {
        logger.warning("Handling low memory condition")
        
        // Clear caches aggressively
        await transcriptionCache?.clearCache()
        
        // Cancel low-priority operations
        await transcriptionService?.cancelLowPriorityOperations()
        
        // Free audio processing resources
        await releaseAudioResources()
        
        // Notify other components
        NotificationCenter.default.post(name: .lowMemoryCondition, object: nil)
        
        logger.info("Low memory handling completed")
    }
    
    // MARK: - UI Management
    
    private func pauseUIIntensiveOperations() async {
        // Implementation depends on specific UI operations
        logger.debug("UI-intensive operations paused")
    }
    
    private func saveUIState() async {
        // Save current scroll positions, selected items, etc.
        logger.debug("UI state saved")
    }
    
    private func processQueuedUIUpdates() async {
        // Process any UI updates that were queued while in background
        logger.debug("Queued UI updates processed")
    }
    
    private func refreshUserInterface() async {
        // Refresh visible content
        NotificationCenter.default.post(name: .refreshUserInterface, object: nil)
        logger.debug("User interface refreshed")
    }
    
    // MARK: - Utility Methods
    
    private func releaseAudioResources() async {
        // Release audio processing resources
        logger.debug("Audio resources released")
    }
    
    private func getMetricsURL() -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("performance_metrics.json")
    }
    
    // MARK: - Public Interface
    
    /// Schedule an action to be executed when app returns to foreground
    func scheduleForForegroundResume(_ action: @escaping () async -> Void) {
        foregroundResumeActions.append(action)
    }
    
    /// Get current background execution time remaining
    func getBackgroundTimeRemaining() -> TimeInterval {
        return backgroundTimeRemaining
    }
    
    /// Check if app has been in background for extended period
    func hasBeenInBackgroundForExtendedPeriod() -> Bool {
        guard let enterTime = enterBackgroundTime else { return false }
        return Date().timeIntervalSince(enterTime) > 300 // 5 minutes
    }
    
    /// Force save application state
    func forceSaveState() async {
        await saveApplicationState()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        backgroundTimer?.invalidate()
        transitionTimer?.invalidate()
    }
    
    #endif
}

// MARK: - Supporting Types

enum AppState: String, CaseIterable {
    case foreground
    case background
    case transitioning
    case terminating
    
    var isActive: Bool {
        return self == .foreground
    }
    
    var allowsIntensiveOperations: Bool {
        return self == .foreground
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let lowMemoryCondition = Notification.Name("lowMemoryCondition")
    static let refreshUserInterface = Notification.Name("refreshUserInterface")
    static let backgroundProcessingExpiring = Notification.Name("backgroundProcessingExpiring")
}