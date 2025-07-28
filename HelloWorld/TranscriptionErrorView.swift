import SwiftUI
#if os(macOS)
import AppKit
#endif

/// A comprehensive error view for transcription errors with actionable recovery options
struct TranscriptionErrorView: View {
    let error: TranscriptionError
    let recording: Recording
    let onAction: (ErrorAction) -> Void
    let onDismiss: () -> Void
    
    @State private var isPerformingAction = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Error Icon
            errorIcon
            
            // Error Title and Description
            errorContent
            
            // Action Buttons
            actionButtons
        }
        .padding(24)
        .background(backgroundColorForPlatform)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(errorBorderColor, lineWidth: 1)
        )
    }
    
    // MARK: - Error Icon
    
    @ViewBuilder
    private var errorIcon: some View {
        ZStack {
            Circle()
                .fill(errorBackgroundColor)
                .frame(width: 60, height: 60)
            
            Image(systemName: error.iconName)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(errorForegroundColor)
        }
    }
    
    // MARK: - Error Content
    
    @ViewBuilder
    private var errorContent: some View {
        VStack(spacing: 12) {
            Text(error.errorDescription ?? "Transcription Error")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            
            Text(error.detailedDescription)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.callout)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .foregroundColor(errorForegroundColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(errorBackgroundColor.opacity(0.2))
                    .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Action Buttons
    
    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Primary Action Button
            if let primaryAction = error.primaryAction {
                Button(action: {
                    performAction(primaryAction)
                }) {
                    HStack {
                        if isPerformingAction {
                            ProgressView()
                                .scaleEffect(0.8)
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: primaryAction.iconName)
                                .font(.system(size: 16, weight: .medium))
                        }
                        
                        Text(primaryAction.title)
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(primaryAction.isDestructive ? Color.red : errorForegroundColor)
                    .cornerRadius(10)
                }
                .disabled(isPerformingAction)
            }
            
            // Secondary Action Button
            if let secondaryAction = error.secondaryAction {
                Button(action: {
                    performAction(secondaryAction)
                }) {
                    HStack {
                        Image(systemName: secondaryAction.iconName)
                            .font(.system(size: 14, weight: .medium))
                        
                        Text(secondaryAction.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(secondaryAction.isDestructive ? .red : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                }
                .disabled(isPerformingAction)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var backgroundColorForPlatform: Color {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color(.systemBackground)
        #endif
    }
    
    private var errorBackgroundColor: Color {
        switch error.errorColor {
        case .error:
            return Color.red.opacity(0.1)
        case .warning:
            return Color.orange.opacity(0.1)
        case .info:
            return Color.blue.opacity(0.1)
        case .offline:
            return Color.yellow.opacity(0.1)
        }
    }
    
    private var errorForegroundColor: Color {
        switch error.errorColor {
        case .error:
            return Color.red
        case .warning:
            return Color.orange
        case .info:
            return Color.blue
        case .offline:
            return Color.yellow
        }
    }
    
    private var errorBorderColor: Color {
        switch error.errorColor {
        case .error:
            return Color.red.opacity(0.3)
        case .warning:
            return Color.orange.opacity(0.3)
        case .info:
            return Color.blue.opacity(0.3)
        case .offline:
            return Color.yellow.opacity(0.3)
        }
    }
    
    // MARK: - Actions
    
    private func performAction(_ action: ErrorAction) {
        isPerformingAction = true
        
        // Add a small delay to show the loading state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onAction(action)
            isPerformingAction = false
        }
    }
}

// MARK: - Compact Error View

/// A compact error view for inline display in lists
struct CompactTranscriptionErrorView: View {
    let error: TranscriptionError
    let onRetry: (() -> Void)?
    let onDismiss: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 12) {
            // Error Icon
            Image(systemName: error.iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(errorColor)
                .frame(width: 20, height: 20)
            
            // Error Text
            VStack(alignment: .leading, spacing: 2) {
                Text(error.errorDescription ?? "Error")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(errorColor)
                    .lineLimit(1)
                
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 8) {
                if error.canRetry, let onRetry = onRetry {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                if let onDismiss = onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(errorBackgroundColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(errorColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var errorColor: Color {
        switch error.errorColor {
        case .error:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
        case .offline:
            return .yellow
        }
    }
    
    private var errorBackgroundColor: Color {
        errorColor.opacity(0.1)
    }
}

// MARK: - Error Alert Modifier

struct TranscriptionErrorAlert: ViewModifier {
    @Binding var error: TranscriptionError?
    let recording: Recording?
    let onAction: (ErrorAction) -> Void
    
    func body(content: Content) -> some View {
        content
            .alert(
                error?.errorDescription ?? "Transcription Error",
                isPresented: .constant(error != nil),
                presenting: error
            ) { error in
                // Primary Action Button
                if let primaryAction = error.primaryAction {
                    Button(primaryAction.title) {
                        onAction(primaryAction)
                        self.error = nil
                    }
                }
                
                // Secondary Action Button
                if let secondaryAction = error.secondaryAction {
                    Button(secondaryAction.title, role: secondaryAction.isDestructive ? .destructive : .cancel) {
                        onAction(secondaryAction)
                        self.error = nil
                    }
                }
                
                // Always provide a dismiss option
                Button("Dismiss", role: .cancel) {
                    self.error = nil
                }
            } message: { error in
                Text(error.detailedDescription)
            }
    }
}

extension View {
    func transcriptionErrorAlert(
        error: Binding<TranscriptionError?>,
        recording: Recording? = nil,
        onAction: @escaping (ErrorAction) -> Void
    ) -> some View {
        modifier(TranscriptionErrorAlert(error: error, recording: recording, onAction: onAction))
    }
}

// MARK: - Error Banner View

/// A banner view that appears at the top of the screen for important errors
struct TranscriptionErrorBanner: View {
    let error: TranscriptionError
    let onAction: (ErrorAction) -> Void
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: error.iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(error.errorDescription ?? "Error")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            if let primaryAction = error.primaryAction {
                Button(action: {
                    onAction(primaryAction)
                }) {
                    Text(primaryAction.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(bannerColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .cornerRadius(6)
                }
            }
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(bannerColor)
        .cornerRadius(0)
        .offset(y: isVisible ? 0 : -100)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isVisible)
        .onAppear {
            isVisible = true
        }
    }
    
    private var bannerColor: Color {
        switch error.errorColor {
        case .error:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
        case .offline:
            return .yellow
        }
    }
}

// MARK: - Preview

#Preview("Full Error View") {
    TranscriptionErrorView(
        error: .permissionDenied,
        recording: Recording(
            fileName: "test.m4a",
            url: URL(fileURLWithPath: "/tmp/test.m4a"),
            createdAt: Date(),
            duration: 60.0
        ),
        onAction: { action in
            print("Action: \(action)")
        },
        onDismiss: {
            print("Dismissed")
        }
    )
    .padding()
}

#Preview("Compact Error View") {
    CompactTranscriptionErrorView(
        error: .networkUnavailable,
        onRetry: {
            print("Retry")
        },
        onDismiss: {
            print("Dismiss")
        }
    )
    .padding()
}