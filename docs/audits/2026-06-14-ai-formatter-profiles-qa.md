# AI Formatter Profiles — QA Review — 2026-06-14

> **Status:** ACTIVE. Focused QA pass on the **app-aware AI Formatter
> profiles** feature (REQ-LLM-004), gated by
> `AppFeatures.aiFormatterProfilesEnabled` (enabled 2026-06-10, `main`-only —
> not yet in a tagged release). Covers the data model, persistence, dictation
> routing, History provenance, Settings UI, feature flag, and settings search.
> Combines automated tests, a live database-migration check, real-data
> inspection, a driven-GUI screenshot walkthrough, and a manual code review.
> One real (low-severity) bug was found and fixed in this same change; one
> harmless pre-release dev artifact was identified and explained.

| | Result |
|---|---|
| Feature flag | `AppFeatures.aiFormatterProfilesEnabled = true` |
| Requirement | REQ-LLM-004 (`spec/kernel/requirements.yaml`) |
| QA base commit | `origin/main` `98b4aeef1` |
| Focused formatter test suites | **212 tests, 0 failures** |
| Full `swift test` (with the fix in this change) | **green (exit 0)** |
| Bugs found | 1 (CONFIRMED) |
| Bugs fixed in this change | 1 (+ regression test) |
| Live DB migration `v0.21-ai-formatter-profiles` | applied & schema-verified |
| Driven-GUI screenshots | 5 (Settings → AI Formatter) |

---

## 1. What the feature is

When a dictation finishes, the AI Formatter prompt is no longer a single global
string. It is resolved against the **frontmost app at stop time** through a
four-tier chain (first match wins):

1. **Exact-app profile** — a user prompt bound to a specific bundle id (e.g.
   `com.tinyspeck.slackmacgap`).
2. **Category profile** — a user prompt bound to an app *category* (Messaging,
   Email, Browser, Notes, Documents, Code, Terminal).
3. **Built-in category smart default** — a shipped, readable, per-category
   prompt, gated by a master switch + per-category switches.
4. **Global fallback prompt** — the legacy behavior.

The matched tier is recorded **locally** on the dictation row and surfaced as a
provenance chip in Dictation History. Telemetry only ever transmits the coarse
category bucket — never the bundle id, display name, profile name, profile id,
or prompt text.

Authoritative behavior: `spec/11-llm-integration.md` (Dictation AI Formatter
Profiles) and `spec/02-features.md` (F8). Routing is per-surface (REQ-LLM-005):
independent **Use for transcripts** (default on) and **Use for dictation**
(default off) toggles, ANDed with provider availability.

## 2. Test environment

- Base: `origin/main` at `98b4aeef1` (the QA branch is cut from here).
- Toolchain: `swift test` (XCTest) on Apple Silicon, macOS 14.2+ target.
- Live app: dev bundle `com.macparakeet.dev` built via `scripts/dev/run_app.sh`,
  reading the developer's real `macparakeet.db`.
- LLM provider configured in the dev app: **Local CLI → Codex** (relevant only
  to the live UI; the automated routing/provenance tests mock the LLM).

## 3. Methodology

1. **Mapped the feature surface** end-to-end (model, matcher, repository,
   migration, resolver, dictation wiring, History view, Settings view/VM,
   feature flag, settings search, CLI).
2. **Ran the focused test suites** that cover this feature, then the full suite.
3. **Verified the live migration** against the real dev DB (table, CHECK
   constraints, indices, and the three `dictations` provenance columns).
4. **Inspected real rows** (existing profile + dictation provenance
   distribution) to catch drift between intent and stored data.
5. **Drove the live GUI** (Settings → AI Formatter) via the accessibility API
   and captured screenshots of each surface.
6. **Read the routing + provenance code** for correctness on the failure path.

## 4. What was verified (by layer)

| Layer | How | Result |
|---|---|---|
| Data model & matcher precedence (exact-app > category > smart default > global; sort order; disabled profiles excluded) | `AIFormatterProfileMatcherTests` (22) | ✅ pass |
| Persistence (bundle-id normalization, category-field clearing, dup rejection at repo *and* DB-unique-index level, empty-name guard, ordering) | `AIFormatterProfileRepositoryTests` (11) | ✅ pass |
| Smart-defaults policy (master switch, per-category disable, persistence) | `AppRuntimePreferencesTests` (15) | ✅ pass |
| Provenance columns round-trip on the dictation row | `DictationRepositoryTests` (25) | ✅ pass |
| Settings VM (draft lifecycle, app/category/manual-bundle entry, auto-name, auto-prompt, custom-prompt preservation, smart-default toggles) | `LLMSettingsViewModelTests` (118) | ✅ pass |
| Settings search keywords gate on the flag | `SettingsSearchIndexTests` (21) | ✅ pass |
| Dictation routing + provenance stamping (incl. finish-context preference, telemetry redaction) | `DictationServiceTests` (73) | ✅ pass |
| Live DB migration `v0.21-ai-formatter-profiles` | `sqlite3` on real DB | ✅ table + 2 CHECKs + 4 indices + 3 `dictations` columns present |
| Settings → AI Formatter UI (smart-defaults grid, readable prompts, custom profiles, editor) | driven GUI + screenshots | ✅ renders & behaves as specified |
| Feature-flag gating (Settings sections + History chip + search keywords) | code review | ✅ all four sites gated on `aiFormatterProfilesEnabled` |

The smart-default prompt rendered in the live UI matches the shipped source
(`AIFormatterSmartDefaults.swift`) **verbatim**, including the `{{TRANSCRIPT}}`
placeholder — see the Email screenshot in §6.

### Live database evidence

```
$ sqlite3 macparakeet.db ".schema ai_formatter_profiles"
CREATE TABLE ai_formatter_profiles ( id TEXT PRIMARY KEY, name TEXT NOT NULL,
  isEnabled BOOLEAN NOT NULL DEFAULT 1, targetKind TEXT NOT NULL,
  bundleIdentifier TEXT, appDisplayName TEXT, appCategory TEXT,
  promptTemplate TEXT NOT NULL, origin TEXT NOT NULL DEFAULT 'custom',
  sortOrder INTEGER NOT NULL DEFAULT 0, createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL,
  CHECK (targetKind IN ('bundle','category')), CHECK (origin IN ('custom','template')),
  CHECK ( (targetKind='bundle' AND bundleIdentifier IS NOT NULL AND ... AND appCategory IS NULL)
       OR (targetKind='category' AND appCategory IN (...) AND bundleIdentifier IS NULL AND appDisplayName IS NULL) ));
-- + idx_..._enabled_sort, idx_..._target_kind, UNIQUE idx_..._bundle_unique, UNIQUE idx_..._category_unique
-- dictations gained: aiFormatterProfileID, aiFormatterProfileName, aiFormatterProfileMatchKind
```

## 5. Findings

### QA-AIF-001 — History overclaims provenance when AI formatting fails (CONFIRMED · fixed in this change)

**Severity:** low (no data loss; the *pasted/saved text* is always correct).
**Surface:** Dictation History provenance chip.

When the AI Formatter is enabled for dictation and a profile/category/smart
default routes the dictation, but the LLM call then **throws** (provider error,
timeout, truncation), `DictationService` falls back to standard cleanup — the
pasted text is the *un-formatted* text, which is correct. However, the resolved
routing was still stamped onto the saved dictation row:

```swift
// formatTranscriptIfNeeded(...) catch path — before
return FormatterOutcome(text: nil, run: run, resolution: resolution)
//                                              ^^^^^^^^^^^^^^^^^^^^
// stopRecording() then writes resolution.profileName/matchKind onto the row,
// so History shows: “Formatted with the ‘Slack’ app profile” — for text the
// profile never produced.
```

`formatterOutcome.resolution` is consumed in exactly one place (the provenance
write in `stopRecording`); failure telemetry is carried separately by the failed
`run`. The History surface’s own copy is past-tense (“**Formatted** with …”), so
stamping a profile on a fall-back dictation is an honesty bug, not a routing bug.

**Fix:** drop the resolution on the failure path so the row reads as an
un-routed, standard-cleanup dictation (no chip — same as the global case).

```swift
// after
return FormatterOutcome(text: nil, run: run, resolution: nil)
```

**Regression test:** `DictationServiceTests.testStopRecordingDropsProfileProvenanceWhenAIFormatterFails`
— routes via an exact-app resolution, forces the LLM to throw, and asserts the
saved row carries no `aiFormatterProfileID/Name/MatchKind`.

Why automated coverage missed it: the existing failure test
(`testStopRecordingFallsBackWhenAIFormatterFailsAndPostsWarning`) uses the
*global* resolver, whose `matchKind` is `.global` — which renders no chip — so
it never exercised the profile-match-then-fail combination.

### Observation (not a bug) — “New category profile” row in the dev DB

The real dev DB carries one profile literally named **“New category profile”**
(`targetKind=category`, `appCategory=notes`). That string does **not** exist in
the current code — `git log -S` shows it was the pre-polish default draft name,
removed in the ship-polish commit `37437184d`, which switched new category
drafts to be named after their category (e.g. “Notes”). So the row is a **stale
artifact created by an earlier development build**, not a current-code defect.
Current behavior was confirmed live: opening *Add Category* produces a draft
pre-named “Messaging” (the default category) — see §6.

### Provenance distribution (real data, informational)

Of the developer’s dictations, 8 carry `aiFormatterProfileMatchKind = global`
and the rest predate the columns (`NULL`). None carry a profile/category match
yet (expected — *Use for dictation* defaults off), so a live History chip for a
profile-routed dictation could not be captured without performing a real
dictation; that path is covered by `DictationServiceTests` instead.

## 6. Live GUI walkthrough

All shots are the dev app (`com.macparakeet.dev`), Settings → **AI** tab.

**Settings shell & tab bar** (Capture / Engine / AI / System):

![Settings — Capture tab](assets/2026-06-14-ai-formatter-profiles/00-main-window.png)

**AI tab — top.** “AI Formatter (Final step)” with the per-surface
**Use for transcripts** (on) / **Use for dictation** (off) toggles, matching the
REQ-LLM-005 defaults (verified via the accessibility values, not just visually):

![AI tab top](assets/2026-06-14-ai-formatter-profiles/01-ai-tab.png)

**Smart defaults grid + Custom profiles.** The master switch, the seven category
cards (Messaging, Email, Browser, Notes, Documents, Code, Terminal) each with its
own enable toggle, “Customize fallback prompt”, and the Custom-profiles list with
**Add App** / **Add Category**:

![Smart defaults grid and custom profiles](assets/2026-06-14-ai-formatter-profiles/02-smart-defaults.png)

**Readable smart-default prompt.** Clicking a category card reveals its full
prompt (here Email) — verbatim from `AIFormatterSmartDefaults.swift`, with the
“custom profiles always win” hint:

![Email smart-default prompt preview](assets/2026-06-14-ai-formatter-profiles/03-email-prompt-preview.png)

**Profile editor.** *Add Category* opens an editor with App/Category type,
Name, Category picker, and the auto-filled smart-default prompt (note
`{{TRANSCRIPT}}`). This draft was cancelled after capture — no row was written
(DB profile count stayed at 1):

![Profile editor](assets/2026-06-14-ai-formatter-profiles/04-profile-editor.png)

## 7. Coverage gaps / not exercised live

- **End-to-end dictation routing → History chip** was not exercised in the live
  app: it needs *Use for dictation* turned on, a configured provider call, and a
  real spoken dictation into a target app. The routing, finish-context
  preference, provenance write, and telemetry redaction are covered by
  `DictationServiceTests`; the chip rendering is covered by code review of
  `DictationHistoryView.formatterProvenanceText`.
- **CLI:** there is intentionally **no** CLI surface for managing or exercising
  formatter profiles — app-aware routing is GUI-dictation-only by design
  (`spec/11-llm-integration.md`). CLI `transcribe`/`llm` formatting continues to
  use the global prompt. No CLI contract change here.

## 8. Conclusion

The feature is **well-built and matches the spec** across every layer that can
be tested deterministically: matcher precedence, persistence + DB invariants,
smart-defaults policy, provenance round-trip, settings VM, search gating, and
the live Settings UI all behave as REQ-LLM-004 / REQ-LLM-005 describe. The live
migration is applied and correct on a real database, and the Settings surfaces
render and behave as designed.

One real low-severity bug (QA-AIF-001) — a History provenance overclaim on the
formatter-failure path — was found by code review, **fixed**, and **pinned with
a regression test** in this same change. The full suite is green with the fix.
No other defects were found; the one suspicious DB row was traced to a harmless
pre-release dev artifact.
