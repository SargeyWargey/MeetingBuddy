import SwiftUI

struct TranscriptionDetailView: View {
    let recording: Recording
    let recordingManager: RecordingManager
    
    @Environment(\.dismiss) private var dismiss
    @State private var showingCopyConfirmation = false
    @State private var isRetrying = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Recording Info Header
                    recordingInfoSection
                    
                    Divider()
                    
                    // Transcription Content
                    transcriptionContentSection
                    
                    // Metadata Section (only show if transcription exists)
                    if recording.hasTranscription {
                        Divider()
                        metadataSection
                    }
                }
                .padding()
            }
            .navigationTitle("Transcription")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if recording.hasTranscription {
                        Button(action: copyTranscriptionToClipboard) {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .accessibilityLabel("Copy transcription")
                    }
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if recording.hasTranscription {
                        Button(action: copyTranscriptionToClipboard) {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .accessibilityLabel("Copy transcription")
                    }
                }
                #endif
            }
        }
        .alert("Copied to Clipboard", isPresented: $showingCopyConfirmation) {
            Button("OK") { }
        } message: {
            Text("Transcription text has been copied to your clipboard.")
        }
    }
    
    // MARK: - Recording Info Section
    
    @ViewBuilder
    private var recordingInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recording.title)
                .font(.title2)
                .fontWeight(.semibold)
            
            HStack {
                Label(recording.durationString, systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Label(recording.fileSizeString, systemImage: "doc")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(recording.createdAt, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Transcription Content Section
    
    @ViewBuilder
    private var transcriptionContentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Transcription")
                    .font(.headline)
                
                Spacer()
                
                transcriptionStatusBadge
            }
            
            transcriptionContent
        }
    }
    
    @ViewBuilder
    private var transcriptionStatusBadge: some View {
        switch recording.transcriptionStatus {
        case .completed:
            if recording.hasTranscription {
                Label("Completed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Label("No Content", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        case .inProgress:
            Label("In Progress", systemImage: "clock")
                .font(.caption)
                .foregroundColor(.blue)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(.red)
        case .queued:
            Label("Queued", systemImage: "clock.badge")
                .font(.caption)
                .foregroundColor(.orange)
        case .notStarted:
            Label("Not Started", systemImage: "circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var transcriptionContent: some View {
        switch recording.transcriptionStatus {
        case .completed:
            if recording.hasTranscription {
                transcriptionTextView
            } else {
                emptyTranscriptionView
            }
        case .inProgress:
            inProgressView
        case .failed:
            failedTranscriptionView
        case .queued:
            queuedTranscriptionView
        case .notStarted:
            notStartedView
        }
    }
    
    @ViewBuilder
    private var transcriptionTextView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(recording.transcription ?? "")
                .font(.body)
                .textSelection(.enabled)
                .padding()
                .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                .cornerRadius(8)
            
            HStack {
                Button(action: copyTranscriptionToClipboard) {
                    Label("Copy Text", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: retryTranscription) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isRetrying)
            }
        }
    }
    
    @ViewBuilder
    private var emptyTranscriptionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("No Transcription Available")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("The transcription completed but no text was generated. This might happen with very quiet recordings or audio that doesn't contain speech.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: retryTranscription) {
                Label("Retry Transcription", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRetrying)
        }
        .padding()
    }
    
    @ViewBuilder
    private var inProgressView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Transcribing Audio...")
                .font(.headline)
                .foregroundColor(.blue)
            
            Text("Please wait while we convert your audio to text. This may take a few moments.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    @ViewBuilder
    private var failedTranscriptionView: some View {
        VStack(spacing: 16) {
            // Check if we have a specific error from the error handler
            let errorBanners = recordingManager.errorHandler?.getErrorBanners(for: recording.id) ?? []
            if let latestBanner = errorBanners.last {
                
                TranscriptionErrorView(
                    error: latestBanner.error,
                    recording: recording,
                    onAction: { action in
                        recordingManager.errorHandler?.processErrorAction(action, for: latestBanner.error, recordingId: recording.id)
                    },
                    onDismiss: {
                        recordingManager.errorHandler?.processErrorAction(.dismiss, for: latestBanner.error, recordingId: recording.id)
                    }
                )
                
            } else {
                // Fallback to generic error display
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
                
                Text("Transcription Failed")
                    .font(.headline)
                    .foregroundColor(.red)
                
                if let error = recording.transcriptionError {
                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("An error occurred while transcribing your audio. Please try again.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Button(action: retryTranscription) {
                    if isRetrying {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Retrying...")
                        }
                    } else {
                        Label("Retry Transcription", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRetrying)
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private var queuedTranscriptionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text("Queued for Transcription")
                .font(.headline)
                .foregroundColor(.orange)
            
            Text("Your recording is in the transcription queue and will be processed automatically when possible.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: retryTranscription) {
                Label("Process Now", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRetrying)
        }
        .padding()
    }
    
    @ViewBuilder
    private var notStartedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("Not Transcribed")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("This recording hasn't been transcribed yet. Tap the button below to start the transcription process.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: startTranscription) {
                if isRetrying {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Starting...")
                    }
                } else {
                    Label("Start Transcription", systemImage: "text.bubble")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRetrying)
        }
        .padding()
    }
    
    // MARK: - Metadata Section
    
    @ViewBuilder
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription Details")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                metadataRow(title: "Status", value: recording.transcriptionStatusDisplayText)
                
                if let lastAttempt = recording.lastTranscriptionAttempt {
                    metadataRow(title: "Last Attempt", value: formatDate(lastAttempt))
                }
                
                // Mock metadata - in a real implementation, this would come from TranscriptionResult
                if recording.hasTranscription {
                    metadataRow(title: "Method", value: "On-Device")
                    metadataRow(title: "Confidence", value: "95%")
                    metadataRow(title: "Processing Time", value: "2.3 seconds")
                    
                    if let transcription = recording.transcription {
                        let wordCount = transcription.components(separatedBy: .whitespacesAndNewlines)
                            .filter { !$0.isEmpty }.count
                        metadataRow(title: "Word Count", value: "\(wordCount) words")
                        metadataRow(title: "Character Count", value: "\(transcription.count) characters")
                    }
                }
            }
            .padding()
            .background(Color(red: 0.95, green: 0.95, blue: 0.97))
            .cornerRadius(8)
        }
    }
    
    @ViewBuilder
    private func metadataRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
            
            Spacer()
        }
    }
    
    // MARK: - Actions
    
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
    
    private func startTranscription() {
        isRetrying = true
        recordingManager.transcribeRecording(recording)
        
        // Reset the retrying state after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isRetrying = false
        }
    }
    
    private func retryTranscription() {
        isRetrying = true
        recordingManager.retryTranscription(recording)
        
        // Reset the retrying state after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isRetrying = false
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    let sampleRecording = Recording(
        fileName: "sample.m4a",
        url: URL(fileURLWithPath: "/tmp/sample.m4a"),
        createdAt: Date(),
        duration: 120.0,
        title: "Sample Recording",
        transcription: "This is a sample transcription text that demonstrates how the transcription detail view will look when displaying actual transcribed content from an audio recording.",
        transcriptionStatus: .completed,
        lastTranscriptionAttempt: Date()
    )
    
    TranscriptionDetailView(
        recording: sampleRecording,
        recordingManager: RecordingManager()
    )
}