# ADR-029: Chrome Extension Meeting Bridge

> Status: **ACCEPTED — v1 implementation in this ADR's PR.**
> Default off / opt-in via `macparakeet-cli config set chrome-extension on`
> (the extension installer runs this for the user).
> Date: 2026-07-16
> Related: ADR-002 (local-only), ADR-014 (meeting recording), ADR-017
> (calendar auto-start), ADR-024 (activity-based meeting detection — this ADR
> answers its open question "browser meeting-URL detection without screen
> access"), ADR-027 (product north star).

## Context

MacParakeet already records any meeting a Mac can hear: meeting capture mixes
the microphone and system audio, so a Google Meet tab in Chrome is just as
recordable as the Zoom desktop app. What the app *cannot* see is **when** a
browser meeting starts, **what** it is called, and **when** it ends:

- ADR-024's activity detection can tell that *a browser* holds the microphone,
  but explicitly rules out reading tab content, so a browser earns the weakest
  trust tier and meeting titles are unavailable.
- ADR-017's calendar auto-start only covers scheduled meetings that live on
  the user's own calendar.
- The result: for the very common "click a Meet/Zoom/Teams link in Chrome"
  case, the user is back to remembering to press record, and the saved meeting
  is titled by the auto-titler instead of the real meeting name.

A browser extension is the one place where meeting state is first-party data:
the page's own DOM says "in a call," the tab title carries the meeting name,
and the user installing the extension is an explicit opt-in. This closes
ADR-024's browser gap **without** violating the no-screen-content invariant —
the user granted the extension exactly the visibility it needs, scoped to
meeting domains only.

## Decision

Ship a **Chrome (Chromium) MV3 extension** plus a **native-messaging bridge**
into the existing meeting recording flow. The extension is a *remote control
and metadata source*; all capture, transcription, storage, and artifacts stay
in MacParakeet exactly as ADR-014/019/025 built them. We deliberately do NOT
record audio in the browser (`chrome.tabCapture`): the app's capture path
already handles mic+system mixing, echo cancellation (ADR-028), crash
resilience (ADR-019), and retention policy — a second recorder in JS would be
a strictly worse duplicate (same reasoning as `integrations/README.md`'s
"thin wrapper, not a second implementation" rule).

```
┌────────────────────────── Chrome ──────────────────────────┐
│ content scripts (meet / zoom wc / teams / webex domains)   │
│   └── in-call heuristics + meeting title → service worker  │
│ service worker                                             │
│   └── chrome.runtime.connectNative("com.macparakeet.       │
│        chrome_bridge") ── native messaging (stdio) ──┐     │
│ popup UI: status, Record/Stop, join-prompt toggles   │     │
└──────────────────────────────────────────────────────┼─────┘
                                                       ▼
                    macparakeet-cli chrome-native-host (per-connection process)
                       │  posts command payloads / observes state payloads
                       ▼  DistributedNotificationCenter (local IPC)
┌──────────────────────────────────────────────────────────────┐
│ MacParakeet.app                                              │
│  ChromeBridgeCoordinator (@MainActor, app layer)             │
│    ├── gate: AppFeatures.meetingRecordingEnabled             │
│    │        + ChromeBridgeConfiguration.enabled (default off)│
│    ├── start_recording → MeetingRecordingFlowCoordinator     │
│    │        .startRecording(title:, trigger: .chromeExtension)│
│    ├── stop_recording  → .stopRecording(trigger:)            │
│    └── get_state       → replies current flow state          │
└──────────────────────────────────────────────────────────────┘
```

### 1. Extension detects; app records

Content scripts run only on recognized meeting domains (Google Meet, Zoom web
client, Microsoft Teams, Webex) and evaluate layered DOM heuristics for
"in a call" plus a best-effort meeting title. Detection drives:

- a toolbar badge and popup status,
- an optional (default on) "Record this meeting?" Chrome notification when a
  call starts — mirroring ADR-024's prompt-first philosophy: never
  auto-record without an explicit user action or a separate deeper opt-in,
- an optional auto-stop when the extension itself started the recording and
  the call ends (leave button pressed / tab closed).

Selector heuristics rot as vendors ship UI changes; that is priced in. A
missed detection degrades to the popup's always-available manual Record
button, never to a broken recording.

### 2. Native messaging host = the CLI binary

`macparakeet-cli chrome-native-host` (hidden subcommand) implements Chrome's
native messaging protocol: 4-byte little-endian length-prefixed JSON frames on
stdin/stdout, one process per extension connection, exits on stdin EOF. It is
installed via a wrapper script + per-browser host manifest written by
`integrations/chrome-extension/native-host/install.sh` (native messaging
manifests cannot pass argv, hence the wrapper).

Reusing the CLI binary means: no new build product, the Homebrew/app-bundle
install story already exists, and the host inherits the CLI's telemetry optout
and versioning contract.

### 3. Host ↔ app IPC: distributed notifications

The host relays extension commands to the app by posting
`DistributedNotificationCenter` notifications carrying a single JSON-string
payload, and observes the app's state notifications for replies
(request-id correlated). Chosen over a Unix socket / XPC for v1 because it is
tiny, run-loop native, and adds no listening endpoint or file permission
surface. Trust model, stated plainly:

- Any local process in the user's session can post the same notification.
  The blast radius is bounded: commands can only start/stop a meeting
  recording — a *visible* action (floating pill, menu bar state) the user
  sees immediately, carrying no content and returning no transcript data.
  The state replies expose only flow state (recording or not).
- The app ignores all bridge commands unless the user opted in
  (`chrome-extension` config key, default off).
- Meeting URLs never cross the bridge; only a platform label and the
  page-provided title do. Nothing leaves the device (ADR-002 intact — the
  extension makes no network requests at all).

If a future surface needs richer data (transcripts to the extension, live
state push), that is the point to graduate to an authenticated local socket —
recorded here so the upgrade path is deliberate.

### 4. App-side coordinator

`ChromeBridgeCoordinator` (app layer, `@MainActor`, owned like
`MeetingAutoStartCoordinator` via `AppEnvironmentConfigurer`) observes the
command notification, checks the opt-in preference *at command receipt* (so
`macparakeet-cli config set chrome-extension on` applies without relaunch),
and routes to the existing `MeetingRecordingFlowCoordinator`. Start requests
while a recording is active reply with current state instead of erroring —
first-to-arrive wins, symmetric with ADR-017/024.

State is pull-based in v1: the host sends `get_state` on popup open, after
commands, and on a slow heartbeat while a meeting tab exists or a recording is
believed active. This avoids threading push callbacks through the flow
coordinator and self-heals around manual starts/stops made in the app. The
app-side observer is a single distributed-notification registration — ~0%
idle cost (PR #467 lesson).

### 5. Provenance

New trigger case `chrome_extension` on `TelemetryMeetingRecordingTrigger`,
`TelemetryMeetingOperationTrigger`, and `MeetingStartContext.TriggerKind`, so
saved meetings record that they were started from the browser. These are
property *values* on existing allowlisted events, not new event names, so no
website-allowlist deploy is required. No new telemetry events ship in v1.

## Consequences

### Positive

- One-click (or prompted) recording for Meet/Zoom/Teams/Webex in any
  Chromium browser, with the real meeting title on the saved artifact.
- Closes ADR-024's browser blind spot via explicit user opt-in instead of
  screen scraping.
- Zero new capture/transcription code paths — the extension is a thin
  controller; reliability work (ADR-019/025/028) is inherited, not duplicated.
- Local-first intact: no extension network egress, no content over the
  bridge, opt-in at two layers (install script + config key).

### Negative

- **DOM heuristics are brittle.** Meeting vendors change markup without
  notice. Mitigation: layered selectors, manual record always available,
  heuristics isolated in one content-script table per platform.
- **Distributed notifications are unauthenticated local IPC.** Acceptable for
  start/stop-only commands (see §3); revisit before any richer surface.
- **A second install artifact.** The extension + host manifest must be
  installed and kept in sync with the CLI. Mitigated by `install.sh` and a
  versioned `v` field in every bridge message.
- **Chrome Web Store packaging is out of scope for v1** — the extension loads
  unpacked (developer mode) with a pinned extension ID via the manifest `key`
  field so host manifests stay valid across installs.

## Out of scope (explicitly not building in v1)

- Browser-side audio capture (`tabCapture` / `getDisplayMedia`) — the app
  records; see §Decision.
- Live transcript / notes surfaces inside the extension.
- Auto-record-without-prompt mode. The notification prompt or an explicit
  popup click is required, mirroring ADR-024's `.prompt` default posture.
- Safari / Firefox ports (Safari needs an App Extension target; Firefox
  native messaging manifests differ). The message protocol is
  browser-agnostic on purpose.

## Invariants

- Local-first (ADR-002): no network egress from any bridge component; audio
  and transcripts never cross the bridge.
- Manual, hotkey, and calendar flows unchanged; bridge commands no-op into a
  state reply when a recording is already active.
- Default off; the app acts on bridge commands only after explicit opt-in.
- The CLI surface change (new hidden subcommand) is additive — semver MINOR.
