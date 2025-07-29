import SwiftUI

struct RecordingsListView: View {
    @ObservedObject var recordingManager: RecordingManager
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
                ToolbarItem(placement: .primaryAction) {
                    networkStatusIndicator
                }
            }
            .searchable(text: $searchText, isPresented: $isSearching, prompt: "Search transcriptions and summaries...")
            .onChange(of: searchText) {
                // Trigger UI update when search text changes
                // Announce search results for accessibility
                if !searchText.isEmpty {
                    let resultCount = filteredRecordings.count
                    let message = resultCount == 0 ? "No search results found" : "\(resultCount) search result\(resultCount == 1 ? "" : "s") found"
                    AccessibilityAnnouncementManager.shared.announce(message)
                }
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
            .transcriptionErrorAlert(
                error: Binding<TranscriptionError?>(
                    get: { recordingManager.errorHandler?.currentError },
                    set: { recordingManager.errorHandler?.currentError = $0 }
                ),
                onAction: { action in
                    // Handle error actions - we need a recording ID, so we'll use a placeholder for now
                    // In a real implementation, we'd track which recording the error is for
                    if let errorHandler = recordingManager.errorHandler,
                       let currentError = errorHandler.currentError {
                        errorHandler.processErrorAction(action, for: currentError, recordingId: UUID())
                    }
                }
            )
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
                        .transcriptionAccessibility(
                            label: "Offline",
                            hint: "Device is offline, transcriptions will be queued"
                        )
                    
                    if transcriptionService.offlineQueueCount > 0 {
                        Text("\(transcriptionService.offlineQueueCount)")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                            .transcriptionAccessibility(
                                label: "\(transcriptionService.offlineQueueCount) queued",
                                hint: "Number of transcriptions waiting for network connection"
                            )
                    }
                } else if transcriptionService.isProcessingQueue {
                    ProgressView()
                        .scaleEffect(0.7)
                        .transcriptionAccessibility(
                            label: "Processing queue",
                            hint: "Transcriptions are being processed"
                        )
                }
            }
        }
    }
    
    private var filteredRecordings: [Recording] {
        if searchText.isEmpty {
            return recordingManager.recordings
        }
        
        return recordingManager.recordings.filter { recording in
            // Search through title first
            if recording.title.localizedCaseInsensitiveContains(searchText) {
                return true
            }
            
            // Search through transcription if available
            if recording.hasTranscription,
               let transcription = recording.transcription,
               transcription.localizedCaseInsensitiveContains(searchText) {
                return true
            }
            
            // Search through summary if available
            if recording.hasSummary,
               let summary = recording.summary,
               summary.text.localizedCaseInsensitiveContains(searchText) {
                return true
            }
            
            return false
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
            
            Text("No transcriptions or summaries contain \"\(searchText)\"")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if recordingManager.recordings.contains(where: { !$0.hasTranscription }) {
                Text("Some recordings haven't been transcribed yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
            
            if recordingManager.recordings.contains(where: { $0.hasTranscription && !$0.hasSummary }) {
                Text("Some transcriptions haven't been summarized yet")
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
                HapticFeedbackManager.shared.buttonPressed()
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
            .transcriptionAccessibility(
                label: isPlaying ? "Pause recording" : "Play recording",
                hint: "Plays or pauses the audio recording"
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.headline)
                    .lineLimit(1)
                    .transcriptionDynamicType()
                
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
                
                // Summary Section (only show if transcription exists and summary manager is available)
                if recording.hasTranscription, let summaryManager = recordingManager.summaryManager {
                    summarySection(summaryManager: summaryManager)
                }
            }
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: 8) {
                // Transcription Action Button
                transcriptionActionButton
                
                // Summary Action Button (only show if transcription exists and summary manager is available)
                if recording.hasTranscription, let summaryManager = recordingManager.summaryManager {
                    summaryActionButton(summaryManager: summaryManager)
                }
            }
        }
        .padding(.vertical, 4)
        .onLongPressGesture {
            copyTranscriptionToClipboard()
        }
        .accessibilityAction(named: "Copy transcription") {
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
                    .transcriptionDynamicType()
            }
            .transcriptionStatusAccessibility(status: recording.transcriptionStatus)
        
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
                        .transcriptionDynamicType()
                } else {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("Queued for transcription")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .transcriptionDynamicType()
                }
            }
            .transcriptionStatusAccessibility(status: recording.transcriptionStatus)
        
        case .completed:
            if recording.hasTranscription {
                Button(action: {
                    HapticFeedbackManager.shared.buttonPressed()
                    showingTranscriptionDetail = true
                }) {
                    highlightedTranscriptionPreview
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .transcriptionDynamicType()
                }
                .buttonStyle(PlainButtonStyle())
                .transcriptionActionAccessibility(action: .view)
            } else {
                Text("No transcription available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        
        case .failed:
            VStack(alignment: .leading, spacing: 4) {
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
                
                // Show compact error view if there are error banners for this recording
                let errorBanners = recordingManager.errorHandler?.getErrorBanners(for: recording.id) ?? []
                if let latestBanner = errorBanners.last {
                    CompactTranscriptionErrorView(
                        error: latestBanner.error,
                        onRetry: {
                            recordingManager.errorHandler?.processErrorAction(.retry, for: latestBanner.error, recordingId: recording.id)
                        },
                        onDismiss: {
                            recordingManager.errorHandler?.processErrorAction(.dismiss, for: latestBanner.error, recordingId: recording.id)
                        }
                    )
                }
            }
        }
    }
    
    @ViewBuilder
    private var transcriptionActionButton: some View {
        switch recording.transcriptionStatus {
        case .notStarted, .failed:
            Button(action: {
                HapticFeedbackManager.shared.buttonPressed()
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
            .transcriptionActionAccessibility(
                action: recording.transcriptionStatus == .failed ? .retry : .transcribe
            )
        
        case .inProgress, .queued:
            ProgressView()
                .scaleEffect(0.8)
        
        case .completed:
            if recording.hasTranscription {
                Button(action: {
                    HapticFeedbackManager.shared.buttonPressed()
                    showingTranscriptionDetail = true
                }) {
                    Image(systemName: "text.bubble.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .transcriptionActionAccessibility(action: .view)
            } else {
                Button(action: {
                    HapticFeedbackManager.shared.buttonPressed()
                    showingTranscriptionDetail = true
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .transcriptionActionAccessibility(action: .retry)
            }
        }
    }
    
    // MARK: - Summary Section
    
    @ViewBuilder
    private func summarySection(summaryManager: SummaryManager) -> some View {
        switch recording.summaryStatus {
        case .notStarted:
            if recording.canSummarize {
                Text("Tap to generate AI summary")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .italic()
            } else {
                Text("Transcription too short for summary")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        
        case .inProgress:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Generating summary...")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .transcriptionDynamicType()
            }
            .transcriptionStatusAccessibility(status: recording.transcriptionStatus)
        
        case .queued:
            HStack(spacing: 4) {
                Image(systemName: "clock.badge")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("Queued for summary")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .transcriptionDynamicType()
            }
            .transcriptionStatusAccessibility(status: recording.transcriptionStatus)
        
        case .completed:
            if recording.hasSummary {
                Button(action: {
                    HapticFeedbackManager.shared.buttonPressed()
                    showingTranscriptionDetail = true
                }) {
                    highlightedSummaryPreview(summaryText: recording.summaryPreview)
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .transcriptionDynamicType()
                }
                .buttonStyle(PlainButtonStyle())
                .transcriptionActionAccessibility(action: .view)
            } else {
                Text("No summary available")
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
                    Text("Summary failed - tap to retry")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    @ViewBuilder
    private func summaryActionButton(summaryManager: SummaryManager) -> some View {
        switch recording.summaryStatus {
        case .notStarted:
            if recording.canSummarize {
                Button(action: {
                    HapticFeedbackManager.shared.buttonPressed()
                    generateSummary(summaryManager: summaryManager)
                }) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .transcriptionAccessibility(
                    label: "Generate summary",
                    hint: "Generate AI summary of transcription"
                )
            }
        
        case .failed:
            Button(action: {
                HapticFeedbackManager.shared.buttonPressed()
                generateSummary(summaryManager: summaryManager, forceRegenerate: true)
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            .transcriptionActionAccessibility(action: .retry)
        
        case .inProgress, .queued:
            ProgressView()
                .scaleEffect(0.6)
        
        case .completed:
            if recording.hasSummary {
                Button(action: {
                    HapticFeedbackManager.shared.buttonPressed()
                    showingTranscriptionDetail = true
                }) {
                    Image(systemName: "brain.head.profile.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .transcriptionActionAccessibility(action: .view)
            } else {
                Button(action: {
                    HapticFeedbackManager.shared.buttonPressed()
                    generateSummary(summaryManager: summaryManager, forceRegenerate: true)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .transcriptionActionAccessibility(action: .retry)
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
    
    @ViewBuilder
    private func highlightedSummaryPreview(summaryText: String) -> some View {
        if searchText.isEmpty {
            Text(summaryText)
                .foregroundColor(.primary)
        } else {
            highlightedText(summaryText, searchText: searchText)
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
        
        HapticFeedbackManager.shared.textCopied()
        AccessibilityAnnouncementManager.shared.announceTextCopied()
        showingCopyConfirmation = true
    }
    
    private func generateSummary(summaryManager: SummaryManager, forceRegenerate: Bool = false) {
        Task {
            do {
                let _ = try await summaryManager.generateSummary(
                    for: recording,
                    forceRegenerate: forceRegenerate
                )
            } catch {
                // Error handling - could show an alert or update UI state
                print("Failed to generate summary: \(error)")
            }
        }
    }
}