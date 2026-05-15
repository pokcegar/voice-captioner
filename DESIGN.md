# Design

## Source of truth
- Status: Draft
- Last refreshed: 2026-05-15
- Primary product surfaces: macOS SwiftUI app, meeting history sidebar, record/transcribe workflow, local settings/preferences.
- Evidence reviewed:
  - `README.md` local-first v1 workflow: record -> stop -> local Whisper -> Markdown/SRT/JSON export -> history.
  - `Sources/VoiceCaptionerApp/ContentView.swift`: current single detail screen mixes capture settings, UI language, model setup, record controls, transcription controls, capabilities, preview, and selected meeting details.
  - `Sources/VoiceCaptionerAppModel/VoiceCaptionerAppModel.swift`: UI language defaults to Chinese; Whisper process currently runs post-stop transcription.

## Brand
- Personality: practical, local-first, trustworthy, utility-first.
- Trust signals: explicit local-only language, visible output paths, visible model/executable source, clear permission state.
- Avoid: mixing app preferences with task controls, ambiguous “language” labels, implying live captions when the build only supports post-stop transcription.

## Product goals
- Goals:
  - Let users record a meeting locally, then transcribe locally and export artifacts.
  - Make it obvious what is app preference, what is capture setting, and what is transcription setting.
  - Make Chinese-first use work by default while preserving future multilingual support.
- Non-goals:
  - No cloud transcription.
  - No hidden translation unless the user explicitly enables translation.
  - No claim of real-time subtitles until live transcription exists.
- Success signals:
  - A user can tell “界面语言” is only UI chrome.
  - A user can tell “转写语言/音频语言” affects Whisper recognition.
  - A user can tell whether transcript output is live or available only after stopping.

## Personas and jobs
- Primary personas: Chinese-speaking macOS user recording calls/meetings locally.
- User jobs:
  - Start/stop local capture with minimal setup.
  - Transcribe Chinese speech as Chinese text.
  - Export and reopen meeting transcripts.
  - Optionally change the app UI language without changing recognition behavior.
- Key contexts of use: desktop meeting/call recording, local file review, privacy-sensitive environments.

## Information architecture
- Primary navigation:
  - Sidebar: meeting history.
  - Detail: selected meeting workspace.
  - App-level Preferences/Settings: app behavior and appearance.
- Core screens/sections:
  1. Meeting workspace: selected meeting, transcript, artifacts, status.
  2. Capture controls: title, output directory, start/stop, permissions.
  3. Transcription controls: spoken audio language, model, whisper executable, transcribe/cancel/regenerate.
  4. App settings: interface language, theme/appearance in the future.
- Content hierarchy:
  - Primary actions first: Record / Stop / Transcribe.
  - Transcript output panel stays close to actions.
  - Advanced local Whisper configuration is collapsible or below primary flow.
  - App preference controls must not appear inside the recording section.

## Design principles
- Principle 1: Separate app preferences from meeting workflow controls.
- Principle 2: Use precise labels for language:
  - “界面语言” means UI language only.
  - “音频语言” or “转写语言” means spoken-language recognition.
  - “翻译目标语言” means translation output and must be opt-in.
- Principle 3: State capability honestly. If output appears only after stop/transcribe, call it “转写预览/转写结果”, not “实时字幕”.
- Tradeoffs:
  - Fewer controls in the primary workflow reduce confusion, but advanced model/debug controls still need a discoverable place.

## Visual language
- Color: use macOS system colors; reserve accent/green for ready/success, red for recording, orange/yellow for warnings.
- Typography: native SwiftUI hierarchy; large title for app/meeting context, headline for sections, caption for status/explanations.
- Spacing/layout rhythm: sectioned workspace with clear grouping; avoid one long undifferentiated form.
- Shape/radius/elevation: native grouped forms/cards.
- Motion: minimal; do not animate transcript as if live unless real live updates exist.
- Imagery/iconography: SF Symbols only; record, stop, waveform, folder, gear.

## Components
- Existing components to reuse:
  - `NavigationSplitView` meeting sidebar.
  - Grouped `Form` sections.
  - Status text and capability rows.
- New/changed components:
  - App Preferences panel/menu for “界面语言”.
  - Capture card for recording-only settings and controls.
  - Transcription card for model/executable/spoken-language/export controls.
  - Transcript output card with explicit state: empty, recording, ready to transcribe, transcribing, complete, failed.
- Variants and states:
  - Recording active: Start disabled, Stop emphasized, transcript card says “录音中，停止后可本地转写” unless live mode is implemented.
  - Post-stop ready: Transcribe primary action enabled if model/executable exist.
  - Transcribing: progress/status visible, Cancel enabled.
  - Complete: export buttons enabled.
- Token/component ownership: keep SwiftUI-native; no new design-system package for v1.

## Accessibility
- Target standard: native macOS accessibility with keyboard reachable controls and clear labels.
- Keyboard/focus behavior: primary actions reachable by tab; Preferences not buried in workflow.
- Contrast/readability: use system text colors and avoid status-only color semantics.
- Screen-reader semantics: controls must expose precise labels such as “界面语言” and “转写语言”.
- Reduced motion and sensory considerations: no required animation.

## Responsive behavior
- Supported breakpoints/devices: macOS desktop window, minimum width around current 860px detail.
- Layout adaptations:
  - Sidebar remains history.
  - Detail sections can stack vertically.
  - Advanced settings can collapse to reduce scrolling.
- Touch/hover differences: not applicable for v1 macOS desktop.

## Interaction states
- Loading: “正在扫描模型/会议/权限”.
- Empty: no meeting selected, no transcript yet.
- Error: show typed local error and recovery action.
- Success: show artifact paths and open buttons.
- Disabled: disabled actions must include nearby reason text.
- Offline/slow network: not relevant to core workflow because v1 is local-only.

## Content voice
- Tone: direct, Chinese-first, precise.
- Terminology:
  - “录音” for capture.
  - “转写” for speech-to-text in same language.
  - “翻译” only when language translation is enabled.
  - “界面语言” for UI chrome.
  - “音频语言/转写语言” for Whisper `-l`.
- Microcopy rules:
  - Do not say “实时” unless text updates while recording.
  - Always say local/no cloud where trust matters.
  - Avoid generic “语言” labels.

## Implementation constraints
- Framework/styling system: SwiftUI + AppKit panels.
- Design-token constraints: system colors/fonts; no new dependency.
- Performance constraints: local Whisper is CPU/GPU-heavy; live mode requires careful chunk scheduling and cancellation.
- Compatibility constraints: packaged app bundles `whisper-cli` and local models; model binaries remain untracked.
- Test/screenshot expectations:
  - UI smoke should verify default Chinese labels.
  - Core tests should verify default `-l zh` and no `-tr`.
  - If live transcript ships, add tests for incremental chunk/status behavior.

## Open questions
- [ ] Should v1 remain post-stop transcription only, or should “实时字幕/实时转写” become the next feature? Owner: product. Impact: capture/transcription architecture and UI.
- [ ] Should spoken audio language be fixed to Chinese for now, or exposed as “中文/自动/English/Deutsch/…” in transcription settings? Owner: product. Impact: UI scope and Whisper arguments.
- [ ] Should translation be included at all? If yes, it needs a separate opt-in “翻译为…” control, not the same as transcription language. Owner: product. Impact: model quality, labels, exports.
