//
//  HelloWorldTests.swift
//  HelloWorldTests
//
//  Created by Joshua Sargent on 7/27/25.
//

import Testing
import Foundation
@testable import HelloWorld

struct RecordingModelTests {
    
    // MARK: - Test Data Setup
    
    private func createTestRecording(
        transcription: String? = nil,
        transcriptionStatus: Recording.TranscriptionStatus = .notStarted,
        transcriptionError: String? = nil,
        lastTranscriptionAttempt: Date? = nil
    ) -> Recording {
        let testURL = URL(fileURLWithPath: "/tmp/test.m4a")
        return Recording(
            fileName: "test.m4a",
            url: testURL,
            createdAt: Date(),
            duration: 60.0,
            title: "Test Recording",
            transcription: transcription,
            transcriptionStatus: transcriptionStatus,
            transcriptionError: transcriptionError,
            lastTranscriptionAttempt: lastTranscriptionAttempt
        )
    }
    
    // MARK: - Initialization Tests
    
    @Test func testRecordingInitializationWithDefaults() async throws {
        let testURL = URL(fileURLWithPath: "/tmp/test.m4a")
        let recording = Recording(fileName: "test.m4a", url: testURL)
        
        #expect(recording.fileName == "test.m4a")
        #expect(recording.url == testURL)
        #expect(recording.transcription == nil)
        #expect(recording.transcriptionStatus == .notStarted)
        #expect(recording.transcriptionError == nil)
        #expect(recording.lastTranscriptionAttempt == nil)
    }
    
    @Test func testRecordingInitializationWithTranscriptionData() async throws {
        let testURL = URL(fileURLWithPath: "/tmp/test.m4a")
        let testDate = Date()
        let recording = Recording(
            fileName: "test.m4a",
            url: testURL,
            transcription: "Hello world",
            transcriptionStatus: .completed,
            transcriptionError: nil,
            lastTranscriptionAttempt: testDate
        )
        
        #expect(recording.transcription == "Hello world")
        #expect(recording.transcriptionStatus == .completed)
        #expect(recording.transcriptionError == nil)
        #expect(recording.lastTranscriptionAttempt == testDate)
    }
    
    // MARK: - TranscriptionStatus Enum Tests
    
    @Test func testTranscriptionStatusRawValues() async throws {
        #expect(Recording.TranscriptionStatus.notStarted.rawValue == "not_started")
        #expect(Recording.TranscriptionStatus.inProgress.rawValue == "in_progress")
        #expect(Recording.TranscriptionStatus.completed.rawValue == "completed")
        #expect(Recording.TranscriptionStatus.failed.rawValue == "failed")
        #expect(Recording.TranscriptionStatus.queued.rawValue == "queued")
    }
    
    @Test func testTranscriptionStatusDisplayNames() async throws {
        #expect(Recording.TranscriptionStatus.notStarted.displayName == "Not Started")
        #expect(Recording.TranscriptionStatus.inProgress.displayName == "In Progress")
        #expect(Recording.TranscriptionStatus.completed.displayName == "Completed")
        #expect(Recording.TranscriptionStatus.failed.displayName == "Failed")
        #expect(Recording.TranscriptionStatus.queued.displayName == "Queued")
    }
    
    // MARK: - Computed Properties Tests
    
    @Test func testHasTranscriptionProperty() async throws {
        let recordingWithoutTranscription = createTestRecording()
        #expect(recordingWithoutTranscription.hasTranscription == false)
        
        let recordingWithEmptyTranscription = createTestRecording(transcription: "")
        #expect(recordingWithEmptyTranscription.hasTranscription == false)
        
        let recordingWithTranscription = createTestRecording(transcription: "Hello world")
        #expect(recordingWithTranscription.hasTranscription == true)
    }
    
    @Test func testIsTranscriptionInProgressProperty() async throws {
        let notStartedRecording = createTestRecording(transcriptionStatus: .notStarted)
        #expect(notStartedRecording.isTranscriptionInProgress == false)
        
        let inProgressRecording = createTestRecording(transcriptionStatus: .inProgress)
        #expect(inProgressRecording.isTranscriptionInProgress == true)
        
        let completedRecording = createTestRecording(transcriptionStatus: .completed)
        #expect(completedRecording.isTranscriptionInProgress == false)
    }
    
    @Test func testCanRetryTranscriptionProperty() async throws {
        let notStartedRecording = createTestRecording(transcriptionStatus: .notStarted)
        #expect(notStartedRecording.canRetryTranscription == true)
        
        let failedRecording = createTestRecording(transcriptionStatus: .failed)
        #expect(failedRecording.canRetryTranscription == true)
        
        let inProgressRecording = createTestRecording(transcriptionStatus: .inProgress)
        #expect(inProgressRecording.canRetryTranscription == false)
        
        let completedRecording = createTestRecording(transcriptionStatus: .completed)
        #expect(completedRecording.canRetryTranscription == false)
        
        let queuedRecording = createTestRecording(transcriptionStatus: .queued)
        #expect(queuedRecording.canRetryTranscription == false)
    }
    
    @Test func testTranscriptionPreviewProperty() async throws {
        let recordingWithoutTranscription = createTestRecording()
        #expect(recordingWithoutTranscription.transcriptionPreview == "No transcription available")
        
        let recordingWithEmptyTranscription = createTestRecording(transcription: "")
        #expect(recordingWithEmptyTranscription.transcriptionPreview == "No transcription available")
        
        let shortTranscription = "Hello world"
        let recordingWithShortTranscription = createTestRecording(transcription: shortTranscription)
        #expect(recordingWithShortTranscription.transcriptionPreview == shortTranscription)
        
        let longTranscription = String(repeating: "A", count: 150)
        let recordingWithLongTranscription = createTestRecording(transcription: longTranscription)
        let expectedPreview = String(longTranscription.prefix(100)) + "..."
        #expect(recordingWithLongTranscription.transcriptionPreview == expectedPreview)
    }
    
    @Test func testTranscriptionStatusDisplayTextProperty() async throws {
        let notStartedRecording = createTestRecording(transcriptionStatus: .notStarted)
        #expect(notStartedRecording.transcriptionStatusDisplayText == "Not transcribed")
        
        let inProgressRecording = createTestRecording(transcriptionStatus: .inProgress)
        #expect(inProgressRecording.transcriptionStatusDisplayText == "Transcribing...")
        
        let completedWithTranscription = createTestRecording(
            transcription: "Hello world",
            transcriptionStatus: .completed
        )
        #expect(completedWithTranscription.transcriptionStatusDisplayText == "Transcribed")
        
        let completedWithoutTranscription = createTestRecording(transcriptionStatus: .completed)
        #expect(completedWithoutTranscription.transcriptionStatusDisplayText == "No transcription available")
        
        let failedRecording = createTestRecording(transcriptionStatus: .failed)
        #expect(failedRecording.transcriptionStatusDisplayText == "Transcription failed")
        
        let queuedRecording = createTestRecording(transcriptionStatus: .queued)
        #expect(queuedRecording.transcriptionStatusDisplayText == "Queued for transcription")
    }
    
    // MARK: - Codable Tests
    
    @Test func testRecordingCodableEncoding() async throws {
        let testDate = Date()
        let recording = createTestRecording(
            transcription: "Test transcription",
            transcriptionStatus: .completed,
            transcriptionError: "Test error",
            lastTranscriptionAttempt: testDate
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(recording)
        #expect(data.count > 0)
    }
    
    @Test func testRecordingCodableDecoding() async throws {
        let testDate = Date()
        let originalRecording = createTestRecording(
            transcription: "Test transcription",
            transcriptionStatus: .completed,
            transcriptionError: "Test error",
            lastTranscriptionAttempt: testDate
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(originalRecording)
        let decodedRecording = try decoder.decode(Recording.self, from: data)
        
        #expect(decodedRecording.fileName == originalRecording.fileName)
        #expect(decodedRecording.transcription == originalRecording.transcription)
        #expect(decodedRecording.transcriptionStatus == originalRecording.transcriptionStatus)
        #expect(decodedRecording.transcriptionError == originalRecording.transcriptionError)
        #expect(decodedRecording.lastTranscriptionAttempt?.timeIntervalSince1970 == originalRecording.lastTranscriptionAttempt?.timeIntervalSince1970)
    }
    
    // MARK: - Equatable Tests
    
    @Test func testRecordingEquality() async throws {
        let recording1 = createTestRecording(transcription: "Hello")
        let recording2 = createTestRecording(transcription: "Hello")
        
        // Note: These will not be equal because they have different UUIDs
        // But we can test that recordings with different transcription data are not equal
        let recording3 = createTestRecording(transcription: "World")
        
        #expect(recording1.transcription == recording2.transcription)
        #expect(recording1.transcription != recording3.transcription)
    }
    
    // MARK: - Edge Cases Tests
    
    @Test func testTranscriptionPreviewWithExactly100Characters() async throws {
        let exactTranscription = String(repeating: "A", count: 100)
        let recording = createTestRecording(transcription: exactTranscription)
        #expect(recording.transcriptionPreview == exactTranscription)
    }
    
    @Test func testTranscriptionPreviewWith101Characters() async throws {
        let longTranscription = String(repeating: "A", count: 101)
        let recording = createTestRecording(transcription: longTranscription)
        let expectedPreview = String(repeating: "A", count: 100) + "..."
        #expect(recording.transcriptionPreview == expectedPreview)
    }
}
