import XCTest
@testable import MacParakeetCore

final class MeetingAudioFileTests: XCTestCase {

    // MARK: - mixedAudioURL

    func testMixedAudioURLReturnsNilForFileSource() {
        let transcription = makeTranscription(
            fileName: "lecture.mp3",
            filePath: "/tmp/lecture.mp3",
            sourceType: .file
        )
        XCTAssertNil(MeetingAudioFile.mixedAudioURL(for: transcription))
    }

    func testMixedAudioURLReturnsNilForYouTubeSource() {
        let transcription = makeTranscription(
            fileName: "interview.m4a",
            filePath: "/tmp/interview.m4a",
            sourceType: .youtube
        )
        XCTAssertNil(MeetingAudioFile.mixedAudioURL(for: transcription))
    }

    func testMixedAudioURLReturnsNilWhenFilePathIsMissing() {
        let transcription = makeTranscription(
            fileName: "Meeting",
            filePath: nil,
            sourceType: .meeting
        )
        XCTAssertNil(MeetingAudioFile.mixedAudioURL(for: transcription))
    }

    func testMixedAudioURLReturnsNilWhenFilePathIsWhitespace() {
        let transcription = makeTranscription(
            fileName: "Meeting",
            filePath: "   ",
            sourceType: .meeting
        )
        XCTAssertNil(MeetingAudioFile.mixedAudioURL(for: transcription))
    }

    func testMixedAudioURLReturnsResolvedURLForMeeting() throws {
        let path = "/tmp/MacParakeetTests/meeting.m4a"
        let transcription = makeTranscription(
            fileName: "Meeting",
            filePath: path,
            sourceType: .meeting
        )
        let url = try XCTUnwrap(MeetingAudioFile.mixedAudioURL(for: transcription))
        XCTAssertEqual(url.path, path)
    }

    // MARK: - isAvailable

    func testIsAvailableReturnsFalseForMissingFile() {
        let transcription = makeTranscription(
            fileName: "Meeting",
            filePath: "/tmp/macparakeet-tests-nonexistent-\(UUID().uuidString).m4a",
            sourceType: .meeting
        )
        XCTAssertFalse(MeetingAudioFile.isAvailable(for: transcription))
    }

    func testIsAvailableReturnsTrueWhenFileExists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macparakeet-audio-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("meeting.m4a")
        try Data([0x00, 0x01]).write(to: file)

        let transcription = makeTranscription(
            fileName: "Meeting",
            filePath: file.path,
            sourceType: .meeting
        )
        XCTAssertTrue(MeetingAudioFile.isAvailable(for: transcription))
    }

    func testIsAvailableReturnsFalseWhenPathIsADirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macparakeet-audio-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let transcription = makeTranscription(
            fileName: "Meeting",
            filePath: directory.path,
            sourceType: .meeting
        )
        XCTAssertFalse(MeetingAudioFile.isAvailable(for: transcription))
    }

    // MARK: - suggestedExportStem

    func testSuggestedExportStemPrefersDerivedTitleWithDate() {
        let transcription = makeTranscription(
            fileName: "Meeting May 11, 2026 at 1:32 PM",
            sourceType: .meeting,
            derivedTitle: "Q4 planning sync",
            createdAt: makeDate(year: 2026, month: 5, day: 11)
        )
        let stem = MeetingAudioFile.suggestedExportStem(for: transcription)
        XCTAssertEqual(stem, "Q4 planning sync - 2026-05-11")
    }

    func testSuggestedExportStemFallsBackToFileName() {
        let transcription = makeTranscription(
            fileName: "Meeting May 11, 2026 at 1:32 PM",
            sourceType: .meeting,
            derivedTitle: nil,
            createdAt: makeDate(year: 2026, month: 5, day: 11)
        )
        let stem = MeetingAudioFile.suggestedExportStem(for: transcription)
        XCTAssertEqual(stem, "Meeting May 11, 2026 at 1 32 PM")
        // Colon in `1:32` is sanitized to a space — Finder allows colons in
        // display, but they map to `/` on the filesystem layer and we'd
        // rather show a clean save-as preview.
    }

    func testSuggestedExportStemIgnoresWhitespaceOnlyDerivedTitle() {
        let transcription = makeTranscription(
            fileName: "Meeting",
            sourceType: .meeting,
            derivedTitle: "   ",
            createdAt: makeDate(year: 2026, month: 5, day: 11)
        )
        let stem = MeetingAudioFile.suggestedExportStem(for: transcription)
        XCTAssertEqual(stem, "Meeting")
    }

    func testSuggestedExportStemFallsBackToConstantWhenFileNameIsEmpty() {
        let transcription = makeTranscription(
            fileName: "   ",
            sourceType: .meeting,
            derivedTitle: nil,
            createdAt: makeDate(year: 2026, month: 5, day: 11)
        )
        let stem = MeetingAudioFile.suggestedExportStem(for: transcription)
        XCTAssertEqual(stem, "Meeting")
    }

    func testSuggestedExportStemSanitizesPathSeparators() {
        let transcription = makeTranscription(
            fileName: "Meeting",
            sourceType: .meeting,
            derivedTitle: "Eng/Design sync: roadmap",
            createdAt: makeDate(year: 2026, month: 5, day: 11)
        )
        let stem = MeetingAudioFile.suggestedExportStem(for: transcription)
        // "/" and ":" both replaced with spaces, then collapsed.
        XCTAssertEqual(stem, "Eng Design sync roadmap - 2026-05-11")
    }

    // MARK: - Fixtures

    private func makeTranscription(
        fileName: String,
        filePath: String? = nil,
        sourceType: Transcription.SourceType,
        derivedTitle: String? = nil,
        createdAt: Date = Date()
    ) -> Transcription {
        Transcription(
            createdAt: createdAt,
            fileName: fileName,
            filePath: filePath,
            status: .completed,
            sourceType: sourceType,
            derivedTitle: derivedTitle
        )
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        components.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return Calendar(identifier: .iso8601).date(from: components)!
    }
}
