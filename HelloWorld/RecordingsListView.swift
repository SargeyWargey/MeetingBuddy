import SwiftUI

struct RecordingsListView: View {
    @StateObject private var recordingManager = RecordingManager()
    @State private var showingDeleteAlert = false
    @State private var recordingToDelete: Recording?
    
    var body: some View {
        NavigationView {
            Group {
                if recordingManager.recordings.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "waveform")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Recordings Yet")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        Text("Your recordings will appear here")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach(recordingManager.recordings) { recording in
                            RecordingRowView(recording: recording, recordingManager: recordingManager)
                        }
                        .onDelete(perform: deleteRecordings)
                    }
                }
            }
            .navigationTitle("Recordings")
            .alert("Delete Recording", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let recording = recordingToDelete {
                        recordingManager.deleteRecording(recording)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete this recording? This action cannot be undone.")
            }
        }
    }
    
    private func deleteRecordings(offsets: IndexSet) {
        for index in offsets {
            let recording = recordingManager.recordings[index]
            recordingToDelete = recording
            showingDeleteAlert = true
            break // Handle one at a time for confirmation
        }
    }
}

struct RecordingRowView: View {
    let recording: Recording
    let recordingManager: RecordingManager
    @State private var isPlaying = false
    @State private var showingCopyConfirmation = false
    @State private var showingTranscriptionDetail = false
    
    var body: some View {
        HStack {
            // Play/Pause Button
            Button(action: {
                if isPlaying {
                    recordingManager.stopPlayback()
                    isPlaying = false
                } else {
                    recordingManager.playRecording(recording)
                    isPlaying = true
                }
            }) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack {
                    Text(recording.durationString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(recording.fileSizeString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(recording.createdAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Transcription Section
                transcriptionSection
            }
            
            Spacer()
            
            // Transcription Action Button
            transcriptionActionButton
        }
        .padding(.vertical, 4)
        .onLongPressGesture {
            copyTranscriptionToClipboard()
        }
        .alert("Copied to Clipboard", isPresented: $showingCopyConfirmation) {
            Button("OK") { }
        } message: {
            Text("Transcription text has been copied to your clipboard.")
        }
        .sheet(isPresented: $showingTranscriptionDetail) {
            TranscriptionDetailView(recording: recording, recordingManager: recordingManager)
        }
    }
    
    @ViewBuilder
    private var transcriptionSection: some View {
        switch recording.transcriptionStatus {
        case .notStarted:
            Text("Tap to transcribe")
                .font(.caption)
                .foregroundColor(.blue)
                .italic()
        
        case .inProgress:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Transcribing...")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        
        case .queued:
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("Queued for transcription")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        
        case .completed:
            if recording.hasTranscription {
                Button(action: {
                    showingTranscriptionDetail = true
                }) {
                    Text(recording.transcriptionPreview)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Text("No transcription available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        
        case .failed:
            Button(action: {
                showingTranscriptionDetail = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text("Transcription failed - tap to view details")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    @ViewBuilder
    private var transcriptionActionButton: some View {
        switch recording.transcriptionStatus {
        case .notStarted, .failed:
            Button(action: {
                if recording.transcriptionStatus == .failed {
                    recordingManager.retryTranscription(recording)
                } else {
                    recordingManager.transcribeRecording(recording)
                }
            }) {
                Image(systemName: recording.transcriptionStatus == .failed ? "arrow.clockwise" : "text.bubble")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(recording.transcriptionStatus == .failed ? "Retry transcription" : "Transcribe recording")
        
        case .inProgress, .queued:
            ProgressView()
                .scaleEffect(0.8)
        
        case .completed:
            if recording.hasTranscription {
                Button(action: {
                    showingTranscriptionDetail = true
                }) {
                    Image(systemName: "text.bubble.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("View transcription")
            } else {
                Button(action: {
                    showingTranscriptionDetail = true
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Retry transcription")
            }
        }
    }
    
    private func copyTranscriptionToClipboard() {
        guard recording.hasTranscription, let transcription = recording.transcription else {
            return
        }
        
        #if os(iOS)
        UIPasteboard.general.string = transcription
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcription, forType: .string)
        #endif
        
        showingCopyConfirmation = true
    }
}