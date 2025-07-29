import SwiftUI

// MARK: - Summary Options View

struct SummaryOptionsView: View {
    @Binding var selectedType: SummaryType
    @Binding var selectedLength: SummaryLength
    let recording: Recording
    let summaryManager: SummaryManager
    let onGenerate: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProvider: AIProvider?
    @State private var showCostEstimate: Bool = true
    @State private var saveAsDefaults: Bool = false
    
    private var preferences: SummaryPreferences {
        summaryManager.getSummaryPreferences()
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Summary Type Selection
                    summaryTypeSection
                    
                    Divider()
                    
                    // Summary Length Selection
                    summaryLengthSection
                    
                    Divider()
                    
                    // AI Provider Selection
                    aiProviderSection
                    
                    Divider()
                    
                    // Cost Estimation
                    if showCostEstimate {
                        costEstimationSection
                    }
                    
                    Divider()
                    
                    // Options
                    optionsSection
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Summary Options")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Generate") {
                        generateWithOptions()
                    }
                    .fontWeight(.semibold)
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Generate") {
                        generateWithOptions()
                    }
                    .fontWeight(.semibold)
                }
                #endif
            }
        }
        .onAppear {
            selectedProvider = preferences.preferredProvider
        }
    }
    
    // MARK: - Summary Type Section
    
    @ViewBuilder
    private var summaryTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary Type")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Choose the format and style of your summary")
                .font(.caption)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(SummaryType.allCases) { type in
                    summaryTypeCard(type)
                }
            }
        }
    }
    
    @ViewBuilder
    private func summaryTypeCard(_ type: SummaryType) -> some View {
        Button(action: {
            HapticFeedbackManager.shared.buttonPressed()
            selectedType = type
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: type.icon)
                        .font(.title3)
                        .foregroundColor(selectedType == type ? .white : .blue)
                    
                    Spacer()
                    
                    if selectedType == type {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
                
                Text(type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(selectedType == type ? .white : .primary)
                
                Text(type.description)
                    .font(.caption)
                    .foregroundColor(selectedType == type ? .white.opacity(0.8) : .secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedType == type ? Color.blue : Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .transcriptionAccessibility(
            label: type.displayName,
            hint: type.description,
            traits: selectedType == type ? [.isButton, .isSelected] : .isButton
        )
    }
    
    // MARK: - Summary Length Section
    
    @ViewBuilder
    private var summaryLengthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary Length")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Select the desired length of your summary")
                .font(.caption)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                ForEach(SummaryLength.allCases) { length in
                    summaryLengthRow(length)
                }
            }
        }
    }
    
    @ViewBuilder
    private func summaryLengthRow(_ length: SummaryLength) -> some View {
        Button(action: {
            HapticFeedbackManager.shared.buttonPressed()
            selectedLength = length
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(length.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(length.wordRange)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if selectedLength == length {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
            .padding(12)
            .background(selectedLength == length ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .transcriptionAccessibility(
            label: "\(length.displayName) summary",
            hint: "Approximately \(length.wordRange)",
            traits: selectedLength == length ? [.isButton, .isSelected] : .isButton
        )
    }
    
    // MARK: - AI Provider Section
    
    @ViewBuilder
    private var aiProviderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Provider")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Choose which AI service to use for summarization")
                .font(.caption)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                // Auto-select option
                providerRow(
                    title: "Auto-Select",
                    description: "Automatically choose the best provider",
                    icon: "wand.and.stars",
                    isSelected: selectedProvider == nil,
                    isAvailable: true
                ) {
                    selectedProvider = nil
                }
                
                // Available providers
                ForEach(AIProvider.allCases.filter { $0.isAvailable }) { provider in
                    providerRow(
                        title: provider.displayName,
                        description: provider.description,
                        icon: provider.icon,
                        isSelected: selectedProvider == provider,
                        isAvailable: isProviderAvailable(provider)
                    ) {
                        selectedProvider = provider
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func providerRow(
        title: String,
        description: String,
        icon: String,
        isSelected: Bool,
        isAvailable: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            if isAvailable {
                HapticFeedbackManager.shared.buttonPressed()
                action()
            }
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(isAvailable ? (isSelected ? .blue : .primary) : .secondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(isAvailable ? .primary : .secondary)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                if !isAvailable {
                    Text("Unavailable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .disabled(!isAvailable)
        .transcriptionAccessibility(
            label: title,
            hint: description,
            traits: isSelected ? [.isButton, .isSelected] : .isButton
        )
    }
    
    // MARK: - Cost Estimation Section
    
    @ViewBuilder
    private var costEstimationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cost Estimation")
                .font(.headline)
                .foregroundColor(.primary)
            
            if let cost = estimatedCost {
                if cost > 0 {
                    HStack {
                        Image(systemName: "dollarsign.circle")
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Estimated Cost")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            
                            Text(String(format: "$%.4f", cost))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("Per summary")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        
                        Text("Free (On-Device Processing)")
                            .font(.subheadline)
                            .foregroundColor(.green)
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            } else {
                HStack {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.orange)
                    
                    Text("Cost estimation unavailable")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    
                    Spacer()
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Usage stats for OpenAI
            if selectedProvider == .openAI || selectedProvider == nil {
                let stats = summaryManager.getOpenAIUsageStats()
                if stats.dailyTokens > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today's Usage")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("\(stats.dailyTokens) tokens")
                                .font(.caption)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Text(stats.formattedCost)
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
    
    // MARK: - Options Section
    
    @ViewBuilder
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Options")
                .font(.headline)
                .foregroundColor(.primary)
            
            Toggle("Save as default preferences", isOn: $saveAsDefaults)
                .font(.subheadline)
                .transcriptionAccessibility(
                    label: "Save as default preferences",
                    hint: "Use these settings for future summaries"
                )
        }
    }
    
    // MARK: - Computed Properties
    
    private var estimatedCost: Double? {
        let provider = selectedProvider ?? selectOptimalProvider()
        return summaryManager.estimateCost(for: recording, provider: provider)
    }
    
    // MARK: - Methods
    
    private func isProviderAvailable(_ provider: AIProvider) -> Bool {
        switch provider {
        case .openAI:
            return summaryManager.getOpenAIUsageStats().dailyTokens < 10000 // Arbitrary limit
        case .onDevice:
            return true
        case .claude:
            return false
        }
    }
    
    private func selectOptimalProvider() -> AIProvider {
        // Simple logic to select optimal provider
        if !recording.canSummarize {
            return .onDevice
        }
        
        let wordCount = recording.transcriptionWordCount
        
        // For very long transcriptions, prefer on-device to save costs
        if wordCount > 1000 {
            return .onDevice
        }
        
        // For bullet points and key insights, prefer OpenAI
        if selectedType == .bulletPoints || selectedType == .keyInsights {
            return isProviderAvailable(.openAI) ? .openAI : .onDevice
        }
        
        // Default to OpenAI if available, otherwise on-device
        return isProviderAvailable(.openAI) ? .openAI : .onDevice
    }
    
    private func generateWithOptions() {
        // Save preferences if requested
        if saveAsDefaults {
            let newPreferences = SummaryPreferences(
                defaultType: selectedType,
                defaultLength: selectedLength,
                preferredProvider: selectedProvider,
                autoGenerateOnTranscription: preferences.autoGenerateOnTranscription,
                showConfidenceLevel: preferences.showConfidenceLevel,
                enableNotifications: preferences.enableNotifications
            )
            summaryManager.updateSummaryPreferences(newPreferences)
        }
        
        HapticFeedbackManager.shared.buttonPressed()
        onGenerate()
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
        transcription: "This is a sample transcription text that demonstrates how the summary options view will look when configuring summary generation parameters.",
        transcriptionStatus: .completed
    )
    
    let networkMonitor = NetworkMonitor()
    let summaryManager = SummaryManager(networkMonitor: networkMonitor)
    
    SummaryOptionsView(
        selectedType: .constant(.brief),
        selectedLength: .constant(.medium),
        recording: sampleRecording,
        summaryManager: summaryManager,
        onGenerate: {}
    )
}