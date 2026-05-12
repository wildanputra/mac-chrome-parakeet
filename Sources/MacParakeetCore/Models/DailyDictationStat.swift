import Foundation

/// Per-day rollup of completed dictations. Keyed by local-calendar day (`day`,
/// midnight in the user's current timezone) so the heatmap reflects "what days
/// did you dictate" as the user experiences them, not UTC days.
///
/// Survives `Clear History` — incremented in the same write transaction as
/// `lifetime_dictation_stats`, mirroring the singleton-counter pattern from
/// issue #124 but per-day. Backfilled from existing `dictations` rows on
/// migration so users with history don't see an empty heatmap on first launch.
public struct DailyDictationStat: Sendable, Equatable {
    public let day: Date
    public let count: Int
    public let words: Int
    public let durationMs: Int

    public init(day: Date, count: Int, words: Int, durationMs: Int) {
        self.day = day
        self.count = count
        self.words = words
        self.durationMs = durationMs
    }
}
