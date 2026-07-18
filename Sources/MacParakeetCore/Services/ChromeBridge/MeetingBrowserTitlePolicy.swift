import Foundation

/// Decides whether a browser-reported meeting name may replace a meeting
/// recording's current title (ADR-029 §6).
///
/// The rule mirrors `MeetingTitleGenerator`'s own overwrite policy so the two
/// title sources can never fight over a name a human (or a better source)
/// chose: only fallback-shaped titles are replaceable — the date-stamped
/// "Meeting Jun 17, 2026 at 09:59" default, plus the generic platform labels
/// the bridge itself uses when a page's title has not resolved yet at record
/// start ("Google Meet", "Zoom Meeting", …).
public enum MeetingBrowserTitlePolicy {
    /// Platform-label fallbacks `ChromeBridgeCoordinator` substitutes when a
    /// start request carries no page title. A later real meeting name should
    /// upgrade these.
    static let platformFallbackTitles: Set<String> = [
        "google meet",
        "zoom meeting",
        "teams meeting",
        "webex meeting",
    ]

    public static func canReplaceTitle(_ currentTitle: String) -> Bool {
        let normalized = currentTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if platformFallbackTitles.contains(normalized) {
            return true
        }
        return MeetingTitleGenerator.shouldReplaceFallbackMeetingTitle(currentTitle)
    }

    /// Normalizes a page-provided meeting name into something safe to store
    /// as a recording title; returns `nil` when it isn't usable.
    public static func normalizedBrowserTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let collapsed = title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty, collapsed.count <= 120 else { return nil }
        // A page title that IS one of the platform fallbacks adds nothing.
        guard !platformFallbackTitles.contains(collapsed.lowercased()) else { return nil }
        return collapsed
    }
}
