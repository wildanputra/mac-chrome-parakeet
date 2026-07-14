# MacParakeet: Architecture

> Status: **ACTIVE** - Authoritative, current
> The definitive technical stack and system design for MacParakeet.

---

## System Overview

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                              MACPARAKEET                                          │
│                          macOS Native App                                         │
├──────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────────┐  │
│  │                             UI LAYER                                       │  │
│  │                           (SwiftUI)                                        │  │
│  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌───────────┐  │  │
│  │  │  Main Window  │  │   Menu Bar    │  │   Dictation   │  │ Settings  │  │  │
│  │  │  (Capture Hub │  │   (Status +   │  │   Overlay     │  │   View    │  │  │
│  │  │  + Library)   │  │    Quick      │  │  (Recording   │  │           │  │  │
│  │  │               │  │    Actions)   │  │   Indicator)  │  │           │  │  │
│  │  └───────┬───────┘  └───────┬───────┘  └───────┬───────┘  └─────┬─────┘  │  │
│  │          └──────────────────┴──────────────────┴─────────────────┘         │  │
│  └──────────────────────────────────────┬─────────────────────────────────────┘  │
│                                         │                                        │
│                                         ▼                                        │
│  ┌────────────────────────────────────────────────────────────────────────────┐  │
│  │                        MacParakeetCore                                     │  │
│  │                     (Library — No SwiftUI Views)                           │  │
│  │                                                                            │  │
│  │  ┌─────────────────┐  ┌────────────────────┐  ┌──────────────────┐      │  │
│  │  │ DictationService│  │TranscriptionService│  │MeetingRecording  │      │  │
│  │  └────────┬────────┘  └─────────┬──────────┘  │   Service        │      │  │
│  │           │                     │              └────────┬─────────┘      │  │
│  │           │                     │                       │                │  │
│  │  ┌────────▼─────────────────────▼──────┐  ┌────────────▼────────────┐   │  │
│  │  │         AudioProcessor              │  │  MeetingAudioCapture    │   │  │
│  │  │  (Format conversion, resampling)    │  │  (ScreenCaptureKit +   │   │  │
│  │  │                                     │  │   AVAudioEngine)       │   │  │
│  │  └──────────────────┬──────────────────┘  └────────────┬────────────┘   │  │
│  │                               │                                           │  │
│  │                     ┌─────────▼─────────┐  ┌────────────────────────────┐ │  │
│  │                     │   STT Scheduler   │  │  TextProcessingPipeline   │ │  │
│  │                     │   + Runtime       │  │  (Deterministic cleanup)  │ │  │
│  │                     └─────────┬─────────┘  └────────────────────────────┘ │  │
│  │                               │                                           │  │
│  │  ┌──────────────┐  ┌────────▼──────────────────────────────────────────┐ │  │
│  │  │ExportService │  │               Data Layer                          │ │  │
│  │  │(7 formats)   │  │  Models: Dictation, Transcription, Prompt,       │ │  │
│  │  └──────────────┘  │          PromptResult, ChatConversation,         │ │  │
│  │                     │          QuickPrompt, TransformHistory, LLMRun,  │ │  │
│  │                     │          CustomWord, TextSnippet                 │ │  │
│  │                     │  Repos:  DictationRepository,                    │ │  │
│  │                     │          TranscriptionRepository,                │ │  │
│  │                     │          PromptRepository, PromptResultRepository,│ │  │
│  │                     │          QuickPromptRepository,                  │ │  │
│  │                     │          ChatConversationRepository,             │ │  │
│  │                     │          TransformHistoryRepository,             │ │  │
│  │                     │          LLMRunRepository,                       │ │  │
│  │                     │          CustomWordRepository,                   │ │  │
│  │                     │          TextSnippetRepository                   │ │  │
│  │                     │  DB:     GRDB (SQLite, single file)             │ │  │
│  │                     └──────────────────────────────────────────────────┘ │  │
│  └────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                  │
├──────────────────────────────────────────────────────────────────────────────────┤
│                          LOCAL SPEECH ENGINES                                    │
│                                                                                  │
│  ┌──────────────────────────────┐                                                │
│  │   Parakeet STT (default)     │                                                │
│  │   FluidAudio CoreML on ANE   │                                                │
│  │   ~66 MB working RAM         │                                                │
│  │   ~2.5% WER, 155x realtime   │                                                │
│  └──────────────────────────────┘                                                │
│  ┌──────────────────────────────┐                                                │
│  │   Nemotron STT (optional)    │                                                │
│  │   FluidAudio CoreML, Beta    │                                                │
│  │   Multilingual + English     │                                                │
│  └──────────────────────────────┘                                                │
│  ┌──────────────────────────────┐                                                │
│  │   Cohere STT (optional)      │                                                │
│  │   FluidAudio CoreML batch    │                                                │
│  │   Accuracy-focused           │                                                │
│  └──────────────────────────────┘                                                │
│  ┌──────────────────────────────┐                                                │
│  │   WhisperKit STT (optional)  │                                                │
│  │   Local multilingual engine  │                                                │
│  │   Explicit model download    │                                                │
│  └──────────────────────────────┘                                                │
│                                                                                  │
├──────────────────────────────────────────────────────────────────────────────────┤
│                          SYSTEM INTEGRATIONS                                     │
│                                                                                  │
│  ┌──────────┐  ┌──────────┐  ┌─────────────┐  ┌──────────────┐  ┌─────────┐│
│  │AVAudio   │  │ CGEvent  │  │NSPasteboard │  │Accessibility │  │Screen   ││
│  │Engine    │  │(Global   │  │(Clipboard   │  │(Permission   │  │Audio    ││
│  │(Mic)     │  │ Hotkey)  │  │ Paste)      │  │ Control)     │  │Capture  ││
│  └──────────┘  └──────────┘  └─────────────┘  └──────────────┘  └─────────┘│
│                                                                                  │
│  Parakeet working RAM: ~66 MB per active inference slot on ANE                  │
│  Cohere cache: ~/Library/Application Support/FluidAudio/Models/                 │
│                cohere-transcribe/q8                                             │
│  Whisper cache: ~/Library/Application Support/MacParakeet/models/stt/whisper/   │
│  Recommended: 8 GB RAM default path; Cohere has higher memory needs.            │
└──────────────────────────────────────────────────────────────────────────────────┘
```

**Core STT runs on-device.** Optional LLM features use configured providers or Local CLI tools, and telemetry/crash reporting are opt-out. The app supports a fully local setup, but it is not network-free in every configuration.

### Concurrency Model (ADR-015 + ADR-016)

The diagram below shows the ADR-015/ADR-016 architecture. Dictation and meeting recording run concurrently as independent feature pipelines, while microphone capture fans out from one shared engine and STT routes through one scheduler/runtime owner:

```text
┌─ Shared Microphone Capture ───────────────┐
│ SharedMicrophoneStream (one AVAudioEngine)│
│ → AudioRecorder + MicrophoneCapture       │
└───────────────────────────────────────────┘

┌─ Dictation Pipeline ──────────────────────┐
│ AudioRecorder subscriber                  │
│ → DictationService                        │
└───────────────────────────────────────────┘

┌─ Meeting Pipeline ────────────────────────┐
│ MicrophoneCapture subscriber              │
│ + SystemAudioStream when selected         │
│ → MeetingRecordingService                 │
└───────────────────────────────────────────┘

┌─ File / URL Pipeline ─────────────────────┐
│ FFmpeg / AudioConverter / yt-dlp          │
│ → TranscriptionService                    │
└───────────────────────────────────────────┘

                │
                ▼
      STT Scheduler / Control Plane
      ├── Interactive slot  → dictation
      └── Background slot   → meeting + file transcription
                │
                ▼
     STT Runtime (Parakeet/Nemotron/Whisper/Cohere engines)
```

- **Shared microphone engine** — dictation and meeting mic capture subscribe to one process-wide `SharedMicrophoneStream`; downstream feature pipelines stay independent after copying buffers.
- **Meeting mic processing** — meeting mic capture ships as raw mic capture by default to avoid degrading the live call mic heard by other participants; VPIO remains explicit opt-in plumbing, and consumers extract channel 0 if VPIO is engaged.
- **No mutual exclusion** — dictation and meeting recording can both be active.
- **Centralized STT ownership** — one runtime owner manages lifecycle, warm-up, shutdown, and speech-engine dispatch.
- **Explicit scheduling** — the STT stack uses a reserved dictation slot plus a shared background slot; within the background slot, finalize beats live preview, and file transcription waits.
- **Workflow engine routes** — dictation and meetings/transcriptions have independent persisted engine choices on the shared runtime; transcription jobs snapshot their route at start, and a recording pins the dedicated meeting engine/language until stop/cancel.
- **Cohere is batch-only** — Cohere dictation records first and transcribes on stop; meetings use Cohere only for final transcription, not live preview chunks. The scheduler admits Cohere as one global single-flight resource because the engine owns one large batch pipeline rather than separate interactive/background managers.
- **Menu bar icon priority** — meeting > dictation > file-transcription > idle.

---

## Components Detail

### 1. MacParakeet App (GUI — SwiftUI)

The UI layer. Thin shell over MacParakeetCore. No business logic lives here.

#### Main Window

**Responsibility:** Primary in-app navigation shell. Hosts the Transcribe capture hub, Library, Dictations, Vocabulary, Transforms, Feedback, Settings, and Discover surfaces. File/URL transcription, meeting recording, transcript browse, dictation history, prompt actions, Transforms, and settings all route through this window.

**Key Types:**
- `MainWindowView` — `NavigationSplitView` sidebar (Transcribe / Library / Dictations / Vocabulary / Transforms / Feedback / Settings) plus pinned Discover card and a global transcription progress bar
- `TranscribeView` — YouTube card, file drop card, Meeting Recording tile, and transcript detail / progress surfaces
- `TranscriptionLibraryView` — file, YouTube, meeting, and favorite transcript browse with search/sort/filter support
- `TranscriptResultView` — Scrollable text with optional word-level timestamps
- `DictationHistoryView` — Flat chronological list with bottom bar audio player

**Shared Components** (`Views/Components/`):
- `DesignSystem` — Centralized design tokens (Colors, Typography, Spacing, Layout, Animation)
- `BreathWaveLogo` / `BreathWaveIcon.brandMark` — Inline parakeet brand mark
  surfaces backed by the bundled canonical PNG; vector/promo assets live in
  `brand-assets/` and are not runtime dependencies.
- `SacredGeometry` — Shared sacred geometry components:
  - `TriangleShape` — Equilateral triangle Shape
  - `SpinnerRingView` — Compact merkaba spinner
  - `MeditativeMerkabaView` — Large, slow merkaba for empty states
  - `SacredGeometryDivider` — Thin line with centered diamond ornament

**Dependencies:** `TranscriptionService`, `TranscriptionLibraryViewModel`, `ExportService`, `MeetingRecordingPillViewModel`, feature-gated meeting recording coordinators

**Data Flow:**
```
File/URL/meeting action -> MainWindowView/TranscribeView -> TranscriptionService or MeetingRecordingFlowCoordinator
                                                                |
                                                                v
                                                  TranscriptResultView / Library
```

#### Menu Bar

**Responsibility:** Always-visible status indicator. Quick access to dictation, recent files, and settings.

**Key Types:**
- `AppDelegate` — NSStatusItem setup + NSMenu, main window lifecycle (NSWindow + NSHostingView)

**Dependencies:** `DictationService`, app state

#### Dictation Overlay

**Responsibility:** Floating, non-activating panel that shows recording state. Appears near the cursor or in a fixed position. Does not steal focus from the active app.

**Key Types:**
- `DictationOverlayView` — Waveform visualization + status text
- `DictationOverlayController` — NSPanel (non-activating) lifecycle

**Dependencies:** `DictationService` (observes state)

**Design Notes:**
- Uses `NSPanel` with `.nonactivatingPanel` collection behavior so it never steals keyboard focus
- Subclass `NSPanel` as `KeylessPanel` with `canBecomeKey → false` (overlay should never steal focus)
- Audio level visualization driven by `DictationService` publishing amplitude values

#### Settings View

**Responsibility:** User preferences and diagnostics. Four-tab settings shell for modes, local speech engines, optional AI, appearance, system permissions, storage, updates, and retained entitlement diagnostics.

**Key Types:**
- `SettingsView` — Tabbed/searchable shell (`Modes`, `Engine`, `AI`, `System`) with per-tab scroll bodies
- `SettingsRootViewModel` — Owns active-tab persistence and search state
- `SettingsTab` — Stable tab identifiers shared by search and view routing
- `SettingsSearchIndex` — Cross-tab search entries; includes calendar rows while `AppFeatures.calendarEnabled` is `true`, and hides them when the flag is off
- `SettingsViewModel` — Manages settings state, appearance preference, permissions, model status, speech-engine selection, calendar preferences, and legacy entitlement state

**Dependencies:** `UserDefaults`, `CustomWordRepository`, `TextSnippetRepository`, `STTModelManager`, `WhisperModelManager`, `SPUUpdater`

#### Feedback View

**Responsibility:** User feedback submission and community link.

**Key Types:**
- `FeedbackView` — Card-based scrollable container with category selection, form, and community link
- `FeedbackViewModel` — Form state, submission lifecycle, screenshot attachment
- `FeedbackService` — POSTs feedback JSON to `macparakeet.com/api/feedback` (Cloudflare Worker → GitHub Issues)

**Dependencies:** `FeedbackService`

---

### 2. MacParakeetCore (Library — No SwiftUI Dependencies)

The shared core. All business logic, all data access, all service orchestration. Imported by the GUI app and `macparakeet-cli`.
Core may use AppKit for small macOS adapter services (for example pasteboard, System Settings deep links, app termination notification, document export), but does not own SwiftUI views.

#### 2.1 DictationService

**Responsibility:** Orchestrates the full dictation lifecycle: hotkey detection, audio capture, STT, text processing, and text insertion.

**Key Types/Protocols:**
```swift
protocol DictationServiceProtocol: Sendable {
    var state: DictationState { get async }     // .idle, .recording, .processing, .success, .error
    var audioLevel: Float { get async }         // 0.0–1.0, published for overlay waveform
    func startRecording() async throws
    func stopRecording() async throws -> Dictation
    func cancelRecording() async
}

enum DictationState: Sendable {
    case idle
    case recording
    case processing
    case success(Dictation)
    case cancelled
    case error(String)
}
```

**Dependencies:** `AudioProcessor`, shared `STTManaging` scheduler/runtime path, `DictationRepository`, `ClipboardService`

**Data Flow:**
```
Hotkey pressed
    │
    ▼
DictationService.startRecording()
    │ ── AVAudioEngine installs tap on input node
    │ ── Audio buffer accumulates in memory
    │ ── Publishes audioLevel for overlay
    │
Hotkey released (or toggle stop)
    │
    ▼
DictationService.stopRecording()
    │ ── Writes buffer to temp WAV (16kHz mono)
    │ ── Submits a `dictation` job to the shared STT scheduler
    │ ── Receives raw transcript
    │ ── Runs TextProcessingPipeline (if mode == .clean)
    │ ── Saves to DictationRepository
    │ ── Inserts via NSPasteboard + simulated Cmd+V, then restores clipboard
    │
    ▼
DictationResult returned
```

#### 2.2 TranscriptionService

**Responsibility:** Orchestrates file and URL transcription: download/convert audio, run STT, apply optional deterministic cleanup, persist results, emit UI progress phases, and retranscribe saved library items.

**Key Types/Protocols:**
```swift
protocol TranscriptionServiceProtocol: Sendable {
    func transcribe(fileURL: URL) async throws -> Transcription
    func transcribeURL(urlString: String, onProgress: (@Sendable (String) -> Void)?) async throws -> Transcription
}
```

**Dependencies:** `AudioProcessor`, shared `STTManaging` scheduler/runtime path, `TranscriptionRepository`, `YouTubeDownloader`, storage prefs (`saveTranscriptionAudio`, `meetingAudioRetention`)

**Data Flow:**
```
File transcription:
File URL
    │
    ▼
AudioProcessor.convert(fileURL:) → 16kHz mono WAV in temp dir
    │
    ▼
STTScheduler.transcribe(audioPath:, job: .fileTranscription, onProgress:) → raw transcript + word timestamps
    │
    ▼
TranscriptionRepository.save() → persisted to database
    │
    ▼
Transcription returned to UI

Saved meeting retranscription from the library:
Saved meeting audio file
    │
    ▼
AudioProcessor.convert(fileURL:) → 16kHz mono WAV in temp dir
    │
    ▼
STTScheduler.transcribe(audioPath:, job: .fileTranscription, onProgress:) → queued background-slot work
    │
    ▼
Updated Transcription persisted with sourceType still = .meeting

YouTube URL transcription:
YouTube URL
    │
    ▼
YouTubeDownloader.download(url:, onProgress:) → emits download %
    │
    ▼
AudioProcessor.convert(fileURL:) → 16kHz mono WAV in temp dir
    │
    ▼
STTScheduler.transcribe(audioPath:, job: .fileTranscription, onProgress:) → emits chunk %
    │
    ▼
TranscriptionRepository.save() with sourceURL (+ filePath when retention enabled)
    │
    ▼
Transcription returned to UI
```

#### 2.3 TextProcessingPipeline

**Responsibility:** Deterministic, rule-based text cleanup. Runs after STT, before display. Fast, predictable, repeatable.

**Key Types/Protocols:**
```swift
protocol TextProcessingPipelineProtocol {
    func process(_ text: String) -> String
}

// Pipeline stages (executed in order):
// 1. Filler removal (verbal fillers: um, uh, you know, etc.)
// 2. Custom word replacements (vocabulary anchors + corrections)
// 3. Snippet expansion (trigger → expansion)
// 4. Whitespace cleanup (collapse spaces, fix punctuation, capitalize)
```

**Dependencies:** `CustomWordRepository`, `TextSnippetRepository`

**Design Notes:**
- All stages are pure functions over strings — trivially testable
- Custom words loaded once and cached; refreshed on repository change
- Pipeline is synchronous — no async overhead for a few hundred microseconds of work

#### 2.4 AudioProcessor

**Responsibility:** Audio format conversion and resampling. Converts supported input formats to 16kHz mono WAV for the selected local STT engine. Also handles microphone audio buffer management for dictation.

**Key Types/Protocols:**
```swift
protocol AudioProcessorProtocol: Sendable {
    func convert(fileURL: URL) async throws -> URL   // → 16kHz mono WAV
    func startCapture() async throws                  // mic recording
    func stopCapture() async throws -> URL            // → saved WAV
    var audioLevel: Float { get async }               // current amplitude (0.0–1.0)
    var isRecording: Bool { get async }               // capture state
}
```

**Dependencies:** AVFoundation (mic capture), FFmpeg (file conversion — via bundled binary)

**Design Notes:**
- FFmpeg invoked as a subprocess (`Process`), not linked as a library
- Temp files written to app-scoped temp directory, cleaned after use
- Microphone capture uses `AVAudioEngine` with a tap on the input node
- Dictation capture writes temp WAV output and validates minimum samples before STT
- Supports: MP3, WAV, M4A, FLAC, OGG, OPUS, MP4, MOV, MKV, WebM, AVI

#### 2.5 STT Runtime + Scheduler

**Responsibility:** The shared STT stack owns one process-wide runtime actor plus one explicit scheduler. `STTRuntime` owns FluidAudio model lifecycle, the slot-scoped Parakeet TDT `AsrManager` set for the selected v2/v3 build, the dedicated Parakeet Unified engine, the Nemotron engines, optional `WhisperEngine` lifecycle, and engine dispatch. `STTScheduler` owns admission, slot assignment, in-slot priority, backpressure, cancellation, request-scoped progress, speech-engine leases, and guarded engine/model switching. `STTClient` remains as a compatibility facade, not as an app-owned second runtime.

**Key Types/Protocols:**
```swift
public enum STTJobKind: Sendable, Equatable {
    case dictation
    case meetingFinalize
    case meetingLiveChunk
    case fileTranscription
}

public enum STTWarmUpState: Sendable, Equatable {
    case idle
    case working(message: String, progress: Double?)
    case ready
    case failed(message: String)
}

public protocol STTTranscribing: Sendable {
    func transcribe(
        audioPath: String,
        job: STTJobKind,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> STTResult
}

public protocol SpeechEngineRoutedTranscribing: STTTranscribing {
    func transcribe(
        audioPath: String,
        job: STTJobKind,
        speechEngine: SpeechEngineSelection,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> STTResult
}

public protocol STTRuntimeManaging: Sendable {
    func warmUp(onProgress: (@Sendable (String) -> Void)?) async throws
    func backgroundWarmUp() async
    func observeWarmUpProgress() async -> (id: UUID, stream: AsyncStream<STTWarmUpState>)
    func removeWarmUpObserver(id: UUID) async
    func clearModelCache() async
    func isReady() async -> Bool
    func shutdown() async
}

public typealias STTManaging = STTTranscribing & STTRuntimeManaging
public typealias STTClientProtocol = STTManaging

public enum SpeechEnginePreference: String, CaseIterable, Codable, Sendable {
    case parakeet
    case nemotron
    case whisper
    case cohere
}

public enum ParakeetModelVariant: String, CaseIterable, Codable, Sendable {
    case v3
    case v2
    case unified
}

public enum NemotronModelVariant: String, CaseIterable, Codable, Sendable {
    case multilingual1120 = "multilingual-1120ms"
    case english1120 = "english-1120ms"
}

public struct SpeechEngineSelection: Codable, Equatable, Sendable {
    let engine: SpeechEnginePreference
    let language: String?  // Whisper/Nemotron hint, or Cohere's required language; nil means engine default/auto where supported
}

public struct SpeechEngineLease: Equatable, Sendable {
    let id: UUID
    let selection: SpeechEngineSelection
}

public protocol SpeechEngineSwitching: Sendable {
    func setSpeechEngine(_ preference: SpeechEnginePreference) async throws
    func setParakeetModelVariant(_ variant: ParakeetModelVariant) async throws
    func setNemotronModelVariant(_ variant: NemotronModelVariant) async throws
}

public protocol SpeechEngineSessionManaging: Sendable {
    func beginSpeechEngineSession() async -> SpeechEngineLease
    func endSpeechEngineSession(_ lease: SpeechEngineLease) async
}

struct STTResult: Sendable {
    let text: String
    let words: [TimestampedWord]
    let language: String?
}

struct TimestampedWord: Sendable {
    let word: String
    let startMs: Int          // milliseconds
    let endMs: Int            // milliseconds
    let confidence: Double
}
```

**Dependencies:** FluidAudio SDK (CoreML, runs on ANE) for Parakeet, Nemotron, and Cohere, plus optional WhisperKit.

**Architecture:**
```
CPU:  MacParakeet app (UI, hotkeys, clipboard, history)
ANE:  Parakeet/Nemotron/Cohere STT (via FluidAudio/CoreML) — dedicated ML accelerator
CPU/GPU/CoreML as selected by WhisperKit: optional multilingual STT
```

**API:**
```swift
import FluidAudio

let selectedVersion: AsrModelVersion = .v3 // or .v2 for English-only
let models = try await AsrModels.downloadAndLoad(version: selectedVersion)
let manager = AsrManager(config: .default)
try await manager.initialize(models: models)

let result = try await manager.transcribe(samples, source: .system)
// result.text, result.tokenTimings (word-level timestamps + confidence)
```

**Approved Target Ownership Model:**
```
Feature services (Dictation / Meeting / File / URL)
    │
    ▼
STTScheduler
    ├── interactive slot → dictation
    └── background slot  → meetingFinalize > meetingLiveChunk > fileTranscription
    │
    ▼
STTRuntime
    ├── Parakeet v2/v3 slot managers
    ├── Parakeet Unified engine
    ├── Nemotron multilingual / English engines
    ├── optional single-flight CohereTranscribeEngine selected by routed jobs/preferences
    └── optional WhisperEngine selected by routed jobs/preferences
```

**Model Lifecycle:**
```
App Launch
    │
    ▼
STTRuntime.warmUp() called (lazy, on first use or from onboarding)
    │
    ├── Check: Are Parakeet CoreML models downloaded?
    │     │
    │     ├── Yes → initialize slot managers → Runtime ready (~162ms warm load)
    │     │
    │     └── No ──► AsrModels.downloadAndLoad() (~465 MB download)
    │                  CoreML compilation (~3.4s first time)
    │                  initialize slot managers
    │
    ▼
Slot managers ready — scheduler admits transcription jobs

Whisper and Cohere are downloaded explicitly and do not block Parakeet readiness. Switching engines is refused while STT jobs are queued/running or a meeting speech-engine lease is active.
```

Product-level readiness can coordinate additional services beyond the two STT slots. In particular, speaker diarization remains outside the speech scheduler, but onboarding should still account for its required assets before declaring default-on file-transcription features fully ready.

#### 2.6 ExportService

**Responsibility:** Convert transcription results into various output formats.

**Key Types/Protocols:**
```swift
protocol ExportServiceProtocol: Sendable {
    func exportToTxt(transcription: Transcription, url: URL) throws
    func formatForClipboard(transcription: Transcription) -> String
}

// v0.1: .txt only. SRT/VTT/JSON added in v0.3.
```

**Dependencies:** Foundation (file I/O), `NSPasteboard` (clipboard)

**Data Flow:**
```
Transcription (from DB or in-memory)
    │
    ▼
ExportService.exportToTxt(transcription:, url: outputURL)
    │ ── Formats header (filename, duration)
    │ ── Appends transcript text
    │ ── Writes to file
    │
    ▼
File saved at outputURL
```

#### 2.7 Models

All models conform to GRDB's `Codable` + `FetchableRecord` + `PersistableRecord` protocols.

```swift
struct Dictation: Codable, Identifiable, Sendable {
    var id: UUID
    var createdAt: Date
    var durationMs: Int
    var rawTranscript: String
    var cleanTranscript: String?
    var audioPath: String?
    var pastedToApp: String?        // bundle ID of target app
    var processingMode: ProcessingMode  // .raw, .clean
    var status: DictationStatus     // .recording, .processing, .completed, .error
    var errorMessage: String?
    var updatedAt: Date
}

struct Transcription: Codable, Identifiable, Sendable {
    var id: UUID
    var createdAt: Date
    var fileName: String
    var filePath: String?
    var fileSizeBytes: Int?
    var durationMs: Int?
    var rawTranscript: String?
    var cleanTranscript: String?
    var wordTimestamps: [WordTimestamp]?  // JSON-encoded in DB
    var language: String?
    var speakerCount: Int?
    var speakers: [String]?
    var status: TranscriptionStatus  // .processing, .completed, .error, .cancelled
    var errorMessage: String?
    var exportPath: String?
    var sourceURL: String?           // YouTube/web URL (v0.3)
    var updatedAt: Date
}

// CustomWord and TextSnippet models are v0.2+
struct CustomWord: Codable, Identifiable {
    let id: UUID
    var word: String                // what to match (case-insensitive)
    var replacement: String?        // what to replace with (nil = vocabulary anchor)
    var source: Source              // .manual, .learned
    var isEnabled: Bool
    let createdAt: Date
    var updatedAt: Date
}

struct TextSnippet: Codable, Identifiable {
    let id: UUID
    var trigger: String             // e.g., "my address" (natural phrase, not abbreviation)
    var expansion: String           // e.g., "123 Main St, Springfield, IL"
    var isEnabled: Bool
    var useCount: Int
    let createdAt: Date
    var updatedAt: Date
}
```

#### 2.8 Repositories

One repository per table. All use GRDB and follow the same pattern.

```swift
// Canonical pattern (DictationRepository shown):
protocol DictationRepositoryProtocol: Sendable {
    func save(_ dictation: Dictation) throws
    func fetch(id: UUID) throws -> Dictation?
    func fetchAll(limit: Int?) throws -> [Dictation]
    func search(query: String, limit: Int?) throws -> [Dictation]
    func delete(id: UUID) throws -> Bool
    func deleteAll() throws
    func stats() throws -> DictationStats
}

protocol TranscriptionRepositoryProtocol: Sendable {
    func save(_ transcription: Transcription) throws
    func fetch(id: UUID) throws -> Transcription?
    func fetchAll(limit: Int?) throws -> [Transcription]
    func delete(id: UUID) throws -> Bool
    func deleteAll() throws
    func updateStatus(id: UUID, status: Transcription.TranscriptionStatus, errorMessage: String?) throws
}

// CustomWordRepository and TextSnippetRepository follow the same pattern (v0.2+)
```

**Dependencies:** GRDB (`DatabaseQueue`)

**Design Notes:**
- All repositories take a `DatabaseQueue` via init (dependency injection)
- Tests use in-memory SQLite: `DatabaseQueue()` with no path
- Repositories are `final class` (synchronous GRDB calls, thread safety via DatabaseQueue)
- Migrations run inline on app startup (no migration files)

---

### 3. Local STT Engines

Speech recognition runs in the app process. Parakeet via FluidAudio CoreML on the Neural Engine is the default engine family: v3 is the multilingual default, v2 is an English-only TDT opt-in, and Unified is an English-only opt-in with punctuation/capitalization. Three optional local engines extend coverage: Nemotron 3.5 (Beta), a fast FluidAudio CoreML streaming engine with a multilingual default build and an English-only build; Cohere Transcribe, a batch-only FluidAudio CoreML accuracy engine; and WhisperKit for broader language coverage.

**Responsibility:** Speech-to-text transcription using the user's selected local engine.

**Key Details:**

| Property | Value |
|----------|-------|
| Model | Parakeet TDT 0.6B (`v3` multilingual default, `v2` English-only opt-in) plus Parakeet Unified EN 0.6B (`unified`) |
| WER | ~2.5% (v3) / ~2.1% (v2) / ~2.15% average WER on LibriSpeech test-clean (Unified) |
| Speed | ~155x realtime on Apple Silicon |
| Working RAM | ~66 MB (~130 MB with vocab boosting) |
| Runs on | Neural Engine (ANE) via CoreML |
| Input | 16kHz mono Float32 samples |
| Output | Text + word-level timestamps + confidence |
| Model download | ~465 MB CoreML bundle per build; v2 and v3 cache independently |

| Optional Engine (Nemotron, Beta) | Value |
|-----------------|-------|
| Model | Nemotron 3.5 ASR Streaming 0.6B (`nemotron-multilingual-1120ms`, default) / Nemotron Speech Streaming EN 0.6B (`nemotron-english-1120ms`, English-only) |
| Runtime | FluidAudio CoreML streaming path |
| Sizes | ~1.5 GB (multilingual) / ~600 MB (English) |
| Output | Text + token-derived word-level timestamps when FluidAudio reports token timings + detected/specified language |
| Model cache | FluidAudio cache (`nemotron-multilingual/` and `nemotron-streaming/<tier>ms`) |
| Selection | Settings speech-engine + Nemotron Model picker, or CLI `--engine nemotron --nemotron-model <id>` |

| Optional Engine (WhisperKit) | Value |
|-----------------|-------|
| Model | Whisper large-v3 turbo CoreML variant by default |
| Runtime | WhisperKit |
| Languages | Broad multilingual coverage including languages Parakeet does not cover |
| Model cache | `~/Library/Application Support/MacParakeet/models/stt/whisper/` |
| Selection | Settings speech-engine picker or CLI `--engine whisper --language <code>` |

| Optional Engine (Cohere Transcribe) | Value |
|-----------------|-------|
| Model | Cohere Transcribe 03-2026 q8 CoreML (`cohere-transcribe`) |
| Runtime | FluidAudio `CoherePipeline` through `CohereTranscribeEngine` |
| Languages | Supported Cohere language codes; no auto-detect |
| Output | Plain transcript text; no word timestamps, speaker labels, or live partials |
| Model cache | `~/Library/Application Support/FluidAudio/Models/cohere-transcribe/q8` |
| Selection | Settings speech-engine picker or CLI `--engine cohere --language <code>` |

**Why In-Process (Not Daemon)?**
- FluidAudio provides native Swift async/await API — no IPC overhead
- CoreML models run on the ANE, leaving GPU free for the rest of macOS
- Simpler lifecycle: download models once, initialize, call transcribe()
- No Python, no subprocess, no JSON-RPC for STT — pure Swift local engines

```
~/Library/Application Support/MacParakeet/
    └── models/
        └── stt/
            └── whisper/        # WhisperKit model cache

Parakeet, Nemotron, and Cohere FluidAudio caches are managed by FluidAudio per selected build/engine. `models/stt/whisper/` is the MacParakeet-owned cache for WhisperKit downloads.
```

---

## Data Flow Diagrams

### 1. Dictation Flow: Hotkey -> Record -> STT -> Pipeline -> Paste

```
┌─────────┐      ┌─────────────────┐      ┌────────────────┐
│  User    │      │  DictationService│      │  AudioProcessor │
│ (Hotkey) │      │                  │      │                 │
└────┬─────┘      └────────┬────────┘      └────────┬────────┘
     │                     │                        │
     │  Press hotkey       │                        │
     │ ──────────────────> │                        │
     │                     │  startCapture()        │
     │                     │ ─────────────────────> │
     │                     │                        │ ── AVAudioEngine
     │                     │                        │    tap on input
     │                     │    audioLevel updates  │
     │                     │ <───────────────────── │
     │   overlay updates   │                        │
     │ <────────────────── │                        │
     │                     │                        │
     │  Release hotkey     │                        │
     │ ──────────────────> │                        │
     │                     │  stopCapture() → WAV   │
     │                     │ ─────────────────────> │
     │                     │                        │
     │                     │      ┌──────────────┐   │
     │                     │ ───> │STTScheduler  │   │
     │                     │      └──────┬───────┘   │
     │                     │             │           │
     │                     │             │  transcribe(wav, .dictation)
     │                     │             │ ────────────────────┐
     │                     │           │                     │
     │                     │             │    ┌──────────────▼──────┐
     │                     │             │    │ STTRuntime +        │
     │                     │             │    │ selected engine     │
     │                     │             │    └─────────────────────┘
     │                     │           │                     │
     │                     │             │  raw transcript     │
     │                     │             │ <───────────────────┘
     │                     │             │
     │                     │  raw text │
     │                     │ <──────── │
     │                     │
     │                     │      ┌──────────────────────┐
     │                     │ ───> │TextProcessingPipeline│
     │                     │      └──────────┬───────────┘
     │                     │                 │
     │                     │  clean text     │
     │                     │ <───────────────┘
     │                     │
     │                     │  Save to DictationRepository
     │                     │  Copy to NSPasteboard
     │                     │  Simulate Cmd+V via CGEvent
     │                     │
     │   text pasted       │
     │ <────────────────── │
     │                     │
```

### 2. File Transcription Flow: File -> AudioProcessor -> STT -> Display

```
┌──────────────┐    ┌──────────────────────┐    ┌────────────────┐
│  MainWindow  │    │ TranscriptionService │    │ AudioProcessor │
│  (Drop Zone) │    │                      │    │                │
└──────┬───────┘    └──────────┬───────────┘    └───────┬────────┘
       │                       │                        │
       │  File dropped         │                        │
       │ ────────────────────> │                        │
       │                       │  convert(fileURL:)      │
       │                       │ ─────────────────────> │
       │                       │                        │ ── FFmpeg subprocess
       │                       │  16kHz mono WAV        │    input → WAV
       │                       │ <───────────────────── │
       │                       │
       │                       │     ┌──────────────┐
       │                       │ ──> │STTScheduler  │ ──> STTRuntime + selected engine
       │                       │     └─────┬────────┘
       │                       │           │
       │                       │  STTResult (text + timestamps)
       │                       │ <──────── │
       │                       │
       │                       │  Save to TranscriptionRepository
       │                       │
       │  TranscriptionResult  │
       │ <──────────────────── │
       │                       │
       │  Display transcript   │
       │  in TranscriptView    │
       │                       │
```

### 3. Export Flow: Transcription -> Format -> File

```
┌──────────────┐    ┌───────────────┐    ┌───────────────┐
│  MainWindow  │    │ ExportService │    │  File System  │
└──────┬───────┘    └───────┬───────┘    └───────┬───────┘
       │                    │                    │
       │ User clicks Export │                    │
       │ Selects format     │                    │
       │ (e.g., .srt)      │                    │
       │                    │                    │
       │ export(transcription, .srt, outputURL)  │
       │ ─────────────────> │                    │
       │                    │                    │
       │                    │  Read word timestamps
       │                    │  from transcription
       │                    │                    │
       │                    │  Format as SRT:    │
       │                    │  ┌───────────────┐ │
       │                    │  │ 1             │ │
       │                    │  │ 00:00:00,000  │ │
       │                    │  │ --> 00:00:00, │ │
       │                    │  │ 500           │ │
       │                    │  │ Hello world   │ │
       │                    │  └───────────────┘ │
       │                    │                    │
       │                    │  Write to file     │
       │                    │ ─────────────────> │
       │                    │                    │
       │  Success           │                    │
       │ <───────────────── │                    │
       │                    │                    │
```

---

## Database Architecture

Single SQLite file via GRDB. All data in one place. No external database processes.

**Location:** `~/Library/Application Support/MacParakeet/macparakeet.db`

### Representative Schema Excerpt

See [01-data-model.md](01-data-model.md) for the full current schema. The excerpt below highlights the core tables and columns most relevant to the architecture discussion.

```sql
-- Dictation history (voice-to-text sessions)
-- Note: GRDB Codable uses camelCase column names by default
CREATE TABLE dictations (
    id              TEXT PRIMARY KEY,       -- UUID
    createdAt       TEXT NOT NULL,          -- ISO 8601
    durationMs      INTEGER NOT NULL,       -- recording duration in milliseconds
    rawTranscript   TEXT NOT NULL,          -- exact STT output
    cleanTranscript TEXT,                   -- after TextProcessingPipeline (v0.2+)
    audioPath       TEXT,                   -- relative path to saved audio (nullable)
    pastedToApp     TEXT,                   -- bundle ID of target app
    processingMode  TEXT NOT NULL DEFAULT 'raw', -- 'raw' (v0.1) or 'clean' (v0.2 default via UserDefaults)
    hidden          BOOLEAN NOT NULL DEFAULT 0,  -- private dictation mode (v0.5)
    wordCount       INTEGER NOT NULL DEFAULT 0,  -- cached for voice stats (v0.5)
    engine          TEXT,                   -- STT engine attribution (v0.8)
    engineVariant   TEXT,                   -- engine-specific model variant (v0.8)
    status          TEXT NOT NULL DEFAULT 'completed', -- 'recording' | 'processing' | 'completed' | 'error'
    errorMessage    TEXT,                   -- non-null if status == 'error'
    updatedAt       TEXT NOT NULL
);
CREATE INDEX idx_dictations_created_at ON dictations(createdAt);

-- File transcription history
CREATE TABLE transcriptions (
    id              TEXT PRIMARY KEY,       -- UUID
    createdAt       TEXT NOT NULL,          -- ISO 8601
    fileName        TEXT NOT NULL,          -- original file name
    filePath        TEXT,                   -- original file path
    fileSizeBytes   INTEGER,               -- original file size
    durationMs      INTEGER,               -- audio duration in milliseconds
    rawTranscript   TEXT,                   -- exact STT output
    cleanTranscript TEXT,                   -- after TextProcessingPipeline (v0.2+)
    wordTimestamps  TEXT,                   -- JSON: [{"word":...,"startMs":...,"endMs":...,"confidence":...}]
    diarizationSegments TEXT,               -- JSON speaker segments (v0.4+)
    language        TEXT DEFAULT 'en',      -- detected language
    speakerCount    INTEGER,               -- number of speakers (v0.4+)
    speakers        TEXT,                   -- JSON: [{"id":"S1","label":"Speaker 1"}, ...] (v0.4+)
    sourceType      TEXT NOT NULL DEFAULT 'file', -- file | youtube | meeting (v0.6)
    thumbnailURL    TEXT,                   -- YouTube thumbnail URL (v0.5)
    channelName     TEXT,                   -- YouTube channel name (v0.5)
    videoDescription TEXT,                  -- YouTube video description (v0.5)
    isFavorite      BOOLEAN NOT NULL DEFAULT 0, -- favorite marker (v0.5)
    recoveredFromCrash BOOLEAN NOT NULL DEFAULT 0, -- recovered interrupted meeting (v0.7.5)
    isTranscriptEdited BOOLEAN NOT NULL DEFAULT 0, -- user-edited transcript flag (v0.7.7)
    userNotes       TEXT,                   -- meeting notes (v0.8)
    engine          TEXT,                   -- STT engine attribution (v0.8)
    engineVariant   TEXT,                   -- engine-specific model variant (v0.8)
    derivedTitle    TEXT,                   -- cached display title (v0.9)
    derivedSnippet  TEXT,                   -- cached display preview (v0.9)
    status          TEXT NOT NULL DEFAULT 'processing', -- 'processing' | 'completed' | 'error' | 'cancelled'
    errorMessage    TEXT,                   -- non-null if status == 'error'
    exportPath      TEXT,                   -- path to exported file
    sourceURL       TEXT,                   -- YouTube/web URL (v0.3)
    updatedAt       TEXT NOT NULL
);
CREATE INDEX idx_transcriptions_created_at ON transcriptions(createdAt);

-- Additional active tables omitted here for brevity:
-- custom_words, text_snippets, chat_conversations, prompts, summaries (PromptResult),
-- lifetime_dictation_stats, quick_prompts
```

### Migrations

Migrations run inline on app startup (not separate files). Pattern:

```swift
var migrator = DatabaseMigrator()

migrator.registerMigration("v0.1-dictations") { db in
    try db.create(table: "dictations") { t in
        t.column("id", .text).primaryKey()
        t.column("createdAt", .text).notNull()
        t.column("durationMs", .integer).notNull()
        t.column("rawTranscript", .text).notNull()
        t.column("cleanTranscript", .text)
        t.column("audioPath", .text)
        t.column("pastedToApp", .text)
        t.column("processingMode", .text).notNull().defaults(to: "raw")
        t.column("status", .text).notNull().defaults(to: "completed")
        t.column("errorMessage", .text)
        t.column("updatedAt", .text).notNull()
    }
    // Historical note: v0.1 also created an FTS5 table + sync triggers.
    // Those were removed in v0.5 after the app standardized on LIKE search.
}

migrator.registerMigration("v0.1-transcriptions") { db in
    try db.create(table: "transcriptions") { ... }
}

try migrator.migrate(dbQueue)
```

### Entity-Relationship Diagram

```
dictations ──logical update──> lifetime_dictation_stats
     │
     └──optional FK from llm_runs for persisted formatter metadata

transcriptions
     ├──< chat_conversations
     ├──< summaries / PromptResult
     └──optional FK from llm_runs for persisted formatter metadata

summaries / PromptResult ───────optional FK from llm_runs
chat_conversations ─────────────optional FK from llm_runs
transform_history ──────────────optional FK from llm_runs

prompts
     ├──category "summary"   -> prompt library / summary generation
     └──category "transform" -> Transforms tab + CLI `transforms`

quick_prompts  -> live meeting Ask shortcut pills
custom_words   -> vocabulary anchors/corrections
text_snippets  -> text snippets + trailing action snippets
daily_dictation_stats -> per-day Stats heatmap/streak rollup
```

`spec/01-data-model.md` is the canonical schema reference. This architecture
document shows only relationships that matter to service boundaries: feature
tables own their full content, while `llm_runs` stores metadata-only source
links for durable LLM operations and cascades away when its source row is
deleted.

---

## File Locations

| Item | Path |
|------|------|
| App bundle | `/Applications/MacParakeet.app` |
| Database | `~/Library/Application Support/MacParakeet/macparakeet.db` |
| Dictation audio | `~/Library/Application Support/MacParakeet/dictations/` |
| Transcription exports | `~/Library/Application Support/MacParakeet/transcriptions/` |
| Parakeet STT models | FluidAudio-managed CoreML cache (~465 MB per build) |
| Cohere STT model | `~/Library/Application Support/FluidAudio/Models/cohere-transcribe/q8` |
| Whisper STT models | `~/Library/Application Support/MacParakeet/models/stt/whisper/` |
| Local LLM models (developer-gated, opt-in download) | `~/Library/Application Support/MacParakeet/LLMModels/` |
| yt-dlp binary | `~/Library/Application Support/MacParakeet/bin/yt-dlp` |
| FFmpeg binary | `~/Library/Application Support/MacParakeet/bin/ffmpeg` |
| Logs | `~/Library/Logs/MacParakeet/` |
| Temp audio | `$TMPDIR/macparakeet/` (cleaned after use) |
| Settings | `UserDefaults` (standard `com.macparakeet.MacParakeet.plist`) |

### Directory Layout

```
~/Library/Application Support/MacParakeet/
    ├── macparakeet.db              # SQLite database (all app data)
    ├── dictations/                 # Saved dictation audio files
    │   ├── {uuid}.wav              # Flat storage, no date subdirectories
    │   └── ...
    ├── models/                     # MacParakeet-owned downloaded ML models
    │   └── stt/
    │       └── whisper/            # WhisperKit models
    ├── LLMModels/                  # Verified opt-in local LLM model cache (developer-gated)
    └── bin/                        # Standalone binaries
        ├── yt-dlp                  # YouTube downloader (~35 MB, self-updating)
        └── ffmpeg                  # Video demuxing (~80 MB)
```

---

## Dependencies

### Swift Packages

| Package | SPM ID | Purpose | Notes |
|---------|--------|---------|-------|
| FluidAudio | `FluidAudio` | Default STT engine (Parakeet TDT via CoreML/ANE), optional Nemotron/Cohere engines, and diarization | Apache 2.0. Use `FluidAudio` product only — NOT `FluidAudioEspeak` (GPL-3.0, would require open-sourcing). |
| WhisperKit | `argmax-oss-swift` | Optional local multilingual STT engine | Exact 0.18.0 when enabled; `MACPARAKEET_SKIP_WHISPERKIT=1` skips the package for compatibility checks. |
| GRDB.swift | `GRDB` | SQLite database | v6.29.0+, single-file storage, migrations, Codable records |
| swift-argument-parser | `ArgumentParser` | CLI (implemented) | `macparakeet-cli transcribe`, `history`, `health`, `models`, `vocab`, `transforms` |

### Bundled / Downloaded Binaries

| Tool | Purpose | Notes |
|------|---------|-------|
| yt-dlp | YouTube audio download | Standalone macOS binary (~35 MB), self-updates via `--update` |
| FFmpeg | Video file demuxing | Extracts audio from video containers (mp4/mov/mkv/webm/avi) |

### System Frameworks

| Framework | Purpose |
|-----------|---------|
| AVFoundation / AVAudioEngine | Microphone capture |
| CoreGraphics (CGEvent) | Global hotkey detection, simulated keystrokes (Cmd+V) |
| AppKit (NSPasteboard) | Clipboard read/write for paste |
| Accessibility (AXUIElement) | Global hotkey, paste simulation |
| SwiftUI | All UI |
| UniformTypeIdentifiers | File type detection for drag-and-drop |

---

## Security & Privacy

### Permissions Required

| Permission | Reason | When Requested | Required? |
|------------|--------|----------------|-----------|
| Microphone | Dictation recording | First dictation attempt | Yes (for dictation) |
| Accessibility | Global hotkey + simulated paste + read selection | First dictation attempt | Yes (for dictation) |

### Permission Flow

```
First Launch
    │
    ▼
Show onboarding: explain what permissions are needed and why
    │
    ▼
User triggers first dictation
    │
    ├── Microphone permission dialog (system)
    │     ├── Granted → continue
    │     └── Denied → show "enable in System Settings" guidance
    │
    ├── Accessibility permission dialog (system)
    │     ├── Granted → continue
    │     └── Denied → show guidance (hotkey + paste won't work)
    │
    ▼
Dictation ready
```

### Privacy Guarantees

1. **No cloud STT** — Speech recognition stays local. Network is used only for explicit surfaces such as model downloads, update checks, optional LLM providers, optional telemetry/crash reporting, retained purchase activation endpoints if explicitly invoked, and user-initiated YouTube downloads.
2. **Temp files cleaned** — Audio files in `$TMPDIR` deleted immediately after transcription
3. **No accounts** — No login, no email, no user tracking
4. **Telemetry is opt-out** — Self-hosted usage analytics and crash reporting run only while telemetry is enabled
5. **Audio storage is opt-in** — Dictation audio only saved if user enables "Keep audio" in settings
6. **Local AI only** — All ML inference happens on-device: STT on the ANE via CoreML

### Runtime Permissions

| Permission | Required For | User Flow |
|------------|--------------|-----------|
| Microphone | Dictation, onboarding mic test, meeting recording mic capture | Requested during onboarding or first dictation/meeting use |
| Accessibility | Global hotkey paste simulation | Requested during onboarding or first dictation use |
| Screen & System Audio Recording | ScreenCaptureKit system-audio capture for meeting source modes that include system audio | Optional during onboarding; otherwise requested on first system-audio meeting attempt; system-audio modes stay blocked until granted |
| Calendar | Calendar reminders and optional meeting auto-start | Requested from onboarding or Settings calendar controls |

### Sandboxing (App Store)

For App Store distribution, the app needs:

| Entitlement | Required For |
|-------------|-------------|
| `com.apple.security.device.audio-input` | Microphone access |
| `com.apple.security.personal-information.calendars` | Calendar event access |
| `com.apple.security.temporary-exception.apple-events` | Accessibility (paste simulation) |
| `com.apple.security.files.user-selected.read-write` | File drag-and-drop |
| `com.apple.security.files.downloads.read-write` | Export to Downloads |
| Hardened Runtime | Code signing requirement |

**Sandboxing Challenges:**
- Accessibility API (`AXUIElement`) requires the app to be in the Accessibility allow-list, which is a system-level permission, not an entitlement
- FFmpeg and yt-dlp subprocesses need careful path handling within the sandbox container
- CoreML runs in-process — no subprocess restrictions apply to STT
- Direct distribution (notarized DMG) avoids most sandbox restrictions

---

## Performance

### Memory Budget

```
┌────────────────────────────────────────────────────────────┐
│                    Memory at Peak                           │
├────────────────────────────────────────────────────────────┤
│  Parakeet STT (CoreML/ANE)       ~66 MB per active slot    │
│  Optional WhisperKit engine      model-dependent           │
│  App process (UI + services)     ~100 MB                   │
│  Audio buffers                   ~50 MB                    │
│  ──────────────────────────────────────                    │
│  Total peak                      depends on active engines │
│                                                            │
│  Minimum system RAM: 8 GB (Apple Silicon)                  │
└────────────────────────────────────────────────────────────┘
```

### Startup Performance

| Phase | Target | Strategy |
|-------|--------|----------|
| App window visible | <1 second | SwiftUI, no heavy init |
| Dictation ready | <2 seconds | Post-onboarding (models pre-warmed) |
| First STT result | <3 seconds | Default Parakeet model warm-up on first transcribe call |

**Model Readiness Strategy:**
```
First Launch ────────> Onboarding model setup step
                           └── Download + warm Parakeet STT
                           ▼
                       Ready state unlocked
                           │
Subsequent Launches ──> Window shown (fast)
                           │
                           ▼
                       Dictation runs immediately
```

After initial warm-up, subsequent dictations are near-instant because the shared runtime keeps its slot managers initialized and ready between requests.

### Transcription Speed

| Audio Length | Transcription Time (M1) | Transcription Time (M1 Pro+) |
|-------------|------------------------|-------------------------------|
| 1 minute | ~0.4 seconds | ~0.2 seconds |
| 10 minutes | ~4 seconds | ~2 seconds |
| 1 hour | ~23 seconds | ~12 seconds |
| 4 hours (max) | ~93 seconds | ~46 seconds |

Parakeet TDT 0.6B throughput varies by device class: v3 is approximately 155x realtime on baseline M1 and up to ~300x on M1 Pro+ hardware via FluidAudio CoreML/ANE; v2 is slightly faster on English-only audio.

### Memory Management

- **Parakeet model:** One shared runtime owner keeps its managers initialized after first use. Budget ~66 MB working RAM per active inference slot on the ANE path. Real total memory depends on how many managers are loaded/active in the current implementation, whether the background capacity stays lazy in the final design, and whether diarization models are also resident.
- **Cohere model:** Loaded only when selected; downloaded explicitly to the FluidAudio cache. It is batch-only and has a larger resident footprint than Parakeet, so it is not part of the default readiness path.
- **Whisper model:** Loaded only when selected; model size and runtime memory are variant-dependent. Default cache is `models/stt/whisper/`.
- **Audio buffers:** Dictation writes temp WAV on stop; meeting recording writes fragmented source M4A files and lock files during capture. Completed meeting audio is retained by default but can be detached from the transcript through GUI/CLI cleanup. No recording duration limit beyond disk space and practical UI constraints.
- **Database:** GRDB uses WAL mode by default. No connection pooling needed (single-user app).

### Background Model Pre-warming

After the user's first dictation session, pre-warm models in the background:

```
First dictation completes
    │
    ▼
Schedule background task (low priority):
    └── If Parakeet model not loaded → initialize the shared runtime's slot managers
```

This ensures subsequent interactions feel instant without bloating initial startup.

---

## Testing Strategy

### Philosophy

"Write tests. Not too many. Mostly integration."

MacParakeet has a small surface area compared to Oatmeal. Focus testing on the core pipeline, not on UI chrome.

### Test Categories

| Category | What | How | Example |
|----------|------|-----|---------|
| Unit | Pure logic, models, pipeline stages | XCTest, fast, no I/O | `TextProcessingPipelineTests` |
| Database | CRUD, queries, migrations | In-memory SQLite via GRDB | `DictationRepositoryTests` |
| Integration | Service boundaries, multi-step flows | Protocol mocks, DI | `TranscriptionServiceTests` |
| Manual | Audio capture, paste, hotkeys | Real hardware | Checklist-based |

### What We Test

- **TextProcessingPipeline** — Every stage, edge cases, custom word matching, snippet expansion
- **Models** — Codable round-trip, validation, edge cases
- **Repositories** — CRUD operations, search queries, migration correctness
- **ExportService** — Format generation (TXT in v0.1; SRT, VTT, JSON in v0.3)
- **STT scheduler/runtime boundary** — mock the `STTClientProtocol` interface (`STTManaging`) rather than real FluidAudio
- **AudioProcessor** — Format detection, conversion parameter correctness (mock FFmpeg)

### What We Skip

- **SwiftUI views** — Test ViewModels, not views
- **AVAudioEngine** — Requires real hardware microphone
- **CGEvent / Accessibility** — Requires system permissions, not testable in CI
- **Parakeet model accuracy** — That is the model's problem, not ours

### Test Infrastructure

```swift
// In-memory database for tests (canonical pattern):
func makeTestDatabase() throws -> DatabaseQueue {
    let dbQueue = try DatabaseQueue()
    var migrator = DatabaseMigrator()
    // Register all migrations
    registerMigrations(&migrator)
    try migrator.migrate(dbQueue)
    return dbQueue
}

// Protocol-based mocking:
actor MockSTTClient: STTClientProtocol {
    var transcribeResult: STTResult?
    var transcribeError: Error?
    var ready = true

    func configure(result: STTResult) { transcribeResult = result; transcribeError = nil }
    func configure(error: Error) { transcribeError = error; transcribeResult = nil }

    func transcribe(
        audioPath: String,
        job: STTJobKind,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> STTResult {
        if let error = transcribeError { throw error }
        guard let result = transcribeResult else { throw STTError.modelNotLoaded }
        return result
    }
    func warmUp(onProgress: (@Sendable (String) -> Void)?) async throws {}
    func backgroundWarmUp() async {}
    func observeWarmUpProgress() async -> (id: UUID, stream: AsyncStream<STTWarmUpState>) {
        (UUID(), AsyncStream { continuation in
            continuation.yield(.idle)
            continuation.finish()
        })
    }
    func removeWarmUpObserver(id: UUID) async {}
    func clearModelCache() async {}
    func isReady() async -> Bool { ready }
    func shutdown() async {}
}
```

### Running Tests

```bash
# All tests (unit + database + integration)
swift test

# Parallel execution
swift test --parallel

# Filter to specific test class
swift test --filter TextProcessingPipelineTests
```

Note: `swift test` works for all tests. Use `xcodebuild` for building the GUI app.

---

## Build & Run

### Commands

```bash
# Build GUI app
xcodebuild build \
    -scheme MacParakeet \
    -destination 'platform=OS X' \
    -derivedDataPath .build/xcode

# Run GUI app
.build/xcode/Build/Products/Debug/MacParakeet.app/Contents/MacOS/MacParakeet

# Run tests (swift test works fine for tests)
swift test

# Open in Xcode
open Package.swift
```

---

## Architecture Principles

1. **MacParakeetCore has no SwiftUI/view ownership.** Core is primarily Foundation + GRDB + FluidAudio + optional WhisperKit. AppKit is limited to small macOS adapter services with no Foundation-only alternative (clipboard, permission deep links, app termination notification, export). This keeps business logic testable without moving platform shims into SwiftUI views.

2. **Protocol-first services.** Every service has a protocol. Tests inject mocks. No singletons.

3. **Local-only for user data.** Core speech inference has no cloud or API-key dependency. Network is only for model artifacts, optional LLM providers, update/telemetry surfaces, retained purchase activation/validation if explicitly invoked, and user-initiated media downloads.

4. **Fast launch + onboarding pre-warm.** App launch stays lightweight; first-run onboarding prepares STT model so core features feel ready immediately afterward.

5. **Single database file.** All persistent state in one SQLite file. Easy to backup, easy to debug, easy to reset.

6. **Deterministic pipeline.** `TextProcessingPipeline` is rule-based and repeatable. Users choose raw or clean mode.

7. **Crash gracefully.** If CoreML fails, retry. If paste fails, copy to clipboard and notify. Never lose the transcript.

---

*Last updated: 2026-06-14*
