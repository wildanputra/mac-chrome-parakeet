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

    /// Regression: if the user copies content during the post-paste window,
    /// we must NOT restore the saved snapshot — that would silently destroy
    /// what they just put on the clipboard. The fix gates `restoreSnapshot`
    /// on `currentChangeCount() == ourChangeCount`.
    func testReplaceSkipsRestoreWhenUserCopiesMidTransform() async throws {
        let backend = FakeSelectionReplacementBackend(
            isTrusted: true,
            axWriteSucceeds: false,
            pasteboardWriteSucceeds: true,
            simulateUserCopyAfterWrite: true
        )
        let service = SelectionReplacementService(backend: backend, postPasteDelay: .milliseconds(1))
        let snapshot = PasteboardSnapshot(items: nil, originalChangeCount: 42)

        _ = try await service.replace(
            with: "polished",
            in: .clipboard(text: "raw", savedClipboard: snapshot)
        )

        XCTAssertEqual(backend.cmdVPostCount(), 1, "Paste should still happen — we only suppress restore")
        XCTAssertEqual(backend.restoreCount(), 0, "Restore must be skipped — user wrote to clipboard mid-transform")
    }
}

// MARK: - Fake Backend

/// Thread-safe state container so a Sendable backend can record calls and
/// the test can read them back without coupling to actor isolation.
final class FakeSelectionReplacementBackend: SelectionReplacementBackend, @unchecked Sendable {
    private let trusted: Bool
    private let axWriteSucceedsValue: Bool
    private let pasteboardWriteSucceedsValue: Bool
    private let simulateUserCopyAfterWrite: Bool
    private let lock = OSAllocatedUnfairLock<State>(initialState: State())

    private struct State {
        var axTexts: [String] = []
        var clipboardTexts: [String] = []
        var cmdVPosts: Int = 0
        var restoreSnapshots: [PasteboardSnapshot] = []
        /// Simulated pasteboard changeCount. Bumped on `writePasteboardString`
        /// (mirroring `setString`'s behavior in production) and optionally
        /// bumped a second time on the second `currentChangeCount` read to
        /// simulate a concurrent user copy mid-transform.
        var changeCount: Int = 0
        var currentChangeCountCallNumber: Int = 0
    }

    init(
        isTrusted: Bool,
        axWriteSucceeds: Bool = false,
        pasteboardWriteSucceeds: Bool = true,
        simulateUserCopyAfterWrite: Bool = false
    ) {
        self.trusted = isTrusted
        self.axWriteSucceedsValue = axWriteSucceeds
        self.pasteboardWriteSucceedsValue = pasteboardWriteSucceeds
        self.simulateUserCopyAfterWrite = simulateUserCopyAfterWrite
    }

    func isAccessibilityTrusted() -> Bool { trusted }

    func writeSelectionViaAX(_ text: String, element: AXUIElement) -> Bool {
        lock.withLock { $0.axTexts.append(text) }
        return axWriteSucceedsValue
    }

    @MainActor
    func writePasteboardString(_ text: String) -> Bool {
        lock.withLock { state in
            state.clipboardTexts.append(text)
            if pasteboardWriteSucceedsValue {
                state.changeCount += 1
            }
        }
        return pasteboardWriteSucceedsValue
    }

    @MainActor
    func postCmdV() throws {
        lock.withLock { $0.cmdVPosts += 1 }
    }

    @MainActor
    func currentChangeCount() -> Int {
        let simulateBump = simulateUserCopyAfterWrite
        return lock.withLock { state in
            state.currentChangeCountCallNumber += 1
            // Service reads currentChangeCount twice: once right after our
            // own write (to capture ourChangeCount) and once during the
            // restore check. The simulated "user copied mid-transform"
            // scenario bumps on the second call.
            if simulateBump && state.currentChangeCountCallNumber >= 2 {
                return state.changeCount + 1
            }
            return state.changeCount
        }
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
