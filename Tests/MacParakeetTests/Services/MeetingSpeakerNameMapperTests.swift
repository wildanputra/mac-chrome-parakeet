import XCTest

@testable import MacParakeetCore

final class MeetingSpeakerNameMapperTests: XCTestCase {
    /// Recording started exactly at epoch second 1_800_000_000 so
    /// wall-clock event math stays readable: wall(ms offset) = base + offset.
    private let recordingStart = Date(timeIntervalSince1970: 1_800_000_000)
    private let baseWallMs: Int64 = 1_800_000_000_000

    private func event(_ name: String, _ startOffsetMs: Int64, _ endOffsetMs: Int64) -> ChromeBridgeSpeakerEvent {
        ChromeBridgeSpeakerEvent(name: name, startMs: baseWallMs + startOffsetMs, endMs: baseWallMs + endOffsetMs)
    }

    private func speakers(_ diarized: [(String, String)]) -> [SpeakerInfo] {
        [
            SpeakerInfo(id: AudioSource.microphone.rawValue, label: AudioSource.microphone.displayLabel),
            SpeakerInfo(id: AudioSource.system.rawValue, label: AudioSource.system.displayLabel),
        ] + diarized.map { SpeakerInfo(id: $0.0, label: $0.1) }
    }

    func testRelabelsDominantOverlappingName() throws {
        let result = MeetingSpeakerNameMapper.relabeledSpeakers(
            speakers: speakers([("system:S1", "Speaker 1")]),
            diarizationSegments: [
                DiarizationSegmentRecord(speakerId: "system:S1", startMs: 0, endMs: 10_000),
                DiarizationSegmentRecord(speakerId: "system:S1", startMs: 20_000, endMs: 30_000),
            ],
            events: [
                event("Dana Devi", 0, 9_000),
                event("Dana Devi", 20_500, 29_000),
                event("Someone Else", 8_000, 9_500),
            ],
            recordingStartedAt: recordingStart
        )

        let relabeled = try XCTUnwrap(result)
        XCTAssertEqual(relabeled.first { $0.id == "system:S1" }?.label, "Dana Devi")
        // Source rows are never touched.
        XCTAssertEqual(relabeled.first { $0.id == "microphone" }?.label, AudioSource.microphone.displayLabel)
        XCTAssertEqual(relabeled.first { $0.id == "system" }?.label, AudioSource.system.displayLabel)
    }

    func testTwoSpeakersGetTheirOwnNames() throws {
        let result = MeetingSpeakerNameMapper.relabeledSpeakers(
            speakers: speakers([("system:S1", "Speaker 1"), ("system:S2", "Speaker 2")]),
            diarizationSegments: [
                DiarizationSegmentRecord(speakerId: "system:S1", startMs: 0, endMs: 12_000),
                DiarizationSegmentRecord(speakerId: "system:S2", startMs: 15_000, endMs: 27_000),
            ],
            events: [
                event("Alice", 500, 11_000),
                event("Bob", 15_200, 26_500),
            ],
            recordingStartedAt: recordingStart
        )

        let relabeled = try XCTUnwrap(result)
        XCTAssertEqual(relabeled.first { $0.id == "system:S1" }?.label, "Alice")
        XCTAssertEqual(relabeled.first { $0.id == "system:S2" }?.label, "Bob")
    }

    func testShortOverlapDoesNotRelabel() {
        // 2s of overlap is below the 3s dominant-overlap floor.
        let result = MeetingSpeakerNameMapper.relabeledSpeakers(
            speakers: speakers([("system:S1", "Speaker 1")]),
            diarizationSegments: [
                DiarizationSegmentRecord(speakerId: "system:S1", startMs: 0, endMs: 60_000)
            ],
            events: [event("Alice", 0, 2_000)],
            recordingStartedAt: recordingStart
        )

        XCTAssertNil(result)
    }

    func testContestedOverlapDoesNotRelabel() {
        // Two names split the same voice almost evenly — no 60% dominance.
        let result = MeetingSpeakerNameMapper.relabeledSpeakers(
            speakers: speakers([("system:S1", "Speaker 1")]),
            diarizationSegments: [
                DiarizationSegmentRecord(speakerId: "system:S1", startMs: 0, endMs: 20_000)
            ],
            events: [
                event("Alice", 0, 10_000),
                event("Bob", 10_000, 19_000),
            ],
            recordingStartedAt: recordingStart
        )

        XCTAssertNil(result)
    }

    func testLowSpeechCoverageDoesNotRelabel() {
        // 4s of confident overlap against 100s of speech misses the 25%
        // coverage floor — a long voice can't be claimed by a brief name.
        let result = MeetingSpeakerNameMapper.relabeledSpeakers(
            speakers: speakers([("system:S1", "Speaker 1")]),
            diarizationSegments: [
                DiarizationSegmentRecord(speakerId: "system:S1", startMs: 0, endMs: 100_000)
            ],
            events: [event("Alice", 0, 4_000)],
            recordingStartedAt: recordingStart
        )

        XCTAssertNil(result)
    }

    func testSelfNameIsIgnored() {
        let result = MeetingSpeakerNameMapper.relabeledSpeakers(
            speakers: speakers([("system:S1", "Speaker 1")]),
            diarizationSegments: [
                DiarizationSegmentRecord(speakerId: "system:S1", startMs: 0, endMs: 10_000)
            ],
            events: [event("You", 0, 10_000)],
            recordingStartedAt: recordingStart
        )

        XCTAssertNil(result)
    }

    func testEventsBeforeRecordingStartAreClippedOut() {
        // Spans that ended before the recording began must contribute nothing.
        let result = MeetingSpeakerNameMapper.relabeledSpeakers(
            speakers: speakers([("system:S1", "Speaker 1")]),
            diarizationSegments: [
                DiarizationSegmentRecord(speakerId: "system:S1", startMs: 0, endMs: 10_000)
            ],
            events: [event("Alice", -20_000, -5_000)],
            recordingStartedAt: recordingStart
        )

        XCTAssertNil(result)
    }

    func testAlreadyMatchingLabelReturnsNil() {
        // A confident match that changes nothing is not a change.
        let result = MeetingSpeakerNameMapper.relabeledSpeakers(
            speakers: speakers([("system:S1", "Alice")]),
            diarizationSegments: [
                DiarizationSegmentRecord(speakerId: "system:S1", startMs: 0, endMs: 10_000)
            ],
            events: [event("Alice", 0, 10_000)],
            recordingStartedAt: recordingStart
        )

        XCTAssertNil(result)
    }

    func testNoEventsReturnsNil() {
        let result = MeetingSpeakerNameMapper.relabeledSpeakers(
            speakers: speakers([("system:S1", "Speaker 1")]),
            diarizationSegments: [
                DiarizationSegmentRecord(speakerId: "system:S1", startMs: 0, endMs: 10_000)
            ],
            events: [],
            recordingStartedAt: recordingStart
        )

        XCTAssertNil(result)
    }
}
