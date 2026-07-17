import XCTest

@testable import MacParakeet
@testable import MacParakeetCore

/// Routing-policy tests for the app side of the Chrome extension bridge
/// (ADR-029). All dependencies are injected closures; no distributed
/// notifications are posted — `handleCommand` is driven directly.
@MainActor
final class ChromeBridgeCoordinatorTests: XCTestCase {
    private final class Harness {
        var bridgeEnabled = true
        var recordingActive = false
        var flowState = "idle"
        var startAccepted = true
        var startedTitles: [String?] = []
        var stopCount = 0
        var replies: [ChromeBridgeReply] = []
        var persistedSpeakers: [(id: UUID, speakers: [SpeakerInfo])] = []
    }

    private func makeCoordinator(_ harness: Harness) -> ChromeBridgeCoordinator {
        ChromeBridgeCoordinator(
            isBridgeEnabled: { harness.bridgeEnabled },
            isRecordingActive: { harness.recordingActive },
            flowStateLabel: { harness.flowState },
            onStartRequested: { title in
                harness.startedTitles.append(title)
                if harness.startAccepted {
                    harness.recordingActive = true
                    harness.flowState = "starting"
                }
                return harness.startAccepted
            },
            onStopRequested: {
                harness.stopCount += 1
                harness.recordingActive = false
                harness.flowState = "stopping"
                return true
            },
            persistSpeakers: { id, speakers in
                harness.persistedSpeakers.append((id: id, speakers: speakers))
            },
            postReply: { harness.replies.append($0) }
        )
    }

    private func request(
        _ type: ChromeBridgeRequest.Kind,
        id: String = "req",
        title: String? = nil,
        platform: String? = nil
    ) throws -> String {
        try ChromeBridgeCodec.encodeString(ChromeBridgeRequest(id: id, type: type, title: title, platform: platform))
    }

    func testGetStateRepliesCurrentState() throws {
        let harness = Harness()
        harness.recordingActive = true
        harness.flowState = "recording"
        let coordinator = makeCoordinator(harness)

        coordinator.handleCommand(payloadString: try request(.getState, id: "s1"))

        XCTAssertEqual(harness.replies, [
            .state(replyTo: "s1", bridgeEnabled: true, recording: true, flowState: "recording")
        ])
    }

    func testGetStateWhenDisabledStillRepliesTruthfully() throws {
        let harness = Harness()
        harness.bridgeEnabled = false
        let coordinator = makeCoordinator(harness)

        coordinator.handleCommand(payloadString: try request(.getState, id: "s2"))

        XCTAssertEqual(harness.replies, [
            .state(replyTo: "s2", bridgeEnabled: false, recording: false, flowState: "idle")
        ])
    }

    func testStartWhenDisabledIsRefusedWithoutStarting() throws {
        let harness = Harness()
        harness.bridgeEnabled = false
        let coordinator = makeCoordinator(harness)

        coordinator.handleCommand(payloadString: try request(.startRecording, id: "d1", title: "Sync"))

        XCTAssertTrue(harness.startedTitles.isEmpty)
        XCTAssertEqual(harness.replies.count, 1)
        XCTAssertEqual(harness.replies[0].type, .error)
        XCTAssertEqual(harness.replies[0].code, .bridgeDisabled)
        XCTAssertEqual(harness.replies[0].replyTo, "d1")
    }

    func testStartFromIdleStartsAndRepliesPostStartState() throws {
        let harness = Harness()
        let coordinator = makeCoordinator(harness)

        coordinator.handleCommand(
            payloadString: try request(.startRecording, id: "r1", title: "Weekly sync", platform: "google_meet")
        )

        XCTAssertEqual(harness.startedTitles, ["Weekly sync"])
        XCTAssertEqual(harness.replies, [
            .state(replyTo: "r1", bridgeEnabled: true, recording: true, flowState: "starting")
        ])
    }

    func testStartWhileRecordingIsIgnoredAndRepliesState() throws {
        let harness = Harness()
        harness.recordingActive = true
        harness.flowState = "recording"
        let coordinator = makeCoordinator(harness)

        coordinator.handleCommand(payloadString: try request(.startRecording, id: "r2", title: "Second"))

        XCTAssertTrue(harness.startedTitles.isEmpty)
        XCTAssertEqual(harness.replies, [
            .state(replyTo: "r2", bridgeEnabled: true, recording: true, flowState: "recording")
        ])
    }

    func testRejectedStartRepliesStartRejectedError() throws {
        let harness = Harness()
        harness.startAccepted = false
        let coordinator = makeCoordinator(harness)

        coordinator.handleCommand(payloadString: try request(.startRecording, id: "r3"))

        XCTAssertEqual(harness.replies.count, 1)
        XCTAssertEqual(harness.replies[0].type, .error)
        XCTAssertEqual(harness.replies[0].code, .startRejected)
        XCTAssertEqual(harness.replies[0].replyTo, "r3")
    }

    func testMissingTitleFallsBackToPlatformLabel() throws {
        let harness = Harness()
        let coordinator = makeCoordinator(harness)

        coordinator.handleCommand(
            payloadString: try request(.startRecording, id: "t1", title: "  ", platform: "google_meet")
        )
        coordinator.handleCommand(payloadString: try request(.stopRecording, id: "t2"))
        coordinator.handleCommand(payloadString: try request(.startRecording, id: "t3", platform: "unknown_platform"))

        XCTAssertEqual(harness.startedTitles, ["Google Meet", nil])
    }

    func testStopStopsAndRepliesState() throws {
        let harness = Harness()
        harness.recordingActive = true
        harness.flowState = "recording"
        let coordinator = makeCoordinator(harness)

        coordinator.handleCommand(payloadString: try request(.stopRecording, id: "x1"))

        XCTAssertEqual(harness.stopCount, 1)
        XCTAssertEqual(harness.replies, [
            .state(replyTo: "x1", bridgeEnabled: true, recording: false, flowState: "stopping")
        ])
    }

    func testStopWhenDisabledIsRefused() throws {
        let harness = Harness()
        harness.bridgeEnabled = false
        harness.recordingActive = true
        let coordinator = makeCoordinator(harness)

        coordinator.handleCommand(payloadString: try request(.stopRecording, id: "x2"))

        XCTAssertEqual(harness.stopCount, 0)
        XCTAssertEqual(harness.replies.first?.code, .bridgeDisabled)
    }

    func testUndecodablePayloadProducesNoReply() {
        let harness = Harness()
        let coordinator = makeCoordinator(harness)

        coordinator.handleCommand(payloadString: "not json")
        coordinator.handleCommand(payloadString: #"{"v":1,"id":"u1","type":"self_destruct"}"#)

        XCTAssertTrue(harness.replies.isEmpty)
        XCTAssertTrue(harness.startedTitles.isEmpty)
        XCTAssertEqual(harness.stopCount, 0)
    }

    // MARK: - Speaker attribution (ADR-029)

    private func meetingTranscription(id: UUID = UUID()) -> Transcription {
        Transcription(
            id: id,
            fileName: "Weekly sync",
            speakers: [
                SpeakerInfo(id: "microphone", label: "Me"),
                SpeakerInfo(id: "system:S1", label: "Speaker 1"),
            ],
            diarizationSegments: [
                DiarizationSegmentRecord(speakerId: "system:S1", startMs: 0, endMs: 10_000)
            ],
            transcriptSegments: [
                TranscriptSegmentRecord(
                    startMs: 0,
                    endMs: 10_000,
                    speakerId: "system:S1",
                    speakerLabel: "Speaker 1",
                    text: "Hello from the browser",
                    wordRange: TranscriptSegmentWordRange(startIndex: 0, endIndexExclusive: 4)
                )
            ],
            status: .completed,
            sourceType: .meeting
        )
    }

    func testSpeakerActivityCollectedDuringRecordingAndAppliedOnCompletion() throws {
        let harness = Harness()
        let coordinator = makeCoordinator(harness)
        harness.recordingActive = true
        coordinator.recordingDidStart()

        // recordingDidStart() captured the real wall clock, so the event's
        // wall-clock span [now, now+10s] lands on the transcription's
        // [0, 10_000] diarization segment (± a few ms of test execution).
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let payload = try ChromeBridgeCodec.encodeString(ChromeBridgeRequest(
            id: "sa1",
            type: .speakerActivity,
            events: [ChromeBridgeSpeakerEvent(name: "Dana", startMs: nowMs, endMs: nowMs + 10_000)]
        ))
        coordinator.handleCommand(payloadString: payload)
        XCTAssertEqual(harness.replies.last?.type, .state)

        harness.recordingActive = false
        let transcription = meetingTranscription()
        let updated = try XCTUnwrap(coordinator.applyPendingSpeakerNames(to: transcription))

        XCTAssertEqual(updated.speakers?.first { $0.id == "system:S1" }?.label, "Dana")
        XCTAssertEqual(updated.transcriptSegments?.first?.speakerLabel, "Dana")
        XCTAssertEqual(harness.persistedSpeakers.count, 1)
        XCTAssertEqual(harness.persistedSpeakers.first?.id, transcription.id)

        // Harvest is one-shot: a second completion finds nothing.
        XCTAssertNil(coordinator.applyPendingSpeakerNames(to: transcription))
    }

    func testSpeakerActivityIgnoredWhileNotRecording() throws {
        let harness = Harness()
        let coordinator = makeCoordinator(harness)
        coordinator.recordingDidStart()
        harness.recordingActive = false

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let payload = try ChromeBridgeCodec.encodeString(ChromeBridgeRequest(
            id: "sa2",
            type: .speakerActivity,
            events: [ChromeBridgeSpeakerEvent(name: "Dana", startMs: nowMs, endMs: nowMs + 10_000)]
        ))
        coordinator.handleCommand(payloadString: payload)

        XCTAssertEqual(harness.replies.last?.type, .state)
        XCTAssertNil(coordinator.applyPendingSpeakerNames(to: meetingTranscription()))
        XCTAssertTrue(harness.persistedSpeakers.isEmpty)
    }

    func testApplySkipsWhileAnotherRecordingIsActive() throws {
        let harness = Harness()
        let coordinator = makeCoordinator(harness)
        harness.recordingActive = true
        coordinator.recordingDidStart()

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let payload = try ChromeBridgeCodec.encodeString(ChromeBridgeRequest(
            id: "sa3",
            type: .speakerActivity,
            events: [ChromeBridgeSpeakerEvent(name: "Dana", startMs: nowMs, endMs: nowMs + 10_000)]
        ))
        coordinator.handleCommand(payloadString: payload)

        // A back-to-back recording is still active when the earlier meeting's
        // transcription completes — the events belong to the live recording,
        // so nothing may be applied.
        XCTAssertNil(coordinator.applyPendingSpeakerNames(to: meetingTranscription()))
        XCTAssertTrue(harness.persistedSpeakers.isEmpty)
    }

    func testApplySkipsNonMeetingTranscriptions() throws {
        let harness = Harness()
        let coordinator = makeCoordinator(harness)
        harness.recordingActive = true
        coordinator.recordingDidStart()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let payload = try ChromeBridgeCodec.encodeString(ChromeBridgeRequest(
            id: "sa4",
            type: .speakerActivity,
            events: [ChromeBridgeSpeakerEvent(name: "Dana", startMs: nowMs, endMs: nowMs + 10_000)]
        ))
        coordinator.handleCommand(payloadString: payload)
        harness.recordingActive = false

        var fileTranscription = meetingTranscription()
        fileTranscription.sourceType = .file
        XCTAssertNil(coordinator.applyPendingSpeakerNames(to: fileTranscription))
        // Events survive a non-meeting completion — the meeting harvest can
        // still happen afterwards.
        XCTAssertNotNil(coordinator.applyPendingSpeakerNames(to: meetingTranscription()))
    }
}
