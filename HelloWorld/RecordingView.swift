import SwiftUI

struct RecordingView: View {
    @StateObject private var recordingManager = RecordingManager()
    @State private var showingPermissionDenied = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
                Spacer()
                
                // Recording Time Display
                VStack(spacing: 8) {
                    Text("Recording Time")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text(recordingManager.formattedCurrentTime)
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                // Recording Button
                Button(action: {
                    if recordingManager.isRecording {
                        recordingManager.stopRecording()
                    } else {
                        if recordingManager.hasPermission {
                            recordingManager.startRecording()
                        } else {
                            showingPermissionDenied = true
                        }
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(recordingManager.isRecording ? Color.red : Color.blue)
                            .frame(width: 120, height: 120)
                            .shadow(radius: 8)
                        
                        if recordingManager.isRecording {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .frame(width: 40, height: 40)
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        }
                    }
                }
                .scaleEffect(recordingManager.isRecording ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: recordingManager.isRecording)
                
                // Status Text
                Text(recordingManager.isRecording ? "Recording..." : "Tap to Record")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Recording Count
                if !recordingManager.recordings.isEmpty {
                    Text("\(recordingManager.recordings.count) recordings saved")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .navigationTitle("Voice Recorder")
            .alert("Microphone Permission Denied", isPresented: $showingPermissionDenied) {
                Button("Settings") {
                    #if os(iOS)
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                    #else
                    // On macOS, open System Preferences
                    if let settingsUrl = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(settingsUrl)
                    }
                    #endif
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Please enable microphone access in Settings to record audio.")
            }
            .alert("Error", isPresented: .constant(recordingManager.errorMessage != nil)) {
                Button("OK") {
                    recordingManager.errorMessage = nil
                }
            } message: {
                if let errorMessage = recordingManager.errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }
}