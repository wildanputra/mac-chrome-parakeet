# Onboarding use-case selection

> Status: **ACTIVE** (plan) · Created 2026-05-28 · ADR-005 amendment

## Problem

First-run onboarding is one linear path for everyone: `Welcome → Microphone →
Accessibility → Meeting Recording → Calendar → Hotkey → Speech Model → Ready`
(`OnboardingViewModel.Step`, `OnboardingViewModel.swift:22`). Meeting Recording
and Calendar are shown to *every* new user with a "Skip — I'll set this up
later" button (`OnboardingFlowView.swift:367`, `:502`).

That means a user who only wants WisprFlow-style dictation still has to actively
dismiss two of macOS's heaviest, scariest permission prompts (Screen & System
Audio Recording, Calendar) that they will never use. And a user who only wants
Granola-style meeting capture sits through the Accessibility prompt and a
two-card push-to-talk hotkey tutorial that are irrelevant to them.

The flow is *opt-out per step*. It should be *opt-in once*: ask what the user is
here for, then show only the steps and request only the permissions that intent
needs.

## Goal

Add a single **use-case selection** step right after Welcome. The choice prunes
the remaining steps and permission prompts so each user gets the shortest honest
path to their first success, with no surprise prompts for features they didn't ask for.

This is a **UI/UX change, not a download change.** Model-download behavior is
deliberately left identical in Phase 1 (see Non-goals + Phase 2).

### The three use cases

| Use case | Value prop | Steps it unlocks | Permissions it requests |
|---|---|---|---|
| **Dictation** | "Type with your voice, anywhere." | Microphone, Accessibility, Hotkey, Speech Model | Microphone, Accessibility |
| **Meetings** | "Record and transcribe meetings." | Microphone, Meeting Recording, Calendar*, Speech Model | Microphone, Screen & System Audio, Calendar* |
| **Everything** | "Dictation + meetings." | all of the above | all of the above |

\* Calendar step only when `AppFeatures.calendarEnabled` is also true (unchanged gate).

**File / YouTube transcription is available in every mode** — it needs no
permissions and rides on the speech model every path downloads. It is *not* a
use case; it is a free rider, and the picker copy says so explicitly.

### Resulting step counts (all `AppFeatures` flags true today)

| Path | Steps | Permission prompts |
|---|---|---|
| Today (everyone) | 8 | up to 4 (mic, ax, screen, calendar) |
| **Dictation** | 7 | **2** (mic, ax) |
| **Meetings** | 7 | up to 3 (mic, screen, calendar) — **no accessibility, no hotkey tutorial** |
| **Everything** | 9 | up to 4 |

The single-intent paths are shorter *and* drop the irrelevant scary prompts.
"Everything" is one step longer than today (the picker), which is the correct
cost for a user who genuinely wants all of it.

## Non-goals (explicitly, to avoid overengineering)

- **No change to what gets downloaded in Phase 1.** Parakeet (~6 GB) / Whisper
  (CJK) and the diarization speaker models still download exactly as they do
  today, on the same critical path, for all three use cases. Diarization also
  powers file-transcription speaker labels, so a dictation user benefits from it
  too; shaving ~130 MB is not worth coupling this UX change to the STT runtime.
  Download optimization is Phase 2 and is independently shippable / skippable.
- **No new "voice notes" / record-into-app mode.** MacParakeet dictation always
  pastes; there is no no-paste capture mode and we are not building one here.
- **No VAD onboarding work.** VAD live chunking is flag-off
  (`meetingVadLiveChunkingEnabled = false`) and cached-only; it has its own plan
  (`2026-05-meeting-vad-guided-live-chunking.md`). Forward hook only (see below).
- **No persisted mid-flow resume.** Onboarding still restarts at Welcome if quit
  before completion (current behavior); we don't add step-resume.
- **Existing users are untouched.** The coordinator only shows onboarding when
  `onboarding.completedAtISO` is absent (`OnboardingCoordinator.swift:41`).

## Design

### 1. `OnboardingViewModel.UseCase`

New nested enum in `OnboardingViewModel`, mirroring the existing `Step` enum:

```swift
public enum UseCase: String, CaseIterable, Sendable {
    case dictation
    case meetings
    case everything

    public var includesDictation: Bool { self == .dictation || self == .everything }
    public var includesMeetings: Bool  { self == .meetings  || self == .everything }
}
```

VM gains an observable property `public private(set) var useCase: UseCase` plus a
setter `selectUseCase(_:)` that (a) updates the property, (b) persists it, and
(c) emits the telemetry event (below). Default = `.dictation` (the modal,
lowest-friction intent; revisit from telemetry). Persisted under a new key
`onboarding.useCase`; read in `init`.

### 2. Add `Step.useCase` between `.welcome` and `.microphone`

`Step` raw values are ephemeral (never persisted — verified: only
`completedAtISO` + the two skip booleans are stored, `OnboardingViewModel.swift:107`).
Navigation walks `visibleSteps` by `rawValue` ordering, so inserting a case in
declaration order is safe. Telemetry `.onboardingStep` keys off the title string,
not the raw value.

Exhaustive `switch`es that must gain a `.useCase` arm:
- `Step.title` (`OnboardingViewModel.swift:34`)
- `canContinueFromCurrentStep()` → `.useCase` returns `true` (`:256`)
- View: `stepBody` (`OnboardingFlowView.swift:325`), `stepIcon` (`:189`),
  `stepIsCompleted` (`:202`, completed when `step.rawValue > useCase.rawValue`),
  `titleForStep` (`:1051`), `subtitleForStep` (`:1064`),
  `primaryButtonTitle` (`:1088`), `continueHint` (`:1217`).

### 3. `visibleSteps` becomes use-case aware (the core change)

Today `visibleSteps` is a **static** computed property gated only by
`AppFeatures` (`OnboardingViewModel.swift:212`). Convert it to an **instance**
property that also consults `useCase`:

```swift
public var visibleSteps: [Step] {
    Step.allCases.filter { step in
        switch step {
        case .welcome, .useCase, .microphone, .engine, .done:
            return true
        case .accessibility:
            return useCase.includesDictation          // paste needs AX
        case .hotkey:
            return useCase.includesDictation          // dictation gesture tutorial
        case .meetingRecording:
            return AppFeatures.meetingRecordingEnabled && useCase.includesMeetings
        case .calendar:
            return AppFeatures.meetingRecordingEnabled
                && AppFeatures.calendarEnabled
                && useCase.includesMeetings
        }
    }
}
```

Call-site updates (static → instance):
- `goNext()` / `goBack()` / use `self.visibleSteps` (`:226`, `:240`).
- View: `private var visibleSteps` → `viewModel.visibleSteps` (`OnboardingFlowView.swift:55`).

Because `visibleSteps` now derives from the observable `useCase`, the sidebar
step list (`ForEach(visibleSteps)`, `:115`) and the "Step X of N" / progress
strip recompute automatically when the user picks. Wrap the sidebar list +
progress in `withAnimation` so rows slide in/out smoothly rather than popping.

**Step normalization guard.** If the user advances, comes back to `.useCase`, and
switches to a path that excludes their previous step, `step` could point at a
now-hidden step. Add a small helper invoked from `selectUseCase` and `goBack`:
if `step` is not in the new `visibleSteps`, clamp to the nearest visible step
≥ current (else the last visible). In practice the user is *on* `.useCase` when
they switch, so `step` is always still visible — but the guard makes the VM
correct under jump()/back() and is cheap to unit-test.

### 4. The use-case step UI (`useCaseStep` in `OnboardingFlowView`)

- Title: **"What do you want to do?"** Subtitle: **"Pick one — you can turn on
  the rest anytime in Settings."**
- Three **selectable rows** (radio semantics), stacked vertically (reads better
  than a grid in the 480pt content column, and lets each row show its
  consequence). Each row: SF Symbol + bold title + one-line value prop + a muted
  footnote naming the permissions it will set up — so the user sees the cost
  before any system prompt. Selected = accent border + filled check; reuse
  `onboardingCard` styling and `DesignSystem` tokens.

  ```
  ⌨  Dictation        Type with your voice, anywhere.
                      Sets up: Microphone, Accessibility            ✓
  ────────────────────────────────────────────────────────────────
  👥  Meetings         Record and transcribe meetings.
                      Sets up: Microphone, Screen & System Audio
  ────────────────────────────────────────────────────────────────
  ▦  Everything       Dictation + meetings.
                      Sets up everything above
  ```

- Reassurance line below the cards: **"Transcribing files & YouTube links works
  in every mode."**
- Pre-select **Dictation** so the default-action **Continue** works immediately.
  Tap selects; Continue advances. (No auto-advance-on-tap — the choice is
  consequential enough to confirm.)
- A11y: each row is a `Button` with an accessibility label + `.isSelected`
  trait; full keyboard navigation; honors `accessibilityReduceMotion` (no
  required motion).

### 5. Tailored "Ready" step

`doneStep` quick tips become use-case aware (`OnboardingFlowView.swift:903`):
- Dictation: hotkey tip + "Drop a file to transcribe" + Settings.
- Meetings: "Click **Record Meeting** in the Transcribe tab" + file tip + Settings.
- Everything: hotkey + meeting + file tips.

Post-onboarding routing (`onOpenMainApp`) stays on the Transcribe tab — already
the shared hub for all three modes — so no routing change is required.

### 6. Telemetry

New event `onboarding_use_case_selected` with one property `use_case`
(`dictation` | `meetings` | `everything`), emitted from `selectUseCase`. This
captures intent even for users who don't finish. Honors the global opt-out;
carries no content.

**Two-repo change (known footgun):** add the case to `TelemetryEventName`
(`TelemetryEvent.swift:78`) *and* to `ALLOWED_EVENTS` in
`macparakeet-website/functions/api/telemetry.ts`. The Worker rejects the entire
batch if any event name is unknown, silently dropping co-batched valid events.
Deploy the website allowlist **before** shipping the build.

### 7. Re-enabling a skipped feature later (verify, don't build)

The choice never hard-locks anything. Confirm these "enable later" paths exist so
a single-intent user can grow into the others without re-onboarding:
- **Meetings later:** the Transcribe Meeting Recording tile starts a meeting and
  triggers the Screen & System Audio prompt on first use (post-IA-overhaul tile).
- **Accessibility later:** Settings → Dictation hotkey config / first dictation
  prompts for Accessibility.
- **Calendar later:** Settings calendar subsection (REQ-CAL-002).

If any path does *not* self-prompt for its permission, that gap is in scope for
Phase 1 (it's the contract that makes pruning safe).

## Phase 2 (separable, optional) — lazy diarization

Independent follow-up, only if we decide the download trim is worth it:
- Skip `prepareDiarizationModelsIfNeeded` during onboarding for **dictation-only**
  (`OnboardingViewModel.swift:704`, called from both Parakeet warm-up `:479` and
  Whisper `:544`); keep it for meetings/everything.
- Make the file-transcription and meeting-start paths lazily prepare diarization
  on first use when not ready (with clear "Preparing speaker detection… one-time
  ~130 MB" progress), since diarization also serves file speaker labels.
- Revisit the 7 GB preflight disk message (`:103`, `:834`).

This touches the STT runtime / transcription flows and carries real regression
risk, so it is **deliberately decoupled** from the Phase 1 UX win and can ship
later or never.

## Forward hook — VAD (not this plan)

When `meetingVadLiveChunkingEnabled` eventually ships, the meetings/everything
onboarding path is the natural place to pre-fetch the Silero VAD model. Tracked
in `2026-05-meeting-vad-guided-live-chunking.md` (Phase 0 pending). No code here.

## Files touched (Phase 1)

| File | Change |
|---|---|
| `Sources/MacParakeetViewModels/OnboardingViewModel.swift` | `UseCase` enum, `useCase` property + `selectUseCase`, `onboarding.useCase` key, `Step.useCase`, instance `visibleSteps`, normalization guard, `.useCase` arms |
| `Sources/MacParakeet/Views/Onboarding/OnboardingFlowView.swift` | `useCaseStep` UI, `viewModel.visibleSteps`, animated sidebar, tailored `doneStep`, `.useCase` arms in all step switches |
| `Sources/MacParakeetCore/Services/Telemetry/TelemetryEvent.swift` | `onboardingUseCaseSelected` event + name |
| `macparakeet-website/functions/api/telemetry.ts` | add `onboarding_use_case_selected` to `ALLOWED_EVENTS` (deploy first) |
| `spec/adr/005-onboarding-first-run.md` | amendment: use-case step + per-intent gating |
| `spec/02-features.md`, `spec/README.md` | onboarding progress note |
| `spec/kernel/requirements.yaml` | new `REQ-ONB-001` (use-case-aware onboarding) |
| `spec/kernel/traceability.md` | map REQ-ONB-001 → VM/Flow + tests |

## Testing (ViewModel/logic only — no SwiftUI view tests)

Extend `Tests/MacParakeetTests/ViewModels/OnboardingViewModelTests.swift`:
- `UseCase.includesDictation/includesMeetings` truth table.
- `visibleSteps` for each use-case × `AppFeatures` combination: dictation hides
  meetingRecording/calendar; meetings hides accessibility/hotkey; everything
  shows all enabled steps; calendar still requires both flags.
- `goNext`/`goBack` walk the gated list with no no-ops or skips.
- `selectUseCase` + normalization clamps a now-hidden `step`.
- `canContinueFromCurrentStep()` is `true` on `.useCase`.
- `onboarding.useCase` persists and is re-read on init.
- Telemetry: `selectUseCase` emits `onboardingUseCaseSelected` (via existing
  telemetry spy pattern).
- Regression: diarization is still prepared in Phase 1 (existing warm-up tests
  unchanged) — guards against accidentally pulling Phase 2 forward.

Run focused VM tests, then full `swift test`.

## Invariants

- Existing users never re-onboard.
- Speech-model download stays mandatory on every path (engine step never gated).
- No feature is hard-locked; every un-chosen feature stays enableable later.
- Local-first / no-content-telemetry unchanged.

## Open question

- Default selection: **Dictation** (assumed modal intent). Revisit once
  `onboarding_use_case_selected` data lands.
