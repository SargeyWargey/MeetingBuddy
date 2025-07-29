import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Accessibility Extensions

extension View {
    /// Adds accessibility support for transcription-related UI elements
    func transcriptionAccessibility(
        label: String,
        hint: String? = nil,
        value: String? = nil,
        traits: AccessibilityTraits = []
    ) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityValue(value ?? "")
            .accessibilityAddTraits(traits)
    }
    
    /// Adds accessibility support for transcription status indicators
    func transcriptionStatusAccessibility(status: Recording.TranscriptionStatus) -> some View {
        let (label, hint) = accessibilityInfo(for: status)
        return self
            .accessibilityLabel(label)
            .accessibilityHint(hint)
    }
    
    /// Adds accessibility support for transcription actions
    func transcriptionActionAccessibility(
        action: TranscriptionAction,
        isEnabled: Bool = true
    ) -> some View {
        let (label, hint) = accessibilityInfo(for: action)
        return self
            .accessibilityLabel(label)
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
    }
    
    /// Adds Dynamic Type support for transcription text
    func transcriptionDynamicType() -> some View {
        self
            .dynamicTypeSize(.xSmall ... .accessibility5)
    }
    
    /// Adds reduced motion alternatives
    func transcriptionReducedMotion<T: Equatable>(
        value: T,
        normalAnimation: Animation = .easeInOut(duration: 0.3),
        reducedAnimation: Animation = .linear(duration: 0.1)
    ) -> some View {
        #if os(iOS)
        let prefersReducedMotion = UIAccessibility.isReduceMotionEnabled
        #else
        let prefersReducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #endif
        
        return self.animation(
            prefersReducedMotion ? reducedAnimation : normalAnimation,
            value: value
        )
    }
}

// MARK: - Transcription Action Types

enum TranscriptionAction {
    case transcribe
    case retry
    case view
    case copy
    case dismiss
}

// MARK: - Accessibility Info Helpers

private func accessibilityInfo(for status: Recording.TranscriptionStatus) -> (label: String, hint: String) {
    switch status {
    case .notStarted:
        return ("Not transcribed", "Tap to start transcription")
    case .inProgress:
        return ("Transcribing", "Transcription in progress, please wait")
    case .queued:
        return ("Queued for transcription", "Transcription will start automatically when possible")
    case .completed:
        return ("Transcription completed", "Tap to view full transcription")
    case .failed:
        return ("Transcription failed", "Tap to retry transcription")
    }
}

private func accessibilityInfo(for action: TranscriptionAction) -> (label: String, hint: String) {
    switch action {
    case .transcribe:
        return ("Transcribe recording", "Starts transcription of this audio recording")
    case .retry:
        return ("Retry transcription", "Attempts to transcribe this recording again")
    case .view:
        return ("View transcription", "Opens the full transcription text")
    case .copy:
        return ("Copy transcription", "Copies the transcription text to clipboard")
    case .dismiss:
        return ("Dismiss", "Dismisses this notification")
    }
}

// MARK: - Haptic Feedback Manager

class HapticFeedbackManager {
    static let shared = HapticFeedbackManager()
    
    private init() {}
    
    func transcriptionCompleted() {
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        #endif
    }
    
    func transcriptionFailed() {
        #if os(iOS)
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.error)
        #endif
    }
    
    func transcriptionStarted() {
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        #endif
    }
    
    func textCopied() {
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        #endif
    }
    
    func buttonPressed() {
        #if os(iOS)
        let selectionFeedback = UISelectionFeedbackGenerator()
        selectionFeedback.selectionChanged()
        #endif
    }
}

// MARK: - Accessibility Announcements

class AccessibilityAnnouncementManager {
    static let shared = AccessibilityAnnouncementManager()
    
    private init() {}
    
    func announce(_ message: String, priority: AccessibilityAnnouncementPriority = .medium) {
        #if os(iOS)
        UIAccessibility.post(notification: .announcement, argument: message)
        #elseif os(macOS)
        NSAccessibility.post(element: NSApp, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: priority.macOSPriority
        ])
        #endif
    }
    
    func announceTranscriptionCompleted(for recording: Recording) {
        let message = "Transcription completed for \(recording.title)"
        announce(message, priority: .high)
    }
    
    func announceTranscriptionFailed(for recording: Recording) {
        let message = "Transcription failed for \(recording.title)"
        announce(message, priority: .high)
    }
    
    func announceTranscriptionStarted(for recording: Recording) {
        let message = "Starting transcription for \(recording.title)"
        announce(message)
    }
    
    func announceTextCopied() {
        announce("Transcription copied to clipboard")
    }
}

// MARK: - Accessibility Announcement Priority

enum AccessibilityAnnouncementPriority: Int {
    case low = 0
    case medium = 1
    case high = 2
    
    #if os(macOS)
    var macOSPriority: NSAccessibilityPriorityLevel {
        switch self {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        }
    }
    #endif
}

// MARK: - Dynamic Type Support

struct DynamicTypeReader: View {
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    let content: (DynamicTypeSize) -> AnyView
    
    var body: some View {
        content(dynamicTypeSize)
    }
}

extension DynamicTypeSize {
    var isAccessibilitySize: Bool {
        switch self {
        case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
            return true
        default:
            return false
        }
    }
    
    var transcriptionFontSize: CGFloat {
        switch self {
        case .xSmall: return 12
        case .small: return 14
        case .medium: return 16
        case .large: return 18
        case .xLarge: return 20
        case .xxLarge: return 22
        case .xxxLarge: return 24
        case .accessibility1: return 28
        case .accessibility2: return 32
        case .accessibility3: return 36
        case .accessibility4: return 40
        case .accessibility5: return 44
        @unknown default: return 16
        }
    }
}