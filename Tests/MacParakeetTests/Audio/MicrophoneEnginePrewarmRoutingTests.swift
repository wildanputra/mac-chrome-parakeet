import CoreAudio
import XCTest
@testable import MacParakeetCore

final class MicrophoneEnginePrewarmRoutingTests: XCTestCase {
    func testPrewarmPrefixStopsBeforeBluetoothFallback() {
        let attempts = [
            MeetingInputDeviceAttempt(source: .selected(uid: "desk"), deviceID: 1),
            MeetingInputDeviceAttempt.implicitSystemDefault(resolvedDeviceID: 2),
            MeetingInputDeviceAttempt(source: .builtIn, deviceID: 3),
        ]

        let result = AVAudioEngineMicrophonePlatform.prewarmAttemptPrefix(
            from: attempts,
            transportType: { deviceID in
                deviceID == 2 ? kAudioDeviceTransportTypeBluetooth : kAudioDeviceTransportTypeBuiltIn
            }
        )

        XCTAssertEqual(result, [MeetingInputDeviceAttempt(source: .selected(uid: "desk"), deviceID: 1)])
    }

    func testPrewarmPrefixFailsClosedForUnresolvedFirstRoute() {
        let attempts = [
            MeetingInputDeviceAttempt.implicitSystemDefault(),
            MeetingInputDeviceAttempt(source: .builtIn, deviceID: 3),
        ]

        let result = AVAudioEngineMicrophonePlatform.prewarmAttemptPrefix(
            from: attempts,
            transportType: { _ in kAudioDeviceTransportTypeBuiltIn }
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testPrewarmPrefixPinsResolvedSystemDefaultExplicitly() {
        let attempts = [MeetingInputDeviceAttempt.implicitSystemDefault(resolvedDeviceID: 4)]

        let result = AVAudioEngineMicrophonePlatform.prewarmAttemptPrefix(
            from: attempts,
            transportType: { _ in kAudioDeviceTransportTypeUSB }
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.explicitDeviceID, 4)
        XCTAssertFalse(result.first?.usesImplicitSystemDefault ?? true)
    }
}
