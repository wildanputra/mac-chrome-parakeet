import Foundation

/// Wire contract for the Chrome extension meeting bridge (ADR-029).
///
/// Three hops share these types:
/// 1. Extension ⇄ native host: Chrome native messaging (length-prefixed JSON
///    frames on stdio, `NativeMessagingFrame`).
/// 2. Native host ⇄ app: `DistributedNotificationCenter` notifications whose
///    userInfo carries one JSON-string payload (`ChromeBridgeChannel`).
/// 3. Both payloads are the same `ChromeBridgeRequest` / `ChromeBridgeReply`
///    JSON, so the host relays bytes rather than re-mapping schemas.
///
/// Every message carries `v` (`ChromeBridgeChannel.schemaVersion`). Additive
/// fields are allowed within a version; renames/removals bump it.
public enum ChromeBridgeChannel {
    public static let schemaVersion = 1

    /// Host → app. Posted by `macparakeet-cli chrome-native-host` for every
    /// extension request that targets the app.
    public static let commandNotificationName = "com.macparakeet.chrome-bridge.command"

    /// App → host. Carries `ChromeBridgeReply` payloads. Replies to a specific
    /// request set `replyTo`; the host also treats un-addressed state replies
    /// as broadcast state.
    public static let replyNotificationName = "com.macparakeet.chrome-bridge.reply"

    /// The single userInfo key on both notifications. The value is the JSON
    /// message as a `String` — one plist-safe scalar, no nested dictionary
    /// bridging concerns.
    public static let payloadUserInfoKey = "payload"

    /// Bundle identifier the host uses to launch the app on request
    /// (`open -b`). Matches `AppPaths.preferencesSuiteName` / the DMG build's
    /// `CFBundleIdentifier`.
    public static let appBundleIdentifier = "com.macparakeet.MacParakeet"
}

/// Opt-in gate for acting on bridge commands. Default off (ADR-029 §3): the
/// app observes the command notification but refuses everything except a
/// polite "disabled" state reply until the user enables the key — via the
/// extension installer or `macparakeet-cli config set chrome-extension on`.
/// Checked at command receipt, not at app launch, so a CLI-side change
/// applies without relaunching the GUI.
public enum ChromeBridgeConfiguration {
    public static let enabledKey = "chromeExtensionBridgeEnabled"

    public static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? false
    }
}

/// One observed span of a named participant actively speaking, as reported by
/// the extension's in-page detection (ADR-029 speaker attribution). Times are
/// wall-clock epoch **milliseconds** (`Date.now()` in the page) — the browser
/// and the app share the machine clock, and the app converts to
/// recording-relative offsets using the recording's start instant.
public struct ChromeBridgeSpeakerEvent: Codable, Sendable, Equatable {
    /// Participant display name as the meeting page renders it.
    public let name: String
    public let startMs: Int64
    public let endMs: Int64

    public init(name: String, startMs: Int64, endMs: Int64) {
        self.name = name
        self.startMs = startMs
        self.endMs = endMs
    }
}

/// A request originating from the extension. `launchApp` is handled entirely
/// by the native host (the app cannot launch itself); all other kinds are
/// relayed to the app.
public struct ChromeBridgeRequest: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case hello
        case getState = "get_state"
        case startRecording = "start_recording"
        case stopRecording = "stop_recording"
        case speakerActivity = "speaker_activity"
        case launchApp = "launch_app"
    }

    public let v: Int
    /// Extension-generated correlation id echoed back as `replyTo`.
    public let id: String
    public let type: Kind
    /// Meeting title scraped from the page (best effort). Only meaningful for
    /// `.startRecording`. Meeting URLs deliberately never cross the bridge.
    public let title: String?
    /// Coarse platform label ("google_meet", "zoom", "teams", "webex") for
    /// title fallbacks and logging. Free-form by design — new platforms must
    /// not require a schema bump.
    public let platform: String?
    /// Active-speaker spans batched by the extension. Only meaningful for
    /// `.speakerActivity`.
    public let events: [ChromeBridgeSpeakerEvent]?

    public init(
        v: Int = ChromeBridgeChannel.schemaVersion,
        id: String,
        type: Kind,
        title: String? = nil,
        platform: String? = nil,
        events: [ChromeBridgeSpeakerEvent]? = nil
    ) {
        self.v = v
        self.id = id
        self.type = type
        self.title = title
        self.platform = platform
        self.events = events
    }
}

/// A reply or broadcast from the app (relayed verbatim to the extension), or
/// synthesized by the host itself (`appRunning: false` timeouts, framing
/// errors).
public struct ChromeBridgeReply: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case state
        case error
    }

    public enum ErrorCode: String, Codable, Sendable, Equatable {
        /// The opt-in preference is off; the command was not acted on.
        case bridgeDisabled = "bridge_disabled"
        /// The app did not answer within the host's reply timeout.
        case appUnreachable = "app_unreachable"
        /// The recording flow rejected the request (busy stopping/finishing).
        case startRejected = "start_rejected"
        /// Malformed frame or undecodable request.
        case invalidRequest = "invalid_request"
    }

    public let v: Int
    public let type: Kind
    /// Correlation id of the request this answers; `nil` for broadcast state.
    public let replyTo: String?
    // State fields (`type == .state`).
    public let bridgeEnabled: Bool?
    public let recording: Bool?
    /// Coarse flow state label ("idle", "starting", "recording", "stopping",
    /// "finishing"). Informational — the extension keys behavior off
    /// `recording` only.
    public let flowState: String?
    // Error fields (`type == .error`).
    public let code: ErrorCode?
    public let message: String?

    public init(
        v: Int = ChromeBridgeChannel.schemaVersion,
        type: Kind,
        replyTo: String?,
        bridgeEnabled: Bool? = nil,
        recording: Bool? = nil,
        flowState: String? = nil,
        code: ErrorCode? = nil,
        message: String? = nil
    ) {
        self.v = v
        self.type = type
        self.replyTo = replyTo
        self.bridgeEnabled = bridgeEnabled
        self.recording = recording
        self.flowState = flowState
        self.code = code
        self.message = message
    }

    public static func state(
        replyTo: String?,
        bridgeEnabled: Bool,
        recording: Bool,
        flowState: String
    ) -> ChromeBridgeReply {
        ChromeBridgeReply(
            type: .state,
            replyTo: replyTo,
            bridgeEnabled: bridgeEnabled,
            recording: recording,
            flowState: flowState
        )
    }

    public static func error(replyTo: String?, code: ErrorCode, message: String) -> ChromeBridgeReply {
        ChromeBridgeReply(type: .error, replyTo: replyTo, code: code, message: message)
    }
}

/// JSON codec shared by every hop. Encoding sorts keys so payloads are
/// deterministic (stable tests, diffable logs); decoding drops unknown fields
/// by Codable default, which is what lets older builds tolerate additive
/// same-version messages.
public enum ChromeBridgeCodec {
    public static func encode(_ request: ChromeBridgeRequest) throws -> Data {
        try encoder().encode(request)
    }

    public static func encode(_ reply: ChromeBridgeReply) throws -> Data {
        try encoder().encode(reply)
    }

    public static func decodeRequest(_ data: Data) throws -> ChromeBridgeRequest {
        try JSONDecoder().decode(ChromeBridgeRequest.self, from: data)
    }

    public static func decodeReply(_ data: Data) throws -> ChromeBridgeReply {
        try JSONDecoder().decode(ChromeBridgeReply.self, from: data)
    }

    public static func encodeString(_ request: ChromeBridgeRequest) throws -> String {
        String(decoding: try encode(request), as: UTF8.self)
    }

    public static func encodeString(_ reply: ChromeBridgeReply) throws -> String {
        String(decoding: try encode(reply), as: UTF8.self)
    }

    public static func decodeRequest(payloadString: String) throws -> ChromeBridgeRequest {
        try decodeRequest(Data(payloadString.utf8))
    }

    public static func decodeReply(payloadString: String) throws -> ChromeBridgeReply {
        try decodeReply(Data(payloadString.utf8))
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

/// Chrome native messaging framing: each message is a 4-byte *native-endian*
/// (little-endian on every supported Mac) UInt32 byte length followed by that
/// many bytes of UTF-8 JSON. Pure functions so the stdio loop in the CLI host
/// stays a thin shell around testable logic.
public enum NativeMessagingFrame {
    /// Chrome rejects host→browser messages over 1 MB; we apply the same cap
    /// inbound as a sanity bound — bridge messages are a few hundred bytes.
    public static let maxMessageBytes = 1_048_576

    public enum FrameError: Error, Equatable {
        case messageTooLarge(bytes: Int)
    }

    public static func encode(_ payload: Data) throws -> Data {
        guard payload.count <= maxMessageBytes else {
            throw FrameError.messageTooLarge(bytes: payload.count)
        }
        var length = UInt32(payload.count).littleEndian
        var framed = withUnsafeBytes(of: &length) { Data($0) }
        framed.append(payload)
        return framed
    }

    /// Attempts to decode one complete frame from the front of `buffer`.
    /// Returns `nil` when the buffer does not yet hold a complete frame
    /// (caller keeps accumulating); returns the payload plus the total number
    /// of bytes consumed otherwise. Throws when the declared length exceeds
    /// `maxMessageBytes` — the stream is unrecoverable at that point because
    /// framing sync is lost.
    public static func decodeFirst(from buffer: Data) throws -> (payload: Data, consumed: Int)? {
        guard buffer.count >= 4 else { return nil }
        // Data slices keep their parent's indices; normalize via prefix copy.
        let header = [UInt8](buffer.prefix(4))
        let length = UInt32(header[0])
            | (UInt32(header[1]) << 8)
            | (UInt32(header[2]) << 16)
            | (UInt32(header[3]) << 24)
        guard length <= UInt32(maxMessageBytes) else {
            throw FrameError.messageTooLarge(bytes: Int(length))
        }
        let total = 4 + Int(length)
        guard buffer.count >= total else { return nil }
        let start = buffer.startIndex
        let payload = Data(buffer[buffer.index(start, offsetBy: 4)..<buffer.index(start, offsetBy: total)])
        return (payload: payload, consumed: total)
    }
}
