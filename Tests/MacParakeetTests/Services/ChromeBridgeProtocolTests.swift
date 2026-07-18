import XCTest

@testable import MacParakeetCore

final class ChromeBridgeProtocolTests: XCTestCase {
    // MARK: - Request codec

    func testDecodesStartRecordingRequestFromExtensionShapedJSON() throws {
        let json = #"{"v":1,"id":"req-1","type":"start_recording","title":"Weekly sync","platform":"google_meet"}"#
        let request = try ChromeBridgeCodec.decodeRequest(payloadString: json)

        XCTAssertEqual(request.v, 1)
        XCTAssertEqual(request.id, "req-1")
        XCTAssertEqual(request.type, .startRecording)
        XCTAssertEqual(request.title, "Weekly sync")
        XCTAssertEqual(request.platform, "google_meet")
    }

    func testDecodesRequestWithoutOptionalFields() throws {
        let json = #"{"v":1,"id":"req-2","type":"get_state"}"#
        let request = try ChromeBridgeCodec.decodeRequest(payloadString: json)

        XCTAssertEqual(request.type, .getState)
        XCTAssertNil(request.title)
        XCTAssertNil(request.platform)
    }

    func testDecodeIgnoresUnknownAdditiveFields() throws {
        let json = #"{"v":1,"id":"req-3","type":"stop_recording","futureField":true}"#
        let request = try ChromeBridgeCodec.decodeRequest(payloadString: json)

        XCTAssertEqual(request.type, .stopRecording)
    }

    func testDecodeUnknownRequestTypeThrows() {
        let json = #"{"v":1,"id":"req-4","type":"self_destruct"}"#
        XCTAssertThrowsError(try ChromeBridgeCodec.decodeRequest(payloadString: json))
    }

    func testRequestRoundTripsThroughCodec() throws {
        let request = ChromeBridgeRequest(id: "req-5", type: .startRecording, title: "Standup", platform: "teams")
        let decoded = try ChromeBridgeCodec.decodeRequest(try ChromeBridgeCodec.encode(request))

        XCTAssertEqual(decoded, request)
    }

    func testDecodesSpeakerActivityRequestWithEvents() throws {
        let json = """
            {"v":1,"id":"sa-1","type":"speaker_activity","events":[\
            {"name":"Alice","startMs":1800000000000,"endMs":1800000004000},\
            {"name":"Bob","startMs":1800000005000,"endMs":1800000009000}]}
            """
        let request = try ChromeBridgeCodec.decodeRequest(payloadString: json)

        XCTAssertEqual(request.type, .speakerActivity)
        XCTAssertEqual(request.events, [
            ChromeBridgeSpeakerEvent(name: "Alice", startMs: 1_800_000_000_000, endMs: 1_800_000_004_000),
            ChromeBridgeSpeakerEvent(name: "Bob", startMs: 1_800_000_005_000, endMs: 1_800_000_009_000),
        ])
    }

    func testSpeakerActivityRoundTripsThroughCodec() throws {
        let request = ChromeBridgeRequest(
            id: "sa-2",
            type: .speakerActivity,
            events: [ChromeBridgeSpeakerEvent(name: "Dana", startMs: 10, endMs: 5_010)]
        )
        let decoded = try ChromeBridgeCodec.decodeRequest(try ChromeBridgeCodec.encode(request))

        XCTAssertEqual(decoded, request)
    }

    // MARK: - Reply codec

    func testStateReplyEncodesWireFieldNames() throws {
        let reply = ChromeBridgeReply.state(
            replyTo: "req-1", bridgeEnabled: true, recording: true, flowState: "recording"
        )
        let json = try ChromeBridgeCodec.encodeString(reply)

        XCTAssertEqual(
            json,
            #"{"bridgeEnabled":true,"flowState":"recording","recording":true,"replyTo":"req-1","type":"state","v":1}"#
        )
    }

    func testErrorReplyOmitsStateFields() throws {
        let reply = ChromeBridgeReply.error(replyTo: nil, code: .bridgeDisabled, message: "Bridge is off")
        let json = try ChromeBridgeCodec.encodeString(reply)

        XCTAssertEqual(
            json,
            #"{"code":"bridge_disabled","message":"Bridge is off","type":"error","v":1}"#
        )
    }

    func testReplyRoundTripsThroughCodec() throws {
        let reply = ChromeBridgeReply.state(replyTo: nil, bridgeEnabled: false, recording: false, flowState: "idle")
        let decoded = try ChromeBridgeCodec.decodeReply(try ChromeBridgeCodec.encode(reply))

        XCTAssertEqual(decoded, reply)
    }

    // MARK: - Native messaging framing

    func testFrameRoundTrip() throws {
        let payload = Data(#"{"v":1,"id":"a","type":"hello"}"#.utf8)
        let framed = try NativeMessagingFrame.encode(payload)

        XCTAssertEqual(framed.count, payload.count + 4)
        let decoded = try XCTUnwrap(NativeMessagingFrame.decodeFirst(from: framed))
        XCTAssertEqual(decoded.payload, payload)
        XCTAssertEqual(decoded.consumed, framed.count)
    }

    func testFrameHeaderIsLittleEndian() throws {
        let framed = try NativeMessagingFrame.encode(Data(repeating: 0x7B, count: 258))

        XCTAssertEqual([UInt8](framed.prefix(4)), [0x02, 0x01, 0x00, 0x00])
    }

    func testDecodeReturnsNilForIncompleteHeader() throws {
        XCTAssertNil(try NativeMessagingFrame.decodeFirst(from: Data([0x05, 0x00])))
    }

    func testDecodeReturnsNilForIncompletePayload() throws {
        var buffer = try NativeMessagingFrame.encode(Data(repeating: 0x41, count: 10))
        buffer.removeLast(3)

        XCTAssertNil(try NativeMessagingFrame.decodeFirst(from: buffer))
    }

    func testDecodeHandlesTwoFramesInOneBuffer() throws {
        let first = Data(#"{"a":1}"#.utf8)
        let second = Data(#"{"b":2}"#.utf8)
        var buffer = try NativeMessagingFrame.encode(first)
        buffer.append(try NativeMessagingFrame.encode(second))

        let one = try XCTUnwrap(NativeMessagingFrame.decodeFirst(from: buffer))
        XCTAssertEqual(one.payload, first)
        buffer.removeFirst(one.consumed)
        let two = try XCTUnwrap(NativeMessagingFrame.decodeFirst(from: buffer))
        XCTAssertEqual(two.payload, second)
        buffer.removeFirst(two.consumed)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testDecodeWorksOnNonZeroBasedSlice() throws {
        // Data slices keep parent indices; the decoder must not assume
        // startIndex == 0. Simulate a consumed-prefix slice.
        let payload = Data(#"{"v":1}"#.utf8)
        var buffer = Data([0xFF, 0xFF, 0xFF])
        buffer.append(try NativeMessagingFrame.encode(payload))
        let slice = buffer[3...]

        let decoded = try XCTUnwrap(NativeMessagingFrame.decodeFirst(from: slice))
        XCTAssertEqual(decoded.payload, payload)
    }

    func testOversizeDeclaredLengthThrows() {
        // 2 MB declared length — exceeds the 1 MB cap even though no payload
        // bytes follow; the decoder must throw rather than wait forever.
        let header = Data([0x00, 0x00, 0x20, 0x00])
        XCTAssertThrowsError(try NativeMessagingFrame.decodeFirst(from: header)) { error in
            XCTAssertEqual(
                error as? NativeMessagingFrame.FrameError,
                .messageTooLarge(bytes: 2_097_152)
            )
        }
    }

    func testOversizeOutgoingPayloadThrows() {
        let payload = Data(count: NativeMessagingFrame.maxMessageBytes + 1)
        XCTAssertThrowsError(try NativeMessagingFrame.encode(payload))
    }

    // MARK: - Configuration

    func testBridgeDisabledByDefault() throws {
        let suiteName = "chrome-bridge-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(ChromeBridgeConfiguration.isEnabled(defaults: defaults))
        defaults.set(true, forKey: ChromeBridgeConfiguration.enabledKey)
        XCTAssertTrue(ChromeBridgeConfiguration.isEnabled(defaults: defaults))
    }
}
