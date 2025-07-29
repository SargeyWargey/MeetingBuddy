//
//  HelloWorldApp.swift
//  HelloWorld
//
//  Created by Joshua Sargent on 7/27/25.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
import BackgroundTasks
#endif

@main
struct HelloWorldApp: App {
    
    // MARK: - Performance Optimization Components
    
    @StateObject private var appLifecycleHandler = AppLifecycleHandler()
    @StateObject private var backgroundTaskManager = BackgroundTaskManager()
    @StateObject private var performanceMonitor = TranscriptionPerformanceMonitor()
    @StateObject private var uiThreadOptimizer = UIThreadOptimizer()
    
    // Cache and memory management
    private let transcriptionCache: TranscriptionCache
    private let audioMemoryManager = AudioMemoryManager()
    
    // MARK: - Initialization
    
    init() {
        // Initialize cache with error handling
        do {
            transcriptionCache = try TranscriptionCache()
        } catch {
            print("Failed to initialize transcription cache: \(error)")
            // Create a fallback cache or handle gracefully
            transcriptionCache = try! TranscriptionCache()
        }
        
        // Configure background tasks for iOS
        #if canImport(UIKit)
        configureBackgroundTasks()
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appLifecycleHandler)
                .environmentObject(backgroundTaskManager)
                .environmentObject(performanceMonitor)
                .environmentObject(uiThreadOptimizer)
                .onAppear {
                    setupPerformanceOptimization()
                }
#if canImport(UIKit)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    handleAppTermination()
                }
#elseif canImport(AppKit)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    handleAppTermination()
                }
#endif
        }
    }
    
    // MARK: - Performance Optimization Setup
    
    private func setupPerformanceOptimization() {
        Task { @MainActor in
            // Start performance monitoring
            performanceMonitor.startMonitoring()
            
            // Configure app lifecycle handler with all services
            // Note: This would need to be updated when TranscriptionService is available
            // For now, we'll set up the structure
            setupLifecycleIntegration()
            
            print("Performance optimization components initialized")
        }
    }
    
    private func setupLifecycleIntegration() {
        // This method would be called once TranscriptionService is available
        // It would configure the app lifecycle handler with all necessary services
        
        // Example of how it would work:
        // appLifecycleHandler.configure(
        //     transcriptionService: transcriptionService,
        //     backgroundTaskManager: backgroundTaskManager,
        //     performanceMonitor: performanceMonitor,
        //     transcriptionCache: transcriptionCache
        // )
    }
    
    private func handleAppTermination() {
        Task { @MainActor in
            // Force save all state before termination
            await appLifecycleHandler.forceSaveState()
            
            // Stop performance monitoring
            performanceMonitor.stopMonitoring()
            
            // Clear memory resources
            audioMemoryManager.clearAll()
            
            print("App termination cleanup completed")
        }
    }
    
    // MARK: - Background Task Configuration (iOS only)
    
    #if canImport(UIKit)
    private func configureBackgroundTasks() {
        // Background tasks are registered in BackgroundTaskManager
        // This ensures they're set up before the app launches
    }
    #endif
}
