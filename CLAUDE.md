# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a SwiftUI-based voice recording iOS application created with Xcode 16.4. The app allows users to record audio from the microphone, save recordings to the device, browse previous recordings, play them back, transcribe them using Apple's Speech framework, and delete unwanted recordings. The project uses Swift 5.0 and targets multiple platforms including iOS (18.5+), macOS (15.5+), and visionOS (2.5+).

## Development Commands

### Building and Running
```bash
# Open project in Xcode (primary development method)
open HelloWorld.xcodeproj

# Build from command line
xcodebuild -project HelloWorld.xcodeproj -scheme HelloWorld -configuration Debug build

# Run tests
xcodebuild test -project HelloWorld.xcodeproj -scheme HelloWorld -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test class
xcodebuild test -project HelloWorld.xcodeproj -scheme HelloWorld -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:HelloWorldTests/RecordingModelTests

# Clean build
xcodebuild clean -project HelloWorld.xcodeproj -scheme HelloWorld
```

## Architecture Overview

### Core Components

#### RecordingManager (RecordingManager.swift)
- Central coordinator for all audio and transcription functionality
- Manages AVAudioRecorder/AVAudioPlayer lifecycle
- Integrates with TranscriptionService for speech-to-text processing
- Handles permissions for both microphone and speech recognition
- Uses @Published properties for SwiftUI reactive updates

#### Transcription System
The app features a sophisticated transcription system with multiple components:

- **TranscriptionService**: Main service handling speech-to-text using Apple's Speech framework
- **TranscriptionQueue**: Manages queued transcription requests with persistence
- **TranscriptionErrorHandler**: Centralized error handling with user-friendly messages
- **NetworkMonitor**: Monitors network connectivity for online transcription features
- **SpeechRecognizer**: Wrapper around SFSpeechRecognizer with async/await support

#### Data Models

- **Recording**: Core data model with transcription support, includes computed properties for UI display
- **TranscriptionResult**: Represents transcription outcomes with error handling
- **TranscriptionQueueItem**: Manages individual transcription tasks in the queue

#### UI Architecture
- **ContentView**: Root TabView container
- **RecordingView**: Recording interface with circular record button
- **RecordingsListView**: List of saved recordings with search functionality
- **TranscriptionDetailView**: Full transcription text display with error handling
- **TranscriptionErrorView**: Dedicated error display component

### Key Technical Details

- **Swift Version**: 5.0
- **Testing Framework**: Swift Testing (uses `@Test` annotation, not XCTest)
- **Minimum Deployment Targets**: iOS 18.5, macOS 15.5, visionOS 2.5
- **Audio Framework**: AVFoundation with high-quality M4A/AAC format (44.1kHz, mono)
- **Speech Framework**: Apple's Speech Recognition API with offline capability detection
- **Bundle ID**: SargeyWargey.HelloWorld
- **Permissions**: Microphone access and speech recognition (configured in HelloWorld.entitlements)

### Storage and Persistence

- Audio files saved to app's Documents directory
- Recording metadata stored in UserDefaults
- Transcription queue persisted across app launches
- Automatic cleanup of orphaned files and metadata

### Testing Structure

The project uses Swift Testing framework extensively:
- **Unit Tests**: Model testing, service layer testing, transcription logic
- **UI Tests**: Recording workflows, transcription UI, search functionality
- Tests use `#expect()` assertions instead of XCTest's `XCTAssert` family
- Async testing supported with `async throws` test functions

### Network and Offline Capabilities

- Real-time network monitoring for transcription features
- Offline transcription queuing when network unavailable
- Automatic retry mechanism when connectivity restored
- User feedback for network-dependent operations

## Project Structure

```
HelloWorld/
├── HelloWorld/                    # Main application source
│   ├── HelloWorldApp.swift       # App entry point
│   ├── ContentView.swift         # Root TabView
│   ├── RecordingView.swift       # Recording interface
│   ├── RecordingsListView.swift  # Recordings list with search
│   ├── TranscriptionDetailView.swift  # Full transcription display
│   ├── RecordingManager.swift    # Core audio/transcription coordinator
│   ├── Recording.swift           # Recording data model
│   ├── TranscriptionService.swift # Speech-to-text service
│   ├── TranscriptionQueue.swift  # Transcription task management
│   ├── NetworkMonitor.swift      # Network connectivity monitoring
│   ├── SpeechRecognizer.swift    # Speech recognition wrapper
│   └── Assets.xcassets/          # App resources
├── HelloWorldTests/              # Unit tests (Swift Testing)
└── HelloWorldUITests/            # UI automation tests
```

## Important Implementation Notes

- All transcription operations run on @MainActor to ensure UI thread safety
- Error handling uses centralized TranscriptionErrorHandler for consistent UX
- Recording metadata includes transcription status tracking with enum states
- Search functionality supports both title and transcription content
- Network-aware transcription with graceful offline handling
- Comprehensive test coverage including edge cases and error scenarios