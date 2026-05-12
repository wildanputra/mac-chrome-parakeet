import AppKit
@preconcurrency import ApplicationServices
import os
import XCTest
@testable import MacParakeetCore

final class SelectionReplacementServiceTests: XCTestCase {
    func testReplaceViaAxSucceeds() async throws {
        let backend = FakeSelectionReplacementBackend(
            isTrusted: true,
            axWriteSucceeds: true
        )
        let service = SelectionReplacementService(backend: backend, postPasteDelay: .milliseconds(1))

        let path = try await service.replace(
            with: "polished",
            in: .ax(text: "raw", element: AXFocusedElement(AXUIElementCreateSystemWide()))
        )

        XCTAssertEqual(path, .ax)
        XCTAssertEqual(backend.lastAXText(), "polished")
        XCTAssertEqual(backend.cmdVPostCount(), 0)
    }

    func testReplaceFallsBackToPasteWhenAXFails() async throws {
        let backend = FakeSelectionReplacementBackend(
            isTrusted: true,
            axWriteSucceeds: false
        )
        let service = SelectionReplacementService(backend: backend, postPasteDelay: .milliseconds(1))

        let path = try await service.replace(
            with: "polished",
            in: .ax(text: "raw", element: AXFocusedElement(AXUIElementCreateSystemWide()))
        )

        XCTAssertEqual(path, .clipboardPaste)
        XCTAssertEqual(backend.lastClipboardText(), "polished")
        XCTAssertEqual(backend.cmdVPostCount(), 1)
        XCTAssertGreaterThanOrEqual(backend.restoreCount(), 1)
    }

    func testReplaceClipboardContextRestoresSnapshot() async throws {
        let backend = FakeSelectionReplacementBackend(
            isTrusted: true,
            axWriteSucceeds: false
        )
        let service = SelectionReplacementService(backend: backend, postPasteDelay: .milliseconds(1))
        let snapshot = PasteboardSnapshot(items: nil, originalChangeCount: 42)

        let path = try await service.replace(
            with: "polished",
            in: .clipboard(text: "raw", savedClipboard: snapshot)
        )

        XCTAssertEqual(path, .clipboardPaste)
        XCTAssertGreaterThanOrEqual(backend.restoreCount(), 1)
        XCTAssertEqual(backend.lastRestoredChangeCount(), 42)
    }

    func testReplaceThrowsOnEmptyContext() async {
        let backend = FakeSelectionReplacementBackend(isTrusted: true)
        let service = SelectionReplacementService(backend: backend, postPasteDelay: .milliseconds(1))

        do {
            _ = try await service.replace(with: "polished", in: .empty)
            XCTFail("Expected throw")
        } catch let error as SelectionReplacementError {
            XCTAssertEqual(error, .allPathsFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testReplaceRestoresClipboardOnPasteboardWriteFailure() async {
        let backend = FakeSelectionReplacementBackend(
            isTrusted: true,
            axWriteSucceeds: false,
            pasteboardWriteSucceeds: false
        )
        let service = SelectionReplacementService(backend: backend, postPasteDelay: .milliseconds(1))
        let snapshot = PasteboardSnapshot(items: nil, originalChangeCount: 99)

        do {
            _ = try await service.replace(
                with: "polished",
                in: .clipboard(text: "raw", savedClipboard: snapshot)
            )
            XCTFail("Expected pasteboardWriteFailed")
        } catch let error as SelectionReplacementError {
            XCTAssertEqual(error, .pasteboardWriteFailed)
            XCTAssertGreaterThanOrEqual(backend.restoreCount(), 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Fake Backend

/// Thread-safe state container so a Sendable backend can record calls and
/// the test can read them back without coupling to actor isolation.
final class FakeSelectionReplacementBackend: SelectionReplacementBackend, @unchecked Sendable {
    private let trusted: Bool
    private let axWriteSucceedsValue: Bool
    private let pasteboardWriteSucceedsValue: Bool
    private let lock = OSAllocatedUnfairLock<State>(initialState: State())

    private struct State {
        var axTexts: [String] = []
        var clipboardTexts: [String] = []
        var cmdVPosts: Int = 0
        var restoreSnapshots: [PasteboardSnapshot] = []
    }

    init(
        isTrusted: Bool,
        axWriteSucceeds: Bool = false,
        pasteboardWriteSucceeds: Bool = true
    ) {
        self.trusted = isTrusted
        self.axWriteSucceedsValue = axWriteSucceeds
        self.pasteboardWriteSucceedsValue = pasteboardWriteSucceeds
    }

    func isAccessibilityTrusted() -> Bool { trusted }

    func writeSelectionViaAX(_ text: String, element: AXUIElement) -> Bool {
        lock.withLock { $0.axTexts.append(text) }
        return axWriteSucceedsValue
    }

    @MainActor
    func writePasteboardString(_ text: String) -> Bool {
        lock.withLock { $0.clipboardTexts.append(text) }
        return pasteboardWriteSucceedsValue
    }

    @MainActor
    func postCmdV() throws {
        lock.withLock { $0.cmdVPosts += 1 }
    }

    @MainActor
    func restoreSnapshot(_ snapshot: PasteboardSnapshot) {
        lock.withLock { $0.restoreSnapshots.append(snapshot) }
    }

    // Test accessors

    func lastAXText() -> String? {
        lock.withLock { $0.axTexts.last }
    }

    func lastClipboardText() -> String? {
        lock.withLock { $0.clipboardTexts.last }
    }

    func cmdVPostCount() -> Int {
        lock.withLock { $0.cmdVPosts }
    }

    func restoreCount() -> Int {
        lock.withLock { $0.restoreSnapshots.count }
    }

    func lastRestoredChangeCount() -> Int? {
        lock.withLock { $0.restoreSnapshots.last?.originalChangeCount }
    }
}
