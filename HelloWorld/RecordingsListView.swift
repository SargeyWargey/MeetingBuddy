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
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}