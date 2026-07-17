import Foundation
import MacParakeetCore
import OSLog

/// App-side endpoint of the Chrome extension meeting bridge (ADR-029).
///
/// Observes `ChromeBridgeChannel.commandNotificationName` distributed
/// notifications posted by `macparakeet-cli chrome-native-host`, applies the
/// opt-in gate, and routes start/stop/state requests into the meeting
/// recording flow. Every relayed request gets exactly one reply notification
/// (state or error) correlated by the request id, so the host can resolve the
/// extension's pending call or synthesize `app_unreachable` on timeout.
///
/// The opt-in preference (`ChromeBridgeConfiguration.enabledKey`, default off)
/// is read *per command*, not at start: the CLI writes the shared defaults
/// suite from another process, which posts no in-app change notification, and
/// re-checking a single UserDefaults bool per command is far cheaper than any
/// cross-process invalidation scheme. When disabled, state queries still get a
/// truthful `bridgeEnabled: false` reply (so the extension can show "bridge
/// disabled" instead of "app not running"), while start/stop are refused.
@MainActor
final class ChromeBridgeCoordinator {
    private let logger = Logger(subsystem: "com.macparakeet", category: "ChromeBridge")

    /// Closures to the meeting recording flow — passed in rather than the
    /// concrete coordinator so this file doesn't gain a reverse dependency on
    /// `MeetingRecordingFlowCoordinator` (and so tests can stub them).
    private let isBridgeEnabled: @MainActor () -> Bool
    private let isRecordingActive: @MainActor () -> Bool
    private let flowStateLabel: @MainActor () -> String
    /// Returns `true` when the start was accepted (recording flow left idle).
    private let onStartRequested: @MainActor (_ title: String?) -> Bool
    /// Returns `true` when a stop was actually issued.
    private let onStopRequested: @MainActor () -> Bool
    /// Persists a relabeled speaker roster for a saved transcription —
    /// `TranscriptionRepository.updateSpeakers` in production (which also
    /// refreshes stored segment labels), a spy in tests.
    private let persistSpeakers: @MainActor (UUID, [SpeakerInfo]) throws -> Void
    /// Reply transport — the distributed notification post in production,
    /// a capture array in tests.
    private let postReply: @MainActor (ChromeBridgeReply) -> Void

    /// Active-speaker spans reported by the extension during the current
    /// (or most recently ended) recording, wall-clock epoch ms. Cleared when
    /// a new recording starts and when a meeting transcription harvests them.
    private var speakerActivityEvents: [ChromeBridgeSpeakerEvent] = []
    /// Wall-clock instant the current recording window began, set from the
    /// flow's `onRecordingBegan` callback so manual/hotkey/calendar starts
    /// are windowed just as precisely as bridge-initiated ones.
    private var speakerActivityRecordingStartedAt: Date?
    /// Hard cap so a runaway page can't grow memory: ~8h of one-second spans.
    private static let maxSpeakerActivityEvents = 30_000

    // `nonisolated(unsafe)` so the nonisolated `deinit` can read it to
    // unregister the observer. Write-only after start()/stop(); mutation
    // always happens on the main actor — no race.
    nonisolated(unsafe) private var commandObserver: NSObjectProtocol?

    init(
        isBridgeEnabled: @escaping @MainActor () -> Bool = { ChromeBridgeConfiguration.isEnabled() },
        isRecordingActive: @escaping @MainActor () -> Bool,
        flowStateLabel: @escaping @MainActor () -> String,
        onStartRequested: @escaping @MainActor (_ title: String?) -> Bool,
        onStopRequested: @escaping @MainActor () -> Bool,
        persistSpeakers: @escaping @MainActor (UUID, [SpeakerInfo]) throws -> Void = { _, _ in },
        postReply: (@MainActor (ChromeBridgeReply) -> Void)? = nil
    ) {
        self.isBridgeEnabled = isBridgeEnabled
        self.isRecordingActive = isRecordingActive
        self.flowStateLabel = flowStateLabel
        self.onStartRequested = onStartRequested
        self.onStopRequested = onStopRequested
        self.persistSpeakers = persistSpeakers
        self.postReply = postReply ?? { reply in
            guard let payload = try? ChromeBridgeCodec.encodeString(reply) else { return }
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name(ChromeBridgeChannel.replyNotificationName),
                object: nil,
                userInfo: [ChromeBridgeChannel.payloadUserInfoKey: payload],
                deliverImmediately: true
            )
        }
    }

    deinit {
        if let observer = commandObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    // MARK: - Lifecycle

    func start() {
        // Defensive: no bridge without the meeting recording feature — same
        // gate the configurer applies, kept here so a forgotten call site
        // can't expose recording control that the UI hides.
        guard AppFeatures.meetingRecordingEnabled else { return }
        guard commandObserver == nil else { return }

        commandObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(ChromeBridgeChannel.commandNotificationName),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract the payload before hopping actors: `Notification` is
            // not Sendable, the payload String is.
            guard
                let payload = notification.userInfo?[ChromeBridgeChannel.payloadUserInfoKey] as? String
            else { return }
            Task { @MainActor [weak self] in self?.handleCommand(payloadString: payload) }
        }
        logger.info("Chrome bridge coordinator started")
    }

    func stop() {
        if let observer = commandObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            commandObserver = nil
        }
        logger.info("Chrome bridge coordinator stopped")
    }

    // MARK: - Command routing

    /// Internal (not private) so tests can drive routing without real
    /// distributed notifications; production reaches this only via `start()`.
    func handleCommand(payloadString: String) {
        let request: ChromeBridgeRequest
        do {
            request = try ChromeBridgeCodec.decodeRequest(payloadString: payloadString)
        } catch {
            // No decodable id to correlate — the host's timeout will answer.
            logger.warning("Undecodable chrome bridge command: \(error.localizedDescription, privacy: .public)")
            return
        }

        let enabled = isBridgeEnabled()
        switch request.type {
        case .hello, .getState:
            replyState(to: request.id, enabled: enabled)

        case .startRecording:
            guard enabled else {
                replyDisabled(to: request.id)
                return
            }
            guard !isRecordingActive() else {
                // Already recording — first-to-arrive wins (ADR-017/024
                // symmetry). Current state is the honest answer, not an error.
                replyState(to: request.id, enabled: enabled)
                return
            }
            let title = resolvedTitle(for: request)
            guard onStartRequested(title) else {
                postReply(.error(
                    replyTo: request.id,
                    code: .startRejected,
                    message: "MacParakeet is busy finishing another recording. Try again in a moment."
                ))
                return
            }
            let platform = request.platform ?? "unknown"
            logger.info("Chrome bridge started meeting recording (platform: \(platform, privacy: .public))")
            replyState(to: request.id, enabled: enabled)

        case .stopRecording:
            guard enabled else {
                replyDisabled(to: request.id)
                return
            }
            if onStopRequested() {
                logger.info("Chrome bridge stopped meeting recording")
            }
            replyState(to: request.id, enabled: enabled)

        case .speakerActivity:
            guard enabled else {
                replyDisabled(to: request.id)
                return
            }
            if isRecordingActive(), let events = request.events, !events.isEmpty {
                appendSpeakerActivity(events)
            }
            replyState(to: request.id, enabled: enabled)

        case .launchApp:
            // Host-side concern; if it ever leaks through, answering with
            // state is harmless and keeps the extension's promise resolved.
            replyState(to: request.id, enabled: enabled)
        }
    }

    // MARK: - Speaker attribution (ADR-029)

    /// Called from the meeting flow's `onRecordingBegan` callback: opens a
    /// fresh speaker-activity window for this recording and discards spans
    /// from any prior meeting.
    func recordingDidStart() {
        speakerActivityRecordingStartedAt = Date()
        speakerActivityEvents = []
    }

    private func appendSpeakerActivity(_ events: [ChromeBridgeSpeakerEvent]) {
        // A recording that started before the app launched (crash recovery)
        // or before this coordinator existed has no window; without a start
        // instant the spans can't be placed on the recording's axis.
        guard speakerActivityRecordingStartedAt != nil else { return }
        let headroom = Self.maxSpeakerActivityEvents - speakerActivityEvents.count
        guard headroom > 0 else { return }
        speakerActivityEvents.append(contentsOf: events.prefix(headroom))
    }

    /// Relabels a just-completed meeting transcription's diarized speakers
    /// with participant names observed by the extension, when the overlap
    /// evidence is confident (`MeetingSpeakerNameMapper`). Persists through
    /// `persistSpeakers` (which also refreshes stored segment labels) and
    /// returns the updated in-memory transcription for immediate
    /// presentation, or `nil` when nothing changed.
    ///
    /// Back-to-back guard: while another recording is already active, its
    /// window has replaced the completed meeting's window (ADR-015 queues
    /// transcriptions behind live recordings), so applying would attribute
    /// the wrong meeting's names — skip instead. The completed meeting keeps
    /// anonymous labels, which is today's behavior.
    func applyPendingSpeakerNames(to transcription: Transcription) -> Transcription? {
        guard transcription.sourceType == .meeting else { return nil }
        guard !isRecordingActive() else { return nil }
        guard let startedAt = speakerActivityRecordingStartedAt, !speakerActivityEvents.isEmpty else {
            return nil
        }
        // Harvest exactly once: this meeting is finished with these spans
        // whether or not the mapper finds a confident match.
        let events = speakerActivityEvents
        speakerActivityEvents = []
        speakerActivityRecordingStartedAt = nil

        guard let speakers = transcription.speakers,
              let relabeled = MeetingSpeakerNameMapper.relabeledSpeakers(
                  speakers: speakers,
                  diarizationSegments: transcription.diarizationSegments ?? [],
                  events: events,
                  recordingStartedAt: startedAt
              )
        else { return nil }

        do {
            try persistSpeakers(transcription.id, relabeled)
        } catch {
            logger.error("Failed to persist speaker names: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        var updated = transcription
        updated.speakers = relabeled
        updated.transcriptSegments = TranscriptSegmentRecord.updatingSpeakerLabels(
            in: updated.transcriptSegments,
            using: relabeled
        )
        logger.info("Chrome bridge attributed speaker names to meeting transcription")
        return updated
    }

    // MARK: - Replies

    private func replyState(to requestID: String, enabled: Bool) {
        postReply(.state(
            replyTo: requestID,
            bridgeEnabled: enabled,
            recording: isRecordingActive(),
            flowState: flowStateLabel()
        ))
    }

    private func replyDisabled(to requestID: String) {
        postReply(.error(
            replyTo: requestID,
            code: .bridgeDisabled,
            message: "The Chrome bridge is disabled. Enable it with: macparakeet-cli config set chrome-extension on"
        ))
    }

    /// Page titles are best-effort; fall back to a readable platform name so
    /// bridge-started meetings are never blank-titled while the auto-titler
    /// runs. `nil` (unknown platform, no title) preserves existing naming.
    private func resolvedTitle(for request: ChromeBridgeRequest) -> String? {
        if let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        switch request.platform {
        case "google_meet": return "Google Meet"
        case "zoom": return "Zoom Meeting"
        case "teams": return "Teams Meeting"
        case "webex": return "Webex Meeting"
        default: return nil
        }
    }
}
