import Foundation

/// Resolves the on-disk audio file for a finalized meeting recording and
/// suggests an export-friendly filename.
///
/// Meeting transcriptions store the mixed-track `meeting.m4a` path in
/// `Transcription.filePath`. The file itself lives at
/// `~/Library/Application Support/MacParakeet/meeting-recordings/<sessionUUID>/meeting.m4a`
/// (see `MeetingAudioStorageWriter`).
///
/// This helper is the single seam between UI surfaces ("Show in Finder",
/// "Save Audio As…") and that on-disk layout, so future changes to the
/// folder structure only ripple through one file.
public enum MeetingAudioFile {

    // MARK: - URL resolution

    /// Returns the mixed-track audio URL for a meeting transcription, or
    /// `nil` for non-meeting sources or transcriptions without a stored
    /// file path. Does NOT check on-disk existence; call
    /// `isAvailable(for:)` when that matters.
    public static func mixedAudioURL(for transcription: Transcription) -> URL? {
        guard transcription.sourceType == .meeting else { return nil }
        guard let path = transcription.filePath,
              !path.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    /// Whether the mixed-track audio file is reachable on disk. Returns
    /// false for non-meeting transcriptions or when the recorded file is
    /// missing (deleted, moved, or recovery still in progress).
    public static func isAvailable(
        for transcription: Transcription,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let url = mixedAudioURL(for: transcription) else { return false }
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    // MARK: - Filename derivation

    /// Suggested filename stem (no extension) for "Save Audio As…" flows.
    ///
    /// Strategy:
    /// - When an LLM-derived title is present, use `"<title> - yyyy-MM-dd"`
    ///   so two meetings titled `"Q4 planning sync"` on different days
    ///   stay distinct in a Downloads folder.
    /// - Otherwise fall back to `transcription.fileName`, which the
    ///   recording service already populates as a date-stamped display
    ///   name (`"Meeting May 11, 2026 at 1:32 PM"`); appending another
    ///   date would just create noise.
    public static func suggestedExportStem(for transcription: Transcription) -> String {
        let derived = transcription.derivedTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !derived.isEmpty {
            let datePart = isoDateFormatter.string(from: transcription.createdAt)
            return sanitize("\(derived) - \(datePart)")
        }
        let fallback = transcription.fileName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitize(fallback.isEmpty ? "Meeting" : fallback)
    }

    // MARK: - Internals

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func sanitize(_ input: String) -> String {
        // Strip characters that would either break filenames on macOS
        // (`/`, NUL) or read poorly in a Save panel preview. We keep
        // unicode, punctuation, and emoji — Finder handles those fine.
        let disallowed = CharacterSet(charactersIn: "/:\\\0\"")
        let cleaned = input
            .components(separatedBy: disallowed)
            .joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return cleaned.isEmpty ? "Meeting" : cleaned
    }
}
