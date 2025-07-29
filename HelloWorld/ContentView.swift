//
//  ContentView.swift
//  HelloWorld
//
//  Created by Joshua Sargent on 7/27/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var recordingManager = RecordingManager()
    
    // Performance optimization components from environment
    @EnvironmentObject var appLifecycleHandler: AppLifecycleHandler
    @EnvironmentObject var backgroundTaskManager: BackgroundTaskManager
    @EnvironmentObject var performanceMonitor: TranscriptionPerformanceMonitor
    @EnvironmentObject var uiThreadOptimizer: UIThreadOptimizer
    
    var body: some View {
        TabView {
            RecordingView(recordingManager: recordingManager)
                .tabItem {
                    Image(systemName: "mic.circle")
                    Text("Record")
                }
            
            RecordingsListView(recordingManager: recordingManager)
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Recordings")
                }
        }
        .onAppear {
            configurePerformanceOptimization()
        }
#if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            handleAppBecameActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            handleAppWillResignActive()
        }
#elseif canImport(AppKit)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            handleAppBecameActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            handleAppWillResignActive()
        }
#endif
    }
    
    // MARK: - Performance Optimization Configuration
    
    private func configurePerformanceOptimization() {
        Task { @MainActor in
            // Configure RecordingManager with performance components
            recordingManager.configurePerformanceOptimization(
                performanceMonitor: performanceMonitor,
                uiThreadOptimizer: uiThreadOptimizer
            )
            
            // Configure app lifecycle handler when transcription service is available
            if let transcriptionService = recordingManager.transcriptionService {
                // This would be called once the transcription service is properly initialized
                // For now, we'll set up the basic structure
                setupLifecycleIntegration(transcriptionService: transcriptionService)
            }
            
            print("Performance optimization configured in ContentView")
        }
    }
    
    private func setupLifecycleIntegration(transcriptionService: TranscriptionService) {
        // This method would configure the app lifecycle handler with all services
        // Currently commented out as it requires proper initialization order
        
        // appLifecycleHandler.configure(
        //     transcriptionService: transcriptionService,
        //     backgroundTaskManager: backgroundTaskManager,
        //     performanceMonitor: performanceMonitor,
        //     transcriptionCache: transcriptionCache
        // )
    }
    
    private func handleAppBecameActive() {
        Task { @MainActor in
            // Resume performance monitoring
            performanceMonitor.startMonitoring()
            
            // Process any queued transcriptions
            recordingManager.processTranscriptionQueue()
            
            print("App became active - performance optimization resumed")
        }
    }
    
    private func handleAppWillResignActive() {
        Task { @MainActor in
            // Prepare for background state
            await appLifecycleHandler.forceSaveState()
            
            print("App will resign active - state saved")
        }
    }
}

#Preview {
    ContentView()
}
