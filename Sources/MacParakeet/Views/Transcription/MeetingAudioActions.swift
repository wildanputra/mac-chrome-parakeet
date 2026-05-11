import AppKit
import Foundation
import MacParakeetCore
import UniformTypeIdentifiers

/// UI-layer wrappers around `MeetingAudioFile` that surface the meeting
/// audio file to the user: reveal in Finder and "Save Audio As…".
///
/// These are deliberately small: the underlying URL resolution and
/// filename derivation live in `MacParakeetCore.MeetingAudioFile` so
/// they remain unit-testable without AppKit.
@MainActor
enum MeetingAudioActions {

    /// File extension MacParakeet writes meeting audio with. Single
    /// source of truth so the Save panel default name and the underlying
    /// storage stay in lockstep.
    static let fileExtension = "m4a"

    // MARK: - Reveal in Finder

    /// Reveals the mixed-track meeting audio file in Finder. Returns
    /// `true` on success, `false` if the source file is missing (in
    /// which case the caller should disable the action upstream).
    @discardableResult
    static func revealInFinder(_ transcription: Transcription) -> Bool {
        guard MeetingAudioFile.isAvailable(for: transcription),
              let url = MeetingAudioFile.mixedAudioURL(for: transcription) else {
            return false
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    // MARK: - Save Audio As…

    /// Outcome of a "Save Audio As…" interaction.
    enum SaveOutcome {
        /// User chose a destination and the file was copied successfully.
        case saved(destination: URL)
        /// User cancelled the Save panel.
        case cancelled
        /// Source audio was missing — caller should normally prevent this
        /// by disabling the action when `MeetingAudioFile.isAvailable`
        /// returns false, but we surface it explicitly for completeness.
        case sourceUnavailable
    }

    /// Presents an `NSSavePanel` and copies the meeting audio file to
    /// the user's chosen destination. Throws on copy failure (disk full,
    /// permissions, etc.).
    static func runSaveAudioPanel(
        for transcription: Transcription
    ) async throws -> SaveOutcome {
        guard MeetingAudioFile.isAvailable(for: transcription),
              let sourceURL = MeetingAudioFile.mixedAudioURL(for: transcription) else {
            return .sourceUnavailable
        }

        let panel = NSSavePanel()
        panel.title = "Save Meeting Audio"
        panel.prompt = "Save"
        panel.message = "Choose where to save the meeting audio file."
        panel.nameFieldLabel = "Save As:"
        panel.nameFieldStringValue =
            "\(MeetingAudioFile.suggestedExportStem(for: transcription)).\(fileExtension)"
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.canCreateDirectories = true
        panel.showsTagField = false
        if let downloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first {
            panel.directoryURL = downloads
        }

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return .cancelled
        }

        // Copy off the main actor so a large meeting (multi-hundred-MB
        // m4a) doesn't stall the UI thread mid-save.
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            // NSSavePanel already prompts the user about overwrite, so
            // a clobber here is intentional. Remove first so copyItem
            // doesn't trip on "file exists".
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }.value

        return .saved(destination: destinationURL)
    }
}
