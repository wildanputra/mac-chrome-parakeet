import ArgumentParser
import Foundation
import MacParakeetCore

/// `macparakeet-cli chrome-native-host` — Chrome native messaging endpoint for
/// the MacParakeet browser extension (ADR-029).
///
/// Chrome spawns this process when the extension connects
/// (`chrome.runtime.connectNative`), speaks length-prefixed JSON frames over
/// stdin/stdout, and closes stdin when the extension disconnects. The host is
/// a stateless relay: extension requests are re-posted to the running app as
/// distributed notifications, app replies flow back as frames. The host never
/// touches audio, the database, or STT models.
///
/// Hidden from `--help`: users never invoke this directly — the browser does,
/// via the host manifest written by
/// `integrations/chrome-extension/native-host/install.sh`.
struct ChromeNativeHostCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chrome-native-host",
        abstract:
            "Chrome native messaging host for the MacParakeet browser extension (launched by the browser).",
        shouldDisplay: false
    )

    func run() throws {
        let host = ChromeNativeHost()
        host.runUntilStdinCloses()
    }
}

/// The relay loop. Threading model, spelled out because four contexts meet:
/// - A dedicated reader `Thread` blocks on stdin and accumulates frames.
/// - A dedicated bridge `Thread` registers the distributed-notification
///   observer and pumps its run loop — distributed notifications are
///   delivered via the run loop of the registering thread, and the CLI's
///   async entry point gives no guarantee that `run()` sits on a pumped main
///   run loop.
/// - `hostQueue` (serial) owns all mutable state (pending reply timeouts)
///   and all stdout writes, so no write interleaving is possible.
/// - The calling thread parks until stdin EOF; if it happens to be the main
///   thread it pumps the main run loop too, as a hedge for macOS versions
///   that bind distributed delivery to the main run loop.
///
/// The park/pump loops wake every 250 ms to notice shutdown — a deliberate,
/// trivial idle cost for a process that only exists while the extension is
/// connected.
///
/// `@unchecked Sendable`: mutable state is confined to `hostQueue` (pending
/// map) or guarded by `shutdownLock` (the shutdown flag).
final class ChromeNativeHost: @unchecked Sendable {
    /// How long to wait for the app to answer a relayed request before
    /// synthesizing `app_unreachable`. The app replies immediately from the
    /// main actor — the timeout only fires when the app isn't running, so
    /// favor snappy popup feedback.
    private static let replyTimeoutSeconds: TimeInterval = 2.0
    /// Extra headroom after `launch_app` before the follow-up state probe:
    /// cold app launches need a moment before observers are registered.
    private static let launchProbeDelaySeconds: TimeInterval = 2.5
    /// Shutdown-poll cadence for the parked/pumping threads.
    private static let shutdownPollSeconds: TimeInterval = 0.25

    private let hostQueue = DispatchQueue(label: "com.macparakeet.chrome-native-host")
    private let observerQueue: OperationQueue
    private let stdout = FileHandle.standardOutput
    private let stdin = FileHandle.standardInput

    /// Request ids relayed to the app and still awaiting a reply, mapped to
    /// their timeout work items. Confined to `hostQueue`.
    private var pendingReplyTimeouts: [String: DispatchWorkItem] = [:]

    private let shutdownLock = NSLock()
    private var shutdownRequested = false

    init() {
        let queue = OperationQueue()
        queue.underlyingQueue = hostQueue
        queue.maxConcurrentOperationCount = 1
        observerQueue = queue
    }

    /// Blocks the calling thread until the browser closes stdin.
    func runUntilStdinCloses() {
        startBridgeRunLoopThread()
        startStdinReaderThread()

        if Thread.isMainThread {
            while !isShutdownRequested() {
                _ = RunLoop.current.run(
                    mode: .default,
                    before: Date(timeIntervalSinceNow: Self.shutdownPollSeconds)
                )
            }
        } else {
            while !isShutdownRequested() {
                Thread.sleep(forTimeInterval: Self.shutdownPollSeconds)
            }
        }
        // Drain hostQueue so a reply that raced shutdown still reaches Chrome
        // (best effort — Chrome may already have closed the pipe).
        hostQueue.sync {}
    }

    // MARK: - Shutdown flag

    private func isShutdownRequested() -> Bool {
        shutdownLock.lock()
        defer { shutdownLock.unlock() }
        return shutdownRequested
    }

    private func requestShutdown() {
        shutdownLock.lock()
        shutdownRequested = true
        shutdownLock.unlock()
    }

    // MARK: - Bridge thread (distributed notification delivery)

    private func startBridgeRunLoopThread() {
        let thread = Thread { [weak self] in
            guard let self else { return }
            // Register on this thread so distributed delivery binds to the
            // run loop we are about to pump. The observer's block itself
            // executes on `observerQueue` (→ hostQueue).
            let observer = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(ChromeBridgeChannel.replyNotificationName),
                object: nil,
                queue: self.observerQueue
            ) { [weak self] notification in
                guard
                    let payloadString = notification.userInfo?[ChromeBridgeChannel.payloadUserInfoKey] as? String
                else { return }
                self?.handleAppReply(payloadString)
            }
            while !self.isShutdownRequested() {
                _ = RunLoop.current.run(
                    mode: .default,
                    before: Date(timeIntervalSinceNow: Self.shutdownPollSeconds)
                )
            }
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        thread.name = "chrome-native-host-bridge"
        thread.start()
    }

    // MARK: - stdin frames

    private func startStdinReaderThread() {
        let thread = Thread { [weak self] in
            self?.readFramesUntilEOF()
        }
        thread.name = "chrome-native-host-stdin"
        thread.start()
    }

    private func readFramesUntilEOF() {
        var buffer = Data()
        while true {
            let chunk = stdin.availableData
            if chunk.isEmpty {
                break  // EOF — extension disconnected or browser quit.
            }
            buffer.append(chunk)
            do {
                while let frame = try NativeMessagingFrame.decodeFirst(from: buffer) {
                    buffer.removeFirst(frame.consumed)
                    let payload = frame.payload
                    hostQueue.async { [weak self] in
                        self?.handleIncoming(payload)
                    }
                }
            } catch {
                // Framing desync is unrecoverable — report and hang up.
                hostQueue.async { [weak self] in
                    self?.send(.error(
                        replyTo: nil,
                        code: .invalidRequest,
                        message: "Native messaging framing error: \(error)"
                    ))
                }
                break
            }
        }
        requestShutdown()
    }

    // MARK: - Request handling (hostQueue)

    private func handleIncoming(_ payload: Data) {
        let request: ChromeBridgeRequest
        do {
            request = try ChromeBridgeCodec.decodeRequest(payload)
        } catch {
            send(.error(replyTo: nil, code: .invalidRequest, message: "Undecodable bridge request: \(error)"))
            return
        }

        switch request.type {
        case .launchApp:
            launchAppAndProbe(request)
        case .hello, .getState, .startRecording, .stopRecording:
            relayToApp(request)
        }
    }

    private func relayToApp(_ request: ChromeBridgeRequest) {
        let payloadString: String
        do {
            payloadString = try ChromeBridgeCodec.encodeString(request)
        } catch {
            send(.error(replyTo: request.id, code: .invalidRequest, message: "Failed to re-encode request: \(error)"))
            return
        }

        armReplyTimeout(requestID: request.id)
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(ChromeBridgeChannel.commandNotificationName),
            object: nil,
            userInfo: [ChromeBridgeChannel.payloadUserInfoKey: payloadString],
            deliverImmediately: true
        )
    }

    private func armReplyTimeout(requestID: String) {
        pendingReplyTimeouts[requestID]?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.pendingReplyTimeouts.removeValue(forKey: requestID) != nil else { return }
            self.send(.error(
                replyTo: requestID,
                code: .appUnreachable,
                message: "MacParakeet did not respond. Launch the app and make sure the Chrome bridge is enabled."
            ))
        }
        pendingReplyTimeouts[requestID] = timeout
        hostQueue.asyncAfter(deadline: .now() + Self.replyTimeoutSeconds, execute: timeout)
    }

    /// `launch_app` is handled host-side: `open -g -b` launches (or activates)
    /// the app without stealing focus from the meeting tab, then a delayed
    /// `get_state` probe under the same request id resolves the extension's
    /// pending call with either real state or `app_unreachable`.
    private func launchAppAndProbe(_ request: ChromeBridgeRequest) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-b", ChromeBridgeChannel.appBundleIdentifier]
        do {
            try process.run()
        } catch {
            send(.error(
                replyTo: request.id,
                code: .appUnreachable,
                message: "Failed to launch MacParakeet: \(error.localizedDescription)"
            ))
            return
        }
        hostQueue.asyncAfter(deadline: .now() + Self.launchProbeDelaySeconds) { [weak self] in
            self?.relayToApp(ChromeBridgeRequest(id: request.id, type: .getState))
        }
    }

    // MARK: - App replies (observer hops to hostQueue)

    private func handleAppReply(_ payloadString: String) {
        guard let reply = try? ChromeBridgeCodec.decodeReply(payloadString: payloadString) else {
            return  // Not ours / newer schema — ignore rather than propagate noise.
        }
        if let replyTo = reply.replyTo {
            guard let timeout = pendingReplyTimeouts.removeValue(forKey: replyTo) else {
                // Another host instance's correlation id (one host per
                // browser profile can coexist); forwarding duplicates would
                // confuse the extension's pending-request bookkeeping.
                return
            }
            timeout.cancel()
        }
        send(reply)
    }

    // MARK: - stdout frames (hostQueue)

    private func send(_ reply: ChromeBridgeReply) {
        guard let payload = try? ChromeBridgeCodec.encode(reply),
              let framed = try? NativeMessagingFrame.encode(payload)
        else {
            return
        }
        // write(contentsOf:) throws on a closed pipe (browser quit mid-reply);
        // shutdown is already in flight at that point, so swallow it.
        try? stdout.write(contentsOf: framed)
    }
}
