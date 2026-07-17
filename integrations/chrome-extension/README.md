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

### Prerequisite: a bridge-capable build (from source, for now)

Until a tagged release ships the bridge, **both sides must come from this
branch** — released Homebrew/app-bundle binaries have neither the
`chrome-native-host` CLI command nor the app-side bridge listener:

```bash
git clone <your fork> && cd <checkout>
swift build -c release --product macparakeet-cli   # → .build/release/macparakeet-cli
scripts/dev/run_app.sh                             # runs the app from source
```

Note that `swift build` never installs anything onto your `$PATH` — the CLI
binary lives inside the (hidden) `.build/` directory, which is why a fresh
clone doesn't appear to "have" `macparakeet-cli`. That's fine here:
`install.sh` below auto-detects the repo-local build and pins its absolute
path, preferring it over any older CLI on your `$PATH`. Sanity checks:

```bash
.build/release/macparakeet-cli chrome-native-host --help
.build/release/macparakeet-cli config get chrome-extension
```

1. **Register the native messaging host** (also enables the opt-in bridge
   preference — this is the consent step; the app ignores the extension until
   it runs):

   ```bash
   integrations/chrome-extension/native-host/install.sh
   ```

   It walks candidates in order — repo-local `.build/release` then
   `.build/debug`, then `$PATH`, then the app bundle — **skipping any CLI
   that predates the bridge** (with a note naming the skipped binary), writes
   a wrapper + host manifest for every Chromium-family browser found (Chrome,
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

### Speaker names in transcripts

While a recording runs, the extension also watches the meeting page's
active-speaker indicators and reports *named speaking spans* to the app. After
transcription, MacParakeet matches those spans against its diarized voices and
— when the overlap is confident — replaces "Speaker 1"-style labels with the
real participant names. This works for Google Meet, Teams, and Zoom web
(best-effort; Webex not yet). Low-confidence matches, missed page markup, or
meetings recorded without the extension simply keep today's anonymous labels,
and you can still rename speakers manually in the app.

## Troubleshooting

| Popup says | Fix |
|---|---|
| "The native bridge isn’t installed yet" | Run `native-host/install.sh`, restart the browser. |
| "MacParakeet isn’t running" | Click *Launch MacParakeet* (or open the app). Make sure the running app is built from this branch. |
| "The Chrome bridge is switched off" | `macparakeet-cli config set chrome-extension on` |
| Installer: "no bridge-capable macparakeet-cli found" (or it skips your installed CLI) | Your installed CLI predates the bridge. Build from this checkout: `swift build -c release --product macparakeet-cli`, then re-run the installer. |
| Call not detected | Vendors change their DOM without notice; detection selectors live in `content/meeting-detector.js`. Manual record from the popup always works. |
| Speakers still say "Speaker 1" | Name mapping is confidence-gated and selector-dependent (Meet/Teams/Zoom web only for now). Rename speakers manually in the transcript view as before. |

## Privacy

- No `host_permissions` beyond the four meeting domains; no `tabs`
  permission; no analytics; no remote code; no network access of any kind.
- What crosses the bridge to the app: a platform label ("google_meet"…), the
  tab title, start/stop/state commands, and — only while a recording is
  running — participant names with speaking time spans, used solely to label
  speakers in your local transcript. Meeting URLs never leave the browser,
  and nothing ever leaves your Mac.
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
