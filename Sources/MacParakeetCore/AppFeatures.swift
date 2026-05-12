import Foundation

/// Compile-time feature gates. Flip a single literal to expose or hide a feature
/// without touching every call site. Release builds should set these to the
/// shipping configuration before tagging a version.
public enum AppFeatures {
    /// Meeting Recording (ADR-014). When `false`, all meeting recording entry
    /// points are hidden: Transcribe tile, menu-bar "Start Recording", global
    /// meeting hotkey, settings card, library filter, onboarding step, and the
    /// screen recording permission row. Data model, services, and tests remain
    /// intact.
    public static let meetingRecordingEnabled: Bool = true

    /// Calendar auto-start (ADR-017). When `false`, all calendar entry points
    /// are hidden: onboarding calendar step, Settings calendar subsection,
    /// search-index calendar entry, and the auto-start coordinator never starts
    /// polling. CalendarService, MeetingAutoStartCoordinator, models, and tests
    /// remain intact — only the surfaces that would invoke them are gated.
    /// Hidden in v0.6 pending hands-on E2E validation; flip to `true` in a
    /// point release once the auto-start flow has been exercised against real
    /// calendars.
    public static let calendarEnabled: Bool = false

    /// Transforms spike (docs/research/transforms-design-2026-05.md, Phase 1
    /// AX-coverage spike). When `false`, the entire Transforms pipeline is
    /// hidden: no Opt+Ctrl+1 hotkey, no SelectionCaptureService/Executor wiring
    /// from AppEnvironment, no floating progress panel. Flipping to `true` is
    /// development-only — the spike is intentionally rough (hardcoded Polish
    /// prompt, no management UI, hardcoded hotkey including Ctrl to avoid
    /// collisions during dev). Used to answer the single question: does the
    /// macOS AX API reliably return selected text in mainstream apps?
    public static let transformsSpikeEnabled: Bool = false
}
