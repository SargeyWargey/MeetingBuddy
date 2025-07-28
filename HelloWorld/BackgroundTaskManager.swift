import Foundation
#if canImport(UIKit)
import UIKit
import BackgroundTasks
#endif

/// Manages background task execution for transcription processing
@MainActor
class BackgroundTaskManager: ObservableObject {
    
    #if !canImport(UIKit)
    // macOS fallback implementation
    @Published private(set) var isBackgroundProcessingEnabled = false
    @Published private(set) var activeBackgroundTasks: Set<Int> = []
    
    private weak var transcriptionService: TranscriptionService?
    
    init() {
        // No-op on macOS
    }
    
    func setTranscriptionService(_ service: TranscriptionService) {
        self.transcriptionService = service
    }
    
    func scheduleBackgroundProcessing() {
        // No-op on macOS
    }
    
    func scheduleBackgroundRefresh() {
        // No-op on macOS
    }
    
    func enableBackgroundProcessing() {
        isBackgroundProcessingEnabled = true
    }
    
    func disableBackgroundProcessing() {
        isBackgroundProcessingEnabled = false
    }
    
    #else
    // iOS implementation
    
    // MARK: - Constants
    
    private static let backgroundProcessingIdentifier = "com.sargeywar.HelloWorld.transcription.processing"
    private static let backgroundRefreshIdentifier = "com.sargeywar.HelloWorld.transcription.refresh"
    
    // MARK: - Published Properties
    
    @Published private(set) var isBackgroundProcessingEnabled = false
    @Published private(set) var activeBackgroundTasks: Set<UIBackgroundTaskIdentifier> = []
    
    // MARK: - Private Properties
    
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    private weak var transcriptionService: TranscriptionService?
    
    // MARK: - Initialization
    
    init() {
        registerBackgroundTasks()
        setupAppLifecycleNotifications()
    }
    
    // MARK: - Background Task Registration
    
    private func registerBackgroundTasks() {
        // Register background processing task for long-running transcription
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundProcessingIdentifier,
            using: nil
        ) { [weak self] task in
            Task {
                await self?.handleBackgroundProcessing(task: task as! BGProcessingTask)
            }
        }
        
        // Register background app refresh for quick transcription updates
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundRefreshIdentifier,
            using: nil
        ) { [weak self] task in
            Task {
                await self?.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
            }
        }
    }
    
    // MARK: - Background Task Execution
    
    private func handleBackgroundProcessing(task: BGProcessingTask) async {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        guard let transcriptionService = transcriptionService else {
            task.setTaskCompleted(success: false)
            return
        }
        
        do {
            // Process queued transcriptions in background
            let success = await transcriptionService.processQueuedTranscriptions(maxProcessingTime: 25.0)
            task.setTaskCompleted(success: success)
            
            // Schedule next background processing if queue has items
            if await transcriptionService.hasQueuedItems() {
                scheduleBackgroundProcessing()
            }
        } catch {
            print("Background processing failed: \(error)")
            task.setTaskCompleted(success: false)
        }
    }
    
    private func handleBackgroundRefresh(task: BGAppRefreshTask) async {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        guard let transcriptionService = transcriptionService else {
            task.setTaskCompleted(success: false)
            return
        }
        
        do {
            // Quick refresh of transcription status
            await transcriptionService.refreshTranscriptionStatus()
            task.setTaskCompleted(success: true)
        } catch {
            print("Background refresh failed: \(error)")
            task.setTaskCompleted(success: false)
        }
    }
    
    // MARK: - Background Task Scheduling
    
    func scheduleBackgroundProcessing() {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundProcessingIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60) // Wait at least 1 minute
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background processing task scheduled")
        } catch {
            print("Failed to schedule background processing: \(error)")
        }
    }
    
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30) // Wait at least 30 seconds
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background refresh task scheduled")
        } catch {
            print("Failed to schedule background refresh: \(error)")
        }
    }
    
    // MARK: - App Lifecycle Integration
    
    private func setupAppLifecycleNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        Task { @MainActor in
            await startBackgroundTask()
            scheduleBackgroundProcessing()
        }
    }
    
    @objc private func appWillEnterForeground() {
        Task { @MainActor in
            await endBackgroundTask()
            // Cancel scheduled background tasks since app is active
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundProcessingIdentifier)
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundRefreshIdentifier)
        }
    }
    
    @objc private func appWillTerminate() {
        Task { @MainActor in
            await endBackgroundTask()
            await transcriptionService?.saveTranscriptionQueue()
        }
    }
    
    // MARK: - Immediate Background Task Management
    
    private func startBackgroundTask() async {
        backgroundTaskIdentifier = await UIApplication.shared.beginBackgroundTask(withName: "TranscriptionProcessing") { [weak self] in
            Task { @MainActor [weak self] in
                await self?.endBackgroundTask()
            }
        }
        
        if backgroundTaskIdentifier != .invalid {
            activeBackgroundTasks.insert(backgroundTaskIdentifier)
            
            // Process transcriptions for remaining background time
            if let transcriptionService = transcriptionService {
                let remainingTime = await UIApplication.shared.backgroundTimeRemaining
                let maxProcessingTime = max(remainingTime - 5.0, 0) // Leave 5 seconds buffer
                
                _ = await transcriptionService.processQueuedTranscriptions(maxProcessingTime: maxProcessingTime)
            }
            
            await endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() async {
        if backgroundTaskIdentifier != .invalid {
            activeBackgroundTasks.remove(backgroundTaskIdentifier)
            await UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
    }
    
    // MARK: - Service Integration
    
    func setTranscriptionService(_ service: TranscriptionService) {
        self.transcriptionService = service
    }
    
    // MARK: - Public Interface
    
    func enableBackgroundProcessing() {
        isBackgroundProcessingEnabled = true
    }
    
    func disableBackgroundProcessing() {
        isBackgroundProcessingEnabled = false
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundProcessingIdentifier)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundRefreshIdentifier)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        Task { @MainActor [backgroundTaskIdentifier] in
            if backgroundTaskIdentifier != .invalid {
                await UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            }
        }
    }
    
    #endif
}