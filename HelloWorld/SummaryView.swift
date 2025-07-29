import SwiftUI

// MARK: - Summary View

struct SummaryView: View {
    let recording: Recording
    @ObservedObject var summaryManager: SummaryManager
    
    @State private var selectedType: SummaryType
    @State private var selectedLength: SummaryLength
    @State private var showingOptions: Bool = false
    @State private var showingCopyConfirmation: Bool = false
    @State private var isGenerating: Bool = false
    @State private var currentError: SummaryError?
    
    // Initialize with preferences
    init(recording: Recording, summaryManager: SummaryManager) {
        self.recording = recording
        self.summaryManager = summaryManager
        let preferences = summaryManager.getSummaryPreferences()
        self._selectedType = State(initialValue: preferences.defaultType)
        self._selectedLength = State(initialValue: preferences.defaultLength)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            summaryHeader
            
            // Content based on summary status
            summaryContent
            
            // Action buttons
            if recording.canSummarize {
                summaryActions
            }
        }
        .padding()
        .background(Color(red: 0.95, green: 0.95, blue: 0.97))
        .cornerRadius(12)
        .alert("Copied to Clipboard", isPresented: $showingCopyConfirmation) {
            Button("OK") { }
        } message: {
            Text("Summary has been copied to your clipboard.")
        }
        .alert("Summary Error", isPresented: .constant(currentError != nil)) {
            Button("OK") {
                currentError = nil
            }
            if currentError?.isRetryable == true {
                Button("Retry") {
                    Task {
                        await generateSummary(forceRegenerate: true)
                    }
                }
            }
        } message: {
            if let error = currentError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.localizedDescription)
                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingOptions) {
            SummaryOptionsView(
                selectedType: $selectedType,
                selectedLength: $selectedLength,
                recording: recording,
                summaryManager: summaryManager,
                onGenerate: {
                    showingOptions = false
                    Task {
                        await generateSummary(forceRegenerate: true)
                    }
                }
            )
        }
        .onReceive(summaryManager.$isGenerating) { generating in
            isGenerating = generating && summaryManager.currentRecordingId == recording.id
        }
    }
    
    // MARK: - Header
    
    @ViewBuilder
    private var summaryHeader: some View {
        HStack {
            Label("AI Summary", systemImage: "brain.head.profile")
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            if let summary = currentSummary {
                summaryMetadataBadge(summary)
            }
        }
    }
    
    @ViewBuilder
    private func summaryMetadataBadge(_ summary: Summary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: summary.aiProvider.icon)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(summary.aiProvider.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if summaryManager.getSummaryPreferences().showConfidenceLevel {
                confidenceBadge(summary.confidenceLevel)
            }
        }
    }
    
    @ViewBuilder
    private func confidenceBadge(_ confidence: ConfidenceLevel) -> some View {
        HStack(spacing: 2) {
            Image(systemName: confidence.icon)
                .font(.caption2)
            Text(confidence.displayName)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(confidence.color).opacity(0.2))
        .foregroundColor(Color(confidence.color))
        .cornerRadius(4)
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var summaryContent: some View {
        switch recording.summaryStatus {
        case .notStarted:
            if recording.canSummarize {
                notStartedView
            } else {
                cannotSummarizeView
            }
        case .inProgress:
            inProgressView
        case .queued:
            queuedView
        case .completed:
            if let summary = currentSummary {
                completedView(summary)
            } else {
                noSummaryView
            }
        case .failed:
            failedView
        }
    }
    
    @ViewBuilder
    private var notStartedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            
            Text("Generate AI Summary")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Create an intelligent summary of your transcription using AI")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if let cost = summaryManager.estimateCost(for: recording) {
                Text("Estimated cost: \(String(format: "$%.4f", cost))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private var cannotSummarizeView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            
            Text("Cannot Summarize")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("This transcription is too short for AI summarization (minimum 50 words required)")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text("Current: \(recording.transcriptionWordCount) words")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    @ViewBuilder
    private var inProgressView: some View {
        VStack(spacing: 16) {
            if isGenerating && summaryManager.currentProvider != nil {
                VStack(spacing: 8) {
                    ProgressView(value: summaryManager.progress)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    HStack {
                        if let provider = summaryManager.currentProvider {
                            HStack(spacing: 4) {
                                Image(systemName: provider.icon)
                                    .font(.caption)
                                Text("Using \(provider.displayName)")
                                    .font(.caption)
                            }
                            .foregroundColor(.blue)
                        }
                        
                        Spacer()
                        
                        Text("\(Int(summaryManager.progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                ProgressView()
                    .scaleEffect(1.2)
            }
            
            Text("Generating Summary...")
                .font(.headline)
                .foregroundColor(.blue)
            
            Text("Please wait while AI analyzes your transcription")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    @ViewBuilder
    private var queuedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            
            Text("Queued for Processing")
                .font(.headline)
                .foregroundColor(.orange)
            
            Text("Your summary request is queued and will be processed automatically when possible")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            let queueStatus = summaryManager.getQueueStatus()
            if queueStatus.pendingCount > 1 {
                Text("\(queueStatus.pendingCount - 1) other items ahead in queue")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private func completedView(_ summary: Summary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary type and length info
            HStack {
                Label(summary.type.displayName, systemImage: summary.type.icon)
                    .font(.subheadline)
                    .foregroundColor(.blue)
                
                Spacer()
                
                Text("\(summary.wordCount) words")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Summary text
            DynamicTypeReader { dynamicTypeSize in
                AnyView(
                    Text(summary.displayText)
                        .font(.system(size: dynamicTypeSize.transcriptionFontSize))
                        .textSelection(.enabled)
                        .lineSpacing(2)
                        .transcriptionAccessibility(
                            label: "AI Summary",
                            hint: "Double tap to select text for copying",
                            value: summary.displayText
                        )
                )
            }
            
            // Summary metadata
            summaryMetadata(summary)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var noSummaryView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            
            Text("No Summary Available")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("The summary completed but no content was generated")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    @ViewBuilder
    private var failedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.red)
            
            Text("Summary Failed")
                .font(.headline)
                .foregroundColor(.red)
            
            if let error = recording.summaryError {
                Text(error)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("An error occurred while generating the summary")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private func summaryMetadata(_ summary: Summary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Generated")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(summary.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                if summary.processingTime > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Processing Time")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1fs", summary.processingTime))
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    @ViewBuilder
    private var summaryActions: some View {
        HStack(spacing: 12) {
            // Generate/Regenerate button
            Button(action: {
                Task {
                    await generateSummary()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: currentSummary != nil ? "arrow.clockwise" : "brain.head.profile")
                    Text(currentSummary != nil ? "Regenerate" : "Generate Summary")
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue)
                .cornerRadius(8)
            }
            .disabled(isGenerating)
            .transcriptionActionAccessibility(
                action: currentSummary != nil ? .retry : .transcribe,
                isEnabled: !isGenerating
            )
            
            // Options button
            Button(action: {
                HapticFeedbackManager.shared.buttonPressed()
                showingOptions = true
            }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            .transcriptionAccessibility(
                label: "Summary options",
                hint: "Configure summary type and length"
            )
            
            Spacer()
            
            // Copy button (only if summary exists)
            if currentSummary != nil {
                Button(action: {
                    copySummaryToClipboard()
                }) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
                .transcriptionActionAccessibility(action: .copy)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var currentSummary: Summary? {
        return summaryManager.getSummary(
            for: recording.id,
            type: selectedType,
            length: selectedLength
        )
    }
    
    // MARK: - Methods
    
    private func generateSummary(forceRegenerate: Bool = false) async {
        do {
            let _ = try await summaryManager.generateSummary(
                for: recording,
                type: selectedType,
                length: selectedLength,
                forceRegenerate: forceRegenerate
            )
            currentError = nil
        } catch let error as SummaryError {
            currentError = error
        } catch {
            currentError = SummaryError.unknownError(error.localizedDescription)
        }
    }
    
    private func copySummaryToClipboard() {
        guard let summary = currentSummary else { return }
        
        #if os(iOS)
        UIPasteboard.general.string = summary.text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary.text, forType: .string)
        #endif
        
        HapticFeedbackManager.shared.textCopied()
        AccessibilityAnnouncementManager.shared.announceTextCopied()
        showingCopyConfirmation = true
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
        transcription: "This is a sample transcription text that demonstrates how the summary view will look when displaying actual transcribed content from an audio recording. It contains enough words to be eligible for summarization and shows various features of the summary interface.",
        transcriptionStatus: .completed
    )
    
    let networkMonitor = NetworkMonitor()
    let summaryManager = SummaryManager(networkMonitor: networkMonitor)
    
    SummaryView(recording: sampleRecording, summaryManager: summaryManager)
        .padding()
}