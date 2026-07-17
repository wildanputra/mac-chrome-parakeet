import Foundation

/// Maps diarized meeting speakers ("Speaker 1", "Speaker 2", …) to real
/// participant names using the browser extension's active-speaker timeline
/// (ADR-029 speaker attribution).
///
/// The two inputs describe the same meeting from different vantage points:
/// - Diarization clusters the *system* audio into anonymous voices with
///   recording-relative segment times.
/// - The meeting page knows *who* is highlighted as speaking at each wall-clock
///   instant, but hears nothing.
///
/// Overlap voting joins them: for each diarized speaker, sum the overlap
/// between that speaker's segments and each name's spans; the dominant name
/// wins the label when it clears the confidence guardrails. Everything here is
/// pure and deterministic — the caller supplies the recording's wall-clock
/// start to place both timelines on one axis.
///
/// Failure direction is always "keep the anonymous label": a missed mapping
/// leaves "Speaker 1" (today's behavior); only a confident match relabels.
public enum MeetingSpeakerNameMapper {
    /// Minimum absolute overlap between a diarized speaker and its dominant
    /// name. Below this the evidence is a blip (one interjection, an indicator
    /// flicker), not attribution.
    static let minimumDominantOverlapMs = 3000
    /// The dominant name must own at least this share of the speaker's total
    /// name-overlapped time, or the tile indicators disagree too much to call.
    static let minimumDominantShare = 0.6
    /// The dominant name's overlap must also cover this share of the speaker's
    /// total speech, so a name seen briefly next to a long-speaking voice
    /// doesn't claim it.
    static let minimumSpeechCoverage = 0.25

    /// Returns a relabeled roster, or `nil` when nothing met the confidence
    /// bar (caller should then change nothing). Only diarized speakers are
    /// candidates — the `microphone` ("Me") and `system` ("Others") source
    /// rows keep their labels, since the page cannot know who the local
    /// microphone is better than the app does.
    public static func relabeledSpeakers(
        speakers: [SpeakerInfo],
        diarizationSegments: [DiarizationSegmentRecord],
        events: [ChromeBridgeSpeakerEvent],
        recordingStartedAt: Date
    ) -> [SpeakerInfo]? {
        let spans = normalizedSpans(events: events, recordingStartedAt: recordingStartedAt)
        guard !spans.isEmpty else { return nil }

        let sourceIDs: Set<String> = [AudioSource.microphone.rawValue, AudioSource.system.rawValue]
        var updated = speakers
        var changed = false

        for index in speakers.indices {
            let speaker = speakers[index]
            guard !sourceIDs.contains(speaker.id) else { continue }

            let segments = diarizationSegments.filter { $0.speakerId == speaker.id }
            guard !segments.isEmpty else { continue }
            let speechMs = segments.reduce(0) { $0 + max(0, $1.endMs - $1.startMs) }
            guard speechMs > 0 else { continue }

            var overlapByName: [String: Int] = [:]
            for segment in segments {
                for span in spans {
                    let overlap = min(segment.endMs, span.endMs) - max(segment.startMs, span.startMs)
                    if overlap > 0 {
                        overlapByName[span.name, default: 0] += overlap
                    }
                }
            }
            guard let dominant = overlapByName.max(by: { lhs, rhs in
                lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
            }) else { continue }

            let totalNameOverlap = overlapByName.values.reduce(0, +)
            guard dominant.value >= minimumDominantOverlapMs,
                  Double(dominant.value) >= minimumDominantShare * Double(totalNameOverlap),
                  Double(dominant.value) >= minimumSpeechCoverage * Double(speechMs)
            else { continue }

            if updated[index].label != dominant.key {
                updated[index].label = dominant.key
                changed = true
            }
        }

        return changed ? updated : nil
    }

    private struct Span {
        let name: String
        let startMs: Int
        let endMs: Int
    }

    /// Converts wall-clock event spans to recording-relative milliseconds,
    /// dropping malformed spans, empty names, and self-referential names the
    /// page renders for the local user (their words are already labeled by
    /// the microphone source).
    private static func normalizedSpans(
        events: [ChromeBridgeSpeakerEvent],
        recordingStartedAt: Date
    ) -> [Span] {
        let startWallMs = Int64((recordingStartedAt.timeIntervalSince1970 * 1000).rounded())
        var spans: [Span] = []
        spans.reserveCapacity(events.count)
        for event in events {
            let name = event.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 100 else { continue }
            guard !isSelfName(name) else { continue }
            let relStart = event.startMs - startWallMs
            let relEnd = event.endMs - startWallMs
            guard relEnd > relStart, relEnd > 0 else { continue }
            // Int overflow is unreachable for sane clocks (offsets are bounded
            // by recording length), but clamp defensively anyway.
            spans.append(Span(
                name: name,
                startMs: Int(clamping: max(0, relStart)),
                endMs: Int(clamping: relEnd)
            ))
        }
        return spans
    }

    /// Meeting pages label the local participant's own tile "You" (localized).
    /// Cover the languages the meeting products themselves commonly render;
    /// an uncovered locale degrades to attributing the mic speaker's name to
    /// a system-side voice only if the indicators actually overlap enough to
    /// clear the guardrails, which cross-talk rarely does.
    private static let selfNames: Set<String> = [
        "you", "tú", "tu", "vous", "du", "sie", "você", "voce", "tú (you)",
        "あなた", "自分", "你", "您", "당신", "나",
    ]

    private static func isSelfName(_ name: String) -> Bool {
        selfNames.contains(name.lowercased())
    }
}
