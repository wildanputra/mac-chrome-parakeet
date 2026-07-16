# MacParakeet Meeting Recorder — Chrome extension

Record Google Meet, Zoom (web client), Microsoft Teams, and Webex calls in any
Chromium browser with the local MacParakeet app. The extension is a **remote
control, not a recorder**: it detects when you join a call, offers to record,
and tells MacParakeet to start/stop its normal meeting recording (microphone +
system audio, echo-cancelled, crash-resilient). Audio and transcripts never
leave your Mac, and the extension itself makes **zero network requests**.

Architecture and trust model: [ADR-029](../../spec/adr/029-chrome-extension-meeting-bridge.md).

```
content scripts ──▶ service worker ──▶ native messaging host
 (call detection)     (badge, prompts)   (macparakeet-cli chrome-native-host)
                                              │ distributed notifications
                                              ▼
                                        MacParakeet.app meeting recording
```

## Install

Prerequisites: MacParakeet.app (or the standalone `macparakeet-cli`) with the
`chrome-native-host` command (CLI ≥ the version in this checkout).

1. **Register the native messaging host** (also enables the opt-in bridge
   preference — this is the consent step; the app ignores the extension until
   it runs):

   ```bash
   integrations/chrome-extension/native-host/install.sh
   ```

   It auto-detects `macparakeet-cli` on `$PATH` or in the app bundle, writes a
   wrapper + host manifest for every Chromium-family browser found (Chrome,
   Edge, Brave, Arc, Vivaldi, Chromium), and runs
   `macparakeet-cli config set chrome-extension on`.

2. **Load the extension**: open `chrome://extensions`, enable *Developer
   mode*, click *Load unpacked*, and select this
   `integrations/chrome-extension/` directory. The extension ID is pinned to
   `jeiadfgefgjejfblpgpgiihakgpcebfm` by the `key` field in `manifest.json`,
   so the host manifest's `allowed_origins` matches no matter where the
   directory lives.

3. **Restart the browser** once so it picks up the native messaging host.

To remove everything: `native-host/install.sh --uninstall` and delete the
extension from `chrome://extensions`.

## Use

- **Join a call** on meet.google.com, `*.zoom.us/wc` (web client),
  teams.microsoft.com / teams.live.com, or `*.webex.com`. A notification asks
  "Record this meeting?" — click *Start recording*. The meeting title from the
  tab becomes the recording's title.
- **Or click the parakeet toolbar icon** and press *Start recording* — works
  with or without a detected call, exactly like pressing record in the app.
- **Stop** from the popup, from the app (pill / menu bar) — or let auto-stop
  end it when you leave a call the extension started.
- Popup toggles:
  - *Ask to record when a call starts* (default on) — the join notification.
  - *Stop when I leave a call I recorded from here* (default on) — auto-stop
    applies only to recordings this extension started, never to recordings
    you started in the app.

The toolbar badge shows `REC` while MacParakeet records and `•` when a call is
detected but not being recorded.

## Troubleshooting

| Popup says | Fix |
|---|---|
| "The native bridge isn’t installed yet" | Run `native-host/install.sh`, restart the browser. |
| "MacParakeet isn’t running" | Click *Launch MacParakeet* (or open the app). |
| "The Chrome bridge is switched off" | `macparakeet-cli config set chrome-extension on` |
| Call not detected | Vendors change their DOM without notice; detection selectors live in `content/meeting-detector.js`. Manual record from the popup always works. |

## Privacy

- No `host_permissions` beyond the four meeting domains; no `tabs`
  permission; no analytics; no remote code; no network access of any kind.
- What crosses the bridge to the app: a platform label ("google_meet"…), the
  tab title, and start/stop/state commands. Meeting URLs never leave the
  browser.
- The app acts on bridge commands only while the `chrome-extension` config
  key is `on` (default `off`).

## Development notes

- Vanilla JS, no build step — the directory is loaded unpacked as-is.
- The wire protocol (`v: 1`) is defined in
  `Sources/MacParakeetCore/Services/ChromeBridge/ChromeBridgeProtocol.swift`
  and mirrored by `background.js`. Keep them in lockstep; additive fields
  only within a version.
- The `key` in `manifest.json` only pins the unpacked-extension ID; there is
  no private key in the repo and none is needed. If you fork and want a
  different ID, generate a new RSA-2048 SPKI, base64 it into `key`, and
  update `EXTENSION_ID` in `native-host/install.sh`.
- Icons are generated (no design-tool source); regenerate by adapting the
  PNG-writer snippet in the PR that introduced this directory if needed.
