import CoreAudio
import XCTest
@testable import MacParakeetCore

final class AudioDeviceManagerTransportTests: XCTestCase {
    func testBluetoothTransportTypesClassifyAsBluetooth() {
        XCTAssertTrue(
            AudioDeviceManager.isBluetoothTransportType(kAudioDeviceTransportTypeBluetooth)
        )
        XCTAssertTrue(
            AudioDeviceManager.isBluetoothTransportType(kAudioDeviceTransportTypeBluetoothLE)
        )
    }

    func testNonBluetoothTransportTypesDoNotClassifyAsBluetooth() {
        XCTAssertFalse(
            AudioDeviceManager.isBluetoothTransportType(kAudioDeviceTransportTypeBuiltIn)
        )
        XCTAssertFalse(
            AudioDeviceManager.isBluetoothTransportType(kAudioDeviceTransportTypeUSB)
        )
        XCTAssertFalse(
            AudioDeviceManager.isBluetoothTransportType(kAudioDeviceTransportTypeAggregate)
        )
        XCTAssertFalse(
            AudioDeviceManager.isBluetoothTransportType(kAudioDeviceTransportTypeVirtual)
        )
        XCTAssertFalse(AudioDeviceManager.isBluetoothTransportType(0))
    }

    func testDirectBluetoothInputClassifiesAsBluetooth() {
        XCTAssertTrue(
            AudioDeviceManager.isBluetoothInput(
                transport: kAudioDeviceTransportTypeBluetooth,
                activeSubDeviceTransports: []
            )
        )
        XCTAssertTrue(
            AudioDeviceManager.isBluetoothInput(
                transport: kAudioDeviceTransportTypeBluetoothLE,
                activeSubDeviceTransports: []
            )
        )
    }

    func testAggregateWithAnyBluetoothSubDeviceClassifiesAsBluetooth() {
        // The Bluetooth member need not be first: an aggregate holds every
        // sub-device's input stream open, so any Bluetooth member pins the
        // headset in HFP/SCO.
        XCTAssertTrue(
            AudioDeviceManager.isBluetoothInput(
                transport: kAudioDeviceTransportTypeAggregate,
                activeSubDeviceTransports: [
                    kAudioDeviceTransportTypeBuiltIn,
                    kAudioDeviceTransportTypeBluetooth,
                ]
            )
        )
    }

    func testAggregateWithoutBluetoothSubDevicesDoesNotClassifyAsBluetooth() {
        XCTAssertFalse(
            AudioDeviceManager.isBluetoothInput(
                transport: kAudioDeviceTransportTypeAggregate,
                activeSubDeviceTransports: [
                    kAudioDeviceTransportTypeBuiltIn,
                    kAudioDeviceTransportTypeUSB,
                ]
            )
        )
        XCTAssertFalse(
            AudioDeviceManager.isBluetoothInput(
                transport: kAudioDeviceTransportTypeAggregate,
                activeSubDeviceTransports: []
            )
        )
    }

    func testNonAggregateNonBluetoothIgnoresSubDeviceTransports() {
        XCTAssertFalse(
            AudioDeviceManager.isBluetoothInput(
                transport: kAudioDeviceTransportTypeUSB,
                activeSubDeviceTransports: [kAudioDeviceTransportTypeBluetooth]
            )
        )
    }

    func testBluetoothOutputStatePreservesUnknownTransport() {
        XCTAssertNil(
            AudioDeviceManager.bluetoothOutputState(
                transport: nil,
                activeSubDeviceTransports: []
            )
        )
    }

    func testBluetoothOutputStatePreservesUnknownAggregateSubDevices() {
        XCTAssertNil(
            AudioDeviceManager.bluetoothOutputState(
                transport: kAudioDeviceTransportTypeAggregate,
                activeSubDeviceTransports: nil
            )
        )
    }

    func testBluetoothOutputStateKeepsKnownNonBluetoothRouteSafe() {
        XCTAssertEqual(
            AudioDeviceManager.bluetoothOutputState(
                transport: kAudioDeviceTransportTypeUSB,
                activeSubDeviceTransports: nil
            ),
            false
        )
    }
}
