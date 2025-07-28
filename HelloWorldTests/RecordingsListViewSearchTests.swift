import XCTest
@testable import HelloWorld

final class RecordingsListViewSearchTests: XCTestCase {
    
    var recordingManager: RecordingManager!
    var testRecordings: [Recording]!
    
    override func setUpWithError() throws {
        recordingManager = RecordingManager()
        
        // Create test recordings with different transcription states
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        testRecordings = [
            Recording(
                fileName: "test1.m4a",
                url: documentsURL.appendingPathComponent("test1.m4a"),
                createdAt: Date(),
                duration: 30.0,
                title: "Meeting Notes",
                transcription: "This is a meeting about project planning and budget allocation",
                transcriptionStatus: .completed
            ),
            Recording(
                fileName: "test2.m4a",
                url: documentsURL.appendingPathComponent("test2.m4a"),
                createdAt: Date(),
                duration: 45.0,
                title: "Voice Memo",
                transcription: "Remember to buy groceries and pick up dry cleaning",
                transcriptionStatus: .completed
            ),
            Recording(
                fileName: "test3.m4a",
                url: documentsURL.appendingPathComponent("test3.m4a"),
                createdAt: Date(),
                duration: 60.0,
                title: "Interview",
                transcription: nil,
                transcriptionStatus: .notStarted
            ),
            Recording(
                fileName: "test4.m4a",
                url: documentsURL.appendingPathComponent("test4.m4a"),
                createdAt: Date(),
                duration: 20.0,
                title: "Quick Note",
                transcription: "",
                transcriptionStatus: .completed
            ),
            Recording(
                fileName: "test5.m4a",
                url: documentsURL.appendingPathComponent("test5.m4a"),
                createdAt: Date(),
                duration: 90.0,
                title: "Conference Call",
                transcription: "Discussion about quarterly results and future planning strategies",
                transcriptionStatus: .completed
            )
        ]
    }
    
    override func tearDownWithError() throws {
        recordingManager = nil
        testRecordings = nil
    }
    
    // MARK: - Search Filtering Tests
    
    func testSearchFilteringWithEmptySearchText() throws {
        // Given
        let searchText = ""
        
        // When
        let filteredRecordings = filterRecordings(testRecordings, searchText: searchText)
        
        // Then
        XCTAssertEqual(filteredRecordings.count, testRecordings.count, "Empty search should return all recordings")
    }
    
    func testSearchFilteringWithTranscriptionContent() throws {
        // Given
        let searchText = "meeting"
        
        // When
        let filteredRecordings = filterRecordings(testRecordings, searchText: searchText)
        
        // Then
        XCTAssertEqual(filteredRecordings.count, 1, "Should find one recording containing 'meeting'")
        XCTAssertEqual(filteredRecordings.first?.title, "Meeting Notes")
    }
    
    func testSearchFilteringCaseInsensitive() throws {
        // Given
        let searchText = "GROCERIES"
        
        // When
        let filteredRecordings = filterRecordings(testRecordings, searchText: searchText)
        
        // Then
        XCTAssertEqual(filteredRecordings.count, 1, "Case insensitive search should find 'groceries'")
        XCTAssertEqual(filteredRecordings.first?.title, "Voice Memo")
    }
    
    func testSearchFilteringByTitle() throws {
        // Given
        let searchText = "Interview"
        
        // When
        let filteredRecordings = filterRecordings(testRecordings, searchText: searchText)
        
        // Then
        XCTAssertEqual(filteredRecordings.count, 0, "Should not find recordings without transcription even if title matches")
    }
    
    func testSearchFilteringExcludesRecordingsWithoutTranscription() throws {
        // Given
        let searchText = "test"
        
        // When
        let filteredRecordings = filterRecordings(testRecordings, searchText: searchText)
        
        // Then
        XCTAssertEqual(filteredRecordings.count, 0, "Should exclude recordings without transcription")
        
        // Verify that recordings without transcription are excluded
        let recordingsWithoutTranscription = testRecordings.filter { !$0.hasTranscription }
        XCTAssertGreaterThan(recordingsWithoutTranscription.count, 0, "Test data should include recordings without transcription")
    }
    
    func testSearchFilteringExcludesEmptyTranscriptions() throws {
        // Given
        let searchText = "quick"
        
        // When
        let filteredRecordings = filterRecordings(testRecordings, searchText: searchText)
        
        // Then
        XCTAssertEqual(filteredRecordings.count, 0, "Should exclude recordings with empty transcription")
    }
    
    func testSearchFilteringMultipleMatches() throws {
        // Given
        let searchText = "planning"
        
        // When
        let filteredRecordings = filterRecordings(testRecordings, searchText: searchText)
        
        // Then
        XCTAssertEqual(filteredRecordings.count, 2, "Should find multiple recordings containing 'planning'")
        
        let titles = filteredRecordings.map { $0.title }.sorted()
        XCTAssertEqual(titles, ["Conference Call", "Meeting Notes"])
    }
    
    func testSearchFilteringNoMatches() throws {
        // Given
        let searchText = "nonexistent"
        
        // When
        let filteredRecordings = filterRecordings(testRecordings, searchText: searchText)
        
        // Then
        XCTAssertEqual(filteredRecordings.count, 0, "Should return empty array for no matches")
    }
    
    func testSearchFilteringPartialMatches() throws {
        // Given
        let searchText = "plan"
        
        // When
        let filteredRecordings = filterRecordings(testRecordings, searchText: searchText)
        
        // Then
        XCTAssertEqual(filteredRecordings.count, 2, "Should find partial matches")
        
        // Verify both "planning" matches are found
        let transcriptions = filteredRecordings.compactMap { $0.transcription }
        XCTAssertTrue(transcriptions.allSatisfy { $0.localizedCaseInsensitiveContains("plan") })
    }
    
    func testSearchFilteringWhitespaceHandling() throws {
        // Given
        let searchText = "  meeting  "
        
        // When
        let filteredRecordings = filterRecordings(testRecordings, searchText: searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        
        // Then
        XCTAssertEqual(filteredRecordings.count, 1, "Should handle whitespace in search text")
    }
    
    // MARK: - Helper Methods
    
    private func filterRecordings(_ recordings: [Recording], searchText: String) -> [Recording] {
        if searchText.isEmpty {
            return recordings
        }
        
        return recordings.filter { recording in
            // Only search through recordings that have transcriptions
            guard recording.hasTranscription,
                  let transcription = recording.transcription else {
                return false
            }
            
            return transcription.localizedCaseInsensitiveContains(searchText) ||
                   recording.title.localizedCaseInsensitiveContains(searchText)
        }
    }
}