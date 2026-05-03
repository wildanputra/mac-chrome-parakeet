# Issue #108 — Transcription hotkeys (file + YouTube)

> Status: **COMPLETED** — file and YouTube transcription hotkeys are implemented; auto-copy stayed explicitly out of scope. Moved from `plans/active` on 2026-05-03.

Source: https://github.com/moona3k/macparakeet/issues/108

## Scope

Add optional global hotkeys for **Transcribe File…** and **Transcribe from YouTube…** so the user can skip the menu-bar click.

Auto-copy-to-clipboard (also requested in #108) is **out of scope**. It overlaps with the existing Copy button in the result view and the existing Auto-save-to-disk feature, and silently clobbering the user's clipboard is a UX hazard we'd rather not ship. Will respond on the issue.

Also unrelated: #52 (multiple hotkey profiles) — that's a bigger ask we're leaving for later.

## Design decisions

- **Two separate hotkeys.** Each action leads to a distinct UI (NSOpenPanel vs YouTube panel), so sharing one trigger makes no sense.
- **Default: disabled.** These flows already have a menu-bar entry; shipping with pre-claimed keys risks collisions with other apps on first launch.
- **Reuse `GlobalShortcutManager`** — same pattern as the meeting hotkey (`AppHotkeyCoordinator.setupMeetingHotkey`). One press → one action.
- **Conflict model**: no hotkey can equal any other configured (non-disabled) hotkey. Reuse `HotkeyRecorderView`'s validator closure with a clear "Already used by <name>." message. Mirrors the existing dictation ↔ meeting conflict UI.
- **Menu-bar items show the shortcut** when configured as a chord, using the existing `applyMeetingHotkeyToMenuItem` pattern (refactored into a generic helper).
- **Hotkey invokes the same code paths** the menu items do — no duplicate flow logic.

## File-by-file changes

| File | Change |
|------|--------|
| `Sources/MacParakeetCore/STT/HotkeyTrigger.swift` | Add `fileTranscriptionDefaultsKey` and `youtubeTranscriptionDefaultsKey` constants. No new preset (default `.disabled`). |
| `Sources/MacParakeetCore/AppNotifications.swift` | Add `macParakeetFileHotkeyTriggerDidChange`, `macParakeetYouTubeHotkeyTriggerDidChange`. |
| `Sources/MacParakeetCore/Services/TelemetryEvent.swift` | Add 2 `TelemetrySetting` cases: `.fileTranscriptionHotkey`, `.youtubeTranscriptionHotkey`. Uses existing `settingChanged` event name → no website allowlist change needed. |
| `Sources/MacParakeetViewModels/SettingsViewModel.swift` | Add `fileTranscriptionHotkeyTrigger` and `youtubeTranscriptionHotkeyTrigger` stored properties with `didSet` persistence + notification post + telemetry. Initialize from defaults in `init`. |
| `Sources/MacParakeet/App/AppHotkeyCoordinator.swift` | Add `fileHotkeyManager`, `youtubeHotkeyManager`; `setupFileHotkey()`, `setupYouTubeHotkey()`, `refreshFileHotkey()`, `refreshYouTubeHotkey()`. Extend conflict check so each setup bails if its trigger equals any other configured hotkey. Extend `refreshAllHotkeys` / `stopAll`. Add 2 new init callbacks. |
| `Sources/MacParakeet/App/AppSettingsObserverCoordinator.swift` | Observe the 2 new notifications; route to 2 new callbacks. |
| `Sources/MacParakeet/App/AppEnvironmentConfigurer.swift` | Pass 2 new closures into `AppHotkeyCoordinator` and expose on `Callbacks`. |
| `Sources/MacParakeet/AppDelegate.swift` | 2 new handlers (`triggerFileTranscriptionFromHotkey`, `triggerYouTubeTranscriptionFromHotkey`) that call into exposed `MenuBarCoordinator` methods. Hook up 2 new `settingsObserverCoordinator` callbacks that call `hotkeyCoordinator.refresh*Hotkey()` + `menuBarCoordinator.refreshTranscriptionHotkeyShortcuts()`. |
| `Sources/MacParakeet/App/MenuBarCoordinator.swift` | Store `transcribeFileMenuItem` and `transcribeYouTubeMenuItem` as refs. Extract `applyChordShortcut(_:to:)` helper (generalize `applyMeetingHotkeyToMenuItem`). Expose `invokeTranscribeFileFlow()` and `invokeTranscribeYouTubeFlow()` from the existing `@objc` handlers (share impl). Add `refreshTranscriptionHotkeyShortcuts()`. Take new trigger providers in the initializer. |
| `Sources/MacParakeet/Views/Settings/SettingsView.swift` | Inside `transcriptionCard`, above Speaker Detection, add two `HotkeyRecorderView` rows with validator closures that reject collisions with dictation, meeting, and the other transcription hotkey. Reuse existing `hotkeyConflictText` style for inline warnings. |
| `Tests/MacParakeetTests/SettingsViewModelTests.swift` (or existing file) | Persistence round-trip for both new triggers. |
| `Tests/MacParakeetTests/AppHotkeyCoordinatorTests.swift` (create if missing, else extend) | Conflict resolution: when file = dictation, file manager does not start. |

No spec or ADR change — additive convenience hotkeys.

## Edge cases

- **Hotkey pressed while main window/menu is front**: `GlobalShortcutManager` uses `.cgSessionEventTap`, fires regardless of key-window state. Good.
- **Hotkey pressed while a transcription is already running**: `transcribeFile` cancels the current task inside `beginNewTranscription` (`TranscriptionViewModel.swift:376`). Matches menu-item behavior. No new guard.
- **Hotkey pressed while the YouTube panel is open**: `YouTubeInputPanelController.show()` early-returns when `panel != nil` (line 26). Safe.
- **Hotkey pressed during NSOpenPanel modal**: modal blocks main thread; the event tap queues; the next action fires after dismissal. Same as double-clicking the menu item. Acceptable.
- **User swaps dictation hotkey to match one of the new ones**: dictation's existing notification fires, which triggers `refreshAllHotkeys()`. The expanded conflict check disables the colliding transcription hotkey. Settings UI warns inline via existing pattern.
- **Accessibility missing**: `GlobalShortcutManager.start()` returns `false`; existing `callbacks.onHotkeyUnavailable` path shows the existing alert.

## Testing

- `swift test` baseline before and after.
- **Unit**: SettingsViewModel persistence round-trip for both triggers. Conflict validator combinations (file↔dictation, file↔meeting, file↔youtube, youtube↔dictation, youtube↔meeting).
- **Manual**:
  1. Enable file hotkey (e.g. ⌃⇧F). Press anywhere on macOS — file picker opens.
  2. Enable YouTube hotkey (e.g. ⌃⇧Y). Press — YouTube panel opens. Press again while visible — no duplicate panel.
  3. Try to record a colliding hotkey — UI rejects with the right message.
  4. Disable dictation while file hotkey is set to the same chord — file hotkey starts working again.
  5. Verify the menu-bar "Transcribe File…" and "Transcribe from YouTube…" items show the chord hint when a chord is configured.

## Rollout

- Bump to 0.6.x patch.
- Changelog: "New: optional global hotkeys for file and YouTube transcription, configurable in Settings → Transcription."
- Reply on #108 explaining the auto-copy half is skipped (overlaps with Copy button + Auto-save to disk; unwanted clipboard clobber).
- No website/worker change (telemetry uses existing `settingChanged` event name).
