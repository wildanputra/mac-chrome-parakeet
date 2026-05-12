import AppKit
import ApplicationServices
import Foundation
import OSLog

// MARK: - Public Types

public enum SelectionReplacementPath: String, Sendable, Equatable {
    /// AX `kAXSelectedTextAttribute` write succeeded.
    case ax
    /// Paste-back via Cmd+V succeeded (either AX-write was unavailable or
    /// failed, or the original capture was `.clipboard`).
    case clipboardPaste
}

public enum SelectionReplacementError: Error, LocalizedError, Sendable {
    case accessibilityNotAuthorized
    case eventSourceUnavailable
    case pasteboardWriteFailed
    case eventPostingFailed
    case allPathsFailed

    public var errorDescription: String? {
        switch self {
        case .accessibilityNotAuthorized:
            return "Accessibility permission required to replace selection."
        case .eventSourceUnavailable:
            return "Could not create a CGEventSource for paste simulation."
        case .pasteboardWriteFailed:
            return "Could not write replacement text to the clipboard."
        case .eventPostingFailed:
            return "Failed to post Cmd+V keystroke."
        case .allPathsFailed:
            return "Selection replacement failed via both AX-write and clipboard paste."
        }
    }
}

// MARK: - Backend Protocol

protocol SelectionReplacementBackend: Sendable {
    func isAccessibilityTrusted() -> Bool
    /// Attempt to write the new text via AX. Returns `true` on success
    /// (set + verifying read-back returned the same text). Returns `false`
    /// when AX rejects the write or the read-back doesn't match.
    func writeSelectionViaAX(_ text: String, element: AXUIElement) -> Bool

    @MainActor
    func writePasteboardString(_ text: String) -> Bool

    @MainActor
    func postCmdV() throws

    @MainActor
    func restoreSnapshot(_ snapshot: PasteboardSnapshot)
}

// MARK: - Service

/// Replaces the user's current selection with new text. AX-write first
/// (zero side effects on clipboard), paste-back via Cmd+V otherwise.
///
/// See `docs/research/transforms-design-2026-05.md` §2 — the design accepts
/// a small clipboard race window (~500ms) in exchange for a working
/// universal path across every macOS app. Snapshot restoration runs even on
/// failure to keep the user's pre-transform clipboard contents safe.
public actor SelectionReplacementService {
    /// Time to wait for the paste to land before restoring the original
    /// clipboard snapshot. 500ms matches the conventional "Espanso / Raycast"
    /// value and the Gemini-review feedback on the capture side.
    public static let defaultPostPasteDelay: Duration = .milliseconds(500)

    private let backend: any SelectionReplacementBackend
    private let postPasteDelay: Duration
    private let logger: Logger

    public init() {
        self.init(backend: SystemSelectionReplacementBackend())
    }

    init(
        backend: any SelectionReplacementBackend,
        postPasteDelay: Duration = SelectionReplacementService.defaultPostPasteDelay,
        logger: Logger = Logger(subsystem: "com.macparakeet.core", category: "SelectionReplacementService")
    ) {
        self.backend = backend
        self.postPasteDelay = postPasteDelay
        self.logger = logger
    }

    /// Replace the user's selection (captured via `SelectionCaptureService`)
    /// with `newText`. Returns the path used, or throws on hard failure.
    @discardableResult
    public func replace(
        with newText: String,
        in context: SelectionCaptureResult
    ) async throws -> SelectionReplacementPath {
        switch context {
        case .ax(_, let focused):
            // AX-write is the no-side-effect path. If it succeeds, we're done.
            if backend.writeSelectionViaAX(newText, element: focused.element) {
                return .ax
            }
            // Fall through to clipboard paste (no original snapshot — the AX
            // capture path didn't touch the clipboard, so we capture a fresh
            // snapshot here to preserve whatever the user had on it).
            let freshSnapshot = await snapshotPasteboardForFallback()
            try await pasteAndRestore(newText: newText, snapshot: freshSnapshot)
            return .clipboardPaste

        case .clipboard(_, let savedSnapshot):
            // Original capture already hijacked the clipboard. Paste then
            // restore the snapshot we promised the user we'd put back.
            try await pasteAndRestore(newText: newText, snapshot: savedSnapshot)
            return .clipboardPaste

        case .empty, .failed:
            throw SelectionReplacementError.allPathsFailed
        }
    }

    @MainActor
    private func snapshotPasteboardForFallback() -> PasteboardSnapshot {
        let pb = NSPasteboard.general
        let items = pb.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
        return PasteboardSnapshot(items: items, originalChangeCount: pb.changeCount)
    }

    private func pasteAndRestore(
        newText: String,
        snapshot: PasteboardSnapshot
    ) async throws {
        let pasteboardWriteSucceeded = await writePasteboardStringOnMain(newText)
        guard pasteboardWriteSucceeded else {
            // Try to put the user's clipboard back even on this failure.
            await restoreSnapshotOnMain(snapshot)
            throw SelectionReplacementError.pasteboardWriteFailed
        }

        do {
            try await postCmdVOnMain()
        } catch let error as SelectionReplacementError {
            await restoreSnapshotOnMain(snapshot)
            throw error
        } catch {
            await restoreSnapshotOnMain(snapshot)
            throw SelectionReplacementError.eventPostingFailed
        }

        // Give the host app time to consume the paste before restoring the
        // saved snapshot. Short enough that the user doesn't see a stale
        // pasteboard, long enough that slow apps (Slack, Mail) finish.
        try? await Task.sleep(for: postPasteDelay)
        await restoreSnapshotOnMain(snapshot)
    }

    @MainActor
    private func writePasteboardStringOnMain(_ text: String) -> Bool {
        backend.writePasteboardString(text)
    }

    @MainActor
    private func postCmdVOnMain() throws {
        try backend.postCmdV()
    }

    @MainActor
    private func restoreSnapshotOnMain(_ snapshot: PasteboardSnapshot) {
        backend.restoreSnapshot(snapshot)
    }
}

// MARK: - System Backend

// `@unchecked Sendable` for the same reason as
// `SystemSelectionCaptureBackend`: the `NSPasteboard` reference is only used
// from `@MainActor` methods. The AX write path is pure.
struct SystemSelectionReplacementBackend: SelectionReplacementBackend, @unchecked Sendable {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func writeSelectionViaAX(_ text: String, element: AXUIElement) -> Bool {
        let setStatus = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        guard setStatus == .success else {
            return false
        }
        // Verify by reading back the value attribute (best-effort — if the
        // field doesn't expose `kAXValue`, we just trust the set succeeded).
        var raw: CFTypeRef?
        let readStatus = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &raw
        )
        if readStatus == .success, let raw, let value = raw as? String {
            // The field's full value should *contain* the inserted text. Equality
            // is too strict because the host app may already have surrounding text.
            return value.contains(text) || value == text
        }
        return true
    }

    @MainActor
    func writePasteboardString(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    @MainActor
    func postCmdV() throws {
        guard AXIsProcessTrusted() else {
            throw SelectionReplacementError.accessibilityNotAuthorized
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw SelectionReplacementError.eventSourceUnavailable
        }
        let vKeyCode: CGKeyCode = 9  // ANSI 'V'
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            throw SelectionReplacementError.eventPostingFailed
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    @MainActor
    func restoreSnapshot(_ snapshot: PasteboardSnapshot) {
        guard let items = snapshot.items, !items.isEmpty else {
            pasteboard.clearContents()
            return
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }
}
