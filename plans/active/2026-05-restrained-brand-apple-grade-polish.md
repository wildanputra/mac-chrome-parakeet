# Restrained Brand + Apple-Grade Polish

> Status: **ACTIVE** - 2026-05-03
> Ship target: **post-v0.7.0**
> Branch: `refactor/restrained-tint-and-button-roles` (off `main` post-#205 merge)
> Shape: **single PR**, commits split per phase for bisect/readability
> Related: docs/design-overhaul.md, docs/brand-identity.md
> Focus rings: follow system accent (Apple-correct, makes coral CTAs read louder)

## Context

PR #205 merged the unified Ask quick prompts (`af23a55d`). During review the user flagged two visual smells, both rooted in the same gap:

1. Action bars on the transcript page and prompt-result page all read coral — no visual hierarchy between primary and secondary actions ("everything is orange, so nothing is").
2. Destructive buttons (Delete) render coral instead of red, because the cascading `.tint(coral)` set in `AppWindowCoordinator.swift:197` overrides destructive role styling.

Root cause: there's no semantic button-role abstraction. Every callsite reaches for `.buttonStyle(.bordered) + .tint(...)` directly. The "App-wide brand-accent sweep" (commit `044f6a74`) was a band-aid for this missing layer.

This plan introduces button roles, pulls the cascading tint, and uses that cleanliness as the foundation for an Apple-grade polish pass *calibrated to MacParakeet*. Not a theming system. Not customizable accent. Discipline at the chrome layer.

## Calibrated principles ("Apple-grade for MacParakeet")

Reference points: macOS Voice Memos, Reminders, Stocks. We are a menu-bar utility — restraint over expression.

1. **Coral is brand, not chrome.** Coral on: CTAs (one per surface max), recording state, AssistantHead, idle/recording pills, BreathingSeedOfLife, brand mark, sacred geometry. Coral OFF: secondary buttons, mode pickers, focus rings, selection, hover.
2. **Hierarchy via type weight + size + spacing, not color.** Color is the third tool, not the first.
3. **Material adoption.** Floating chrome (sheets, popovers, sidebars) gets `.regularMaterial` / `.thickMaterial` / `NSVisualEffectView`. Solid opacity-fills are for in-content surfaces.
4. **System accent for selection/focus.** Respect `NSColor.controlAccentColor`. Don't repaint focus rings coral.
5. **Apple HIG type semantics.** Align our scale to system text style names.
6. **Motion uses Apple's named curves** (`.snappy`, `.smooth`, `.bouncy`) unless a hand-tuned curve is genuinely better. Honor `accessibilityReduceMotion` everywhere.
7. **Light mode is equal.** Visual audit pass.
8. **One Gallery preview.** Single SwiftUI Preview rendering every token side-by-side — drift catcher.

## Anti-goals

- No user-customizable theme. Coral is the parakeet.
- No density toggle.
- No build pipeline (Style Dictionary etc.). Swift static enums stay.
- No new animation framework.
- No backwards-compat shims. Single owner; delete cleanly.

## Phase 1 — Button roles + tint pull

### New API

```swift
// Sources/MacParakeet/Views/Components/DesignSystem.swift
extension DesignSystem.Colors {
    /// Neutral label tint — for `.bordered` buttons that should NOT carry brand.
    /// Resolves to system label color (white in dark, near-black in light).
    static let tintNeutral = Color.primary
}

// Sources/MacParakeet/Views/Components/ParakeetActionStyle.swift (new)
enum ParakeetActionRole {
    case primary               // brand coral, .bordered
    case primaryProminent      // brand coral, .borderedProminent
    case secondary             // neutral — system label color, .bordered
    case destructive           // red — system destructive role
    case destructiveProminent  // red, .borderedProminent
    case subtle                // lower-weight neutral; .borderless or .plain
}

extension View {
    /// Apply a semantic action role. Replaces ad-hoc `.buttonStyle + .tint`.
    func parakeetAction(_ role: ParakeetActionRole) -> some View
}
```

Prominence is encoded in the role so secondary/subtle controls cannot receive
an ignored prominence flag.

### Tint cascade removed from

- `Sources/MacParakeet/App/AppWindowCoordinator.swift:197`
- `Sources/MacParakeet/Onboarding/OnboardingWindowController.swift`
- `Sources/MacParakeet/Views/MeetingRecording/MeetingCountdownToastController.swift`
- `Sources/MacParakeet/Views/MeetingRecording/MeetingRecordingPanelController.swift`
- `Sources/MacParakeet/Views/MeetingRecording/MeetingRecordingPillController.swift`
- `Sources/MacParakeet/Views/Transcription/YouTubeInputPanelController.swift`
- `Sources/MacParakeet/Views/MainWindowView.swift` sidebar list selection tint
- Cross-window sheet patches: `TranscriptResultView` L219, `PromptLibraryView` L146/L238, `VocabularyView`, `VocabularyBackupSection`, `AskPromptsSheet` L138/L282/L533/L706

### Role mapping (representative; full sweep in PR)

**TranscriptResultView action bar:**

| Button | Role |
|--------|------|
| Copy | `.secondary` |
| Export | `.secondary` |
| Retranscribe | `.secondary` |
| New Transcription | `.primary` |

**TranscriptResultView transcript-pane header:**

| Button | Role |
|--------|------|
| Edit | `.secondary` |
| Save (commit edit) | `.primaryProminent` |
| Cancel | `.secondary` |
| Revert | `.secondary` |

**TranscriptResultView prompt-result actions:**

| Button | Role |
|--------|------|
| Regenerate | `.secondary` |
| Copy | `.secondary` |
| Export menu | `.secondary` |
| Delete | `.destructive` |

**Settings, Onboarding, AskPromptsSheet, PromptLibraryView, Vocabulary sheets:** mapped during sweep — most fall into `.primary` (one per sheet) or `.secondary` (everything else).

### Validation

- Manual smoke: every screen, dark mode + light mode
- `swift test` clean (no test changes expected)
- Visual: only Save / New Transcription / "Add Word" / Done style buttons render coral; everything else neutral; Delete red

## Phase 2 — Material adoption

| Surface | Today | Target |
|---------|-------|--------|
| Sheets (export, vocab, prompt library, ask prompts edit) | `.surface` solid | `.thickMaterial` |
| Popovers (export options, retranscribe options, slash menu) | rounded rect solid fill | `.regularMaterial` |
| Sidebars (main window) | likely already NSVisualEffectView via SwiftUI sidebar style | audit, confirm |
| Floating dropdowns (Picker, Menu) | system default | leave |
| In-content cards (transcription thumbnails) | solid surface | leave (in-content, not floating) |

Single biggest "looks Apple-grade" lift. Each callsite is small.

Risk: material can render badly when stacked over `BreathingSeedOfLife` behind the meeting panel. Test each surface; fall back to solid where material muddies the imagery.

## Phase 3 — Markdown color fold

`MarkdownContentView.swift` lines 86-101 use raw `NSColor(red:green:blue:)` literals duplicating `Colors.textPrimary`, `Colors.textSecondary`, `Colors.textTertiary`, `Colors.accent`, `Colors.surfaceElevated`. Fold into `DesignSystem.Colors` tokens via an `NSColor(_ swiftuiColor:)` bridge. Removes a drift target.

## Phase 4 — Light mode visual audit

Screenshot every screen in light mode; fix anything that screams "tested in dark only." Common culprits: borders too subtle in light, opacity values tuned for dark backgrounds, custom-drawn glows that look milky over white.

## Phase 5 — Focus + Tab pass

- Every focusable control has a visible focus ring
- Tab traverses logically across each screen
- Tooltips include keyboard shortcut hints with ⌘ ⌥ ⇧ glyphs where applicable
- Default-button keyboard semantics (`Return` triggers primary CTA on sheets)

## Phase 6 — Motion calibration

- Replace `Animation.selectionChange` / `.hoverTransition` / `.contentSwap` etc. with Apple's named curves (`.snappy`, `.smooth`, `.bouncy`) where appropriate. Keep custom springs only when genuinely better.
- Honor `@Environment(\.accessibilityReduceMotion)` on every animated state change. Today only `BreathingSeedOfLifeView` honors it.

## Phase 7 — Hygiene

- Delete dead Typography aliases (`headline`, `title`, `largeTitle`, `sectionHeader`) — 4 lines.
- Do **not** rename the rest of the Typography scale. ~60 callsites of internal renaming for zero user-visible benefit fails the cost/benefit test.

## Phase 8 — DesignSystemGalleryView

Single SwiftUI Preview rendering:
- Every button role × prominent (`primary`, `secondary`, `destructive`, `subtle`)
- Every typography token (live text samples)
- Every color (with name labels, light/dark side-by-side)
- Every shadow style (on cards)
- Every spacing scale (rulers)

Debug-only, gated behind `#if DEBUG`. Single screen catches drift in 30 seconds.

## Deferred (not in this PR)

- Typography scale rename (cost/benefit fails today)
- Custom shortcut-glyph rendering beyond tooltips
- Spring-curve consistency audit
- `AppTheme` extraction (only if user theming becomes a real feature ask)

## Risk register

- **Phase 1 partial state.** If we merge mid-sweep, some buttons read coral and others neutral. Mitigation: every callsite migrated in one PR; atomic merge.
- **Phase 2 material over BreathingSeedOfLife.** Custom imagery behind meeting panel could fight `.regularMaterial`. Per-surface test.
- **System accent vs coral for focus rings.** Today the cascade paints rings coral. Pulling the cascade reverts rings to user's system accent (red, purple, blue, etc.). This is the *correct* macOS behavior, but it's a visible change — flag for owner approval before Phase 1 lands.

## Tests

No test changes anticipated across all three PRs (purely visual). Existing 2200+ XCTest suite is the safety net. Each PR runs `swift test` to verify no regressions.

## Resolved decisions

1. **Selection/focus ring color** → follow system accent (Apple-correct; makes coral CTAs read louder against neutral focus chrome). Easy to reverse if it looks wrong post-Phase-1.
2. **Sheet material** → `.thickMaterial`. Sheets are primary floating surfaces.
3. **Popover material** → `.regularMaterial`.
4. **Typography rename** → deferred. Cost/benefit fails for 60-callsite churn at zero user-visible benefit.
5. **PR shape** → single PR, commits split per phase.
