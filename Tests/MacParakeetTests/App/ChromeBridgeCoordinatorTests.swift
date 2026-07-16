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
}
