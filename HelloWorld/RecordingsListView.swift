import SwiftUI

struct RecordingsListView: View {
    @StateObject private var recordingManager = RecordingManager()
    @State private var showingDeleteAlert = false
    @State private var recordingToDelete: Recording?
    @State private var searchText = ""
    @State private var isSearching = false
    
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
                    VStack {
                        if filteredRecordings.isEmpty && !searchText.isEmpty {
                            searchEmptyStateView
                        } else {
                            List {
                                ForEach(filteredRecordings) { recording in
                                    RecordingRowView(
                                        recording: recording, 
                                        recordingManager: recordingManager,
                                        searchText: searchText
                                    )
                                }
                                .onDelete(perform: deleteRecordings)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Recordings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    networkStatusIndicator
                }
            }
            .searchable(text: $searchText, isPresented: $isSearching, prompt: "Search transcriptions...")
            .onChange(of: searchText) { _ in
                // Trigger UI update when search text changes
            }
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
    
    // MARK: - Computed Properties
    
    @ViewBuilder
    private var networkStatusIndicator: some View {
        if let transcriptionService = recordingManager.transcriptionService {
            HStack(spacing: 4) {
                if !transcriptionService.isOnline {
                    Image(systemName: "wifi.slash")
                        .foregroundColor(.orange)
                        .font(.caption)
                    
                    if transcriptionService.offlineQueueCount > 0 {
                        Text("\(transcriptionService.offlineQueueCount)")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                } else if transcriptionService.isProcessingQueue {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        }
    }
    
    private var filteredRecordings: [Recording] {
        if searchText.isEmpty {
            return recordingManager.recordings
        }
        
        return recordingManager.recordings.filter { recording in
            // Only search through recordings that have transcriptions
            guard recording.hasTranscription,
                  let transcription = recording.transcription else {
                return false
            }
            
            return transcription.localizedCaseInsensitiveContains(searchText) ||
                   recording.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    @ViewBuilder
    private var searchEmptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Results Found")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("No transcriptions contain \"\(searchText)\"")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if recordingManager.recordings.contains(where: { !$0.hasTranscription }) {
                Text("Some recordings haven't been transcribed yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
    }
    
    // MARK: - Methods
    
    private func deleteRecordings(offsets: IndexSet) {
        for index in offsets {
            let recording = filteredRecordings[index]
            recordingToDelete = recording
            showingDeleteAlert = true
            break // Handle one at a time for confirmation
        }
    }
}

struct RecordingRowView: View {
    let recording: Recording
    let recordingManager: RecordingManager
    let searchText: String
    @State private var isPlaying = false
    @State private var showingCopyConfirmation = false
    @State private var showingTranscriptionDetail = false
    
    init(recording: Recording, recordingManager: RecordingManager, searchText: String = "") {
        self.recording = recording
        self.recordingManager = recordingManager
        self.searchText = searchText
    }
    
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
                if let transcriptionService = recordingManager.transcriptionService,
                   transcriptionService.isQueuedForOffline(recording) {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("Queued for when online")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("Queued for transcription")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        
        case .completed:
            if recording.hasTranscription {
                Button(action: {
                    showingTranscriptionDetail = true
                }) {
                    highlightedTranscriptionPreview
                        .font(.caption)
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
    
    // MARK: - Computed Properties
    
    @ViewBuilder
    private var highlightedTranscriptionPreview: some View {
        if searchText.isEmpty || !recording.hasTranscription {
            Text(recording.transcriptionPreview)
                .foregroundColor(.primary)
        } else {
            highlightedText(recording.transcriptionPreview, searchText: searchText)
        }
    }
    
    // MARK: - Helper Methods
    
    @ViewBuilder
    private func highlightedText(_ text: String, searchText: String) -> some View {
        let attributedString = createHighlightedAttributedString(text: text, searchText: searchText)
        
        #if os(iOS)
        Text(AttributedString(attributedString))
            .foregroundColor(.primary)
        #elseif os(macOS)
        Text(AttributedString(attributedString))
            .foregroundColor(.primary)
        #endif
    }
    
    private func createHighlightedAttributedString(text: String, searchText: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text)
        let range = NSRange(location: 0, length: text.count)
        
        // Set default text color
        #if os(iOS)
        attributedString.addAttribute(.foregroundColor, value: UIColor.label, range: range)
        #elseif os(macOS)
        attributedString.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        #endif
        
        // Find and highlight search matches
        let searchRange = text.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive])
        if let searchRange = searchRange {
            let nsRange = NSRange(searchRange, in: text)
            #if os(iOS)
            attributedString.addAttribute(.backgroundColor, value: UIColor.systemYellow, range: nsRange)
            attributedString.addAttribute(.foregroundColor, value: UIColor.black, range: nsRange)
            #elseif os(macOS)
            attributedString.addAttribute(.backgroundColor, value: NSColor.systemYellow, range: nsRange)
            attributedString.addAttribute(.foregroundColor, value: NSColor.black, range: nsRange)
            #endif
        }
        
        return attributedString
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