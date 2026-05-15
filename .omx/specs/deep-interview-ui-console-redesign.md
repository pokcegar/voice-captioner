# Deep Interview Spec: UI Console Redesign

## Metadata
- Profile: standard
- Context type: brownfield
- Final ambiguity: 18%
- Threshold: 20%
- Source transcript: `.omx/interviews/ui-console-redesign-<timestamp>.md`
- Context snapshot: `.omx/context/ui-console-redesign-20260515T072804Z.md`

## Intent
Reduce UI confusion in VoiceCaptioner. The current UI piles history, recording controls, model settings, app language, transcription actions, permissions, and transcript output into one detail scroll. The redesign should arrange the app by the user's workflow.

## Desired outcome
A console-style macOS interface where users can immediately understand:
- Left = meeting history.
- Center = current meeting workspace: recording status, delayed live subtitles, final transcript/Markdown editor.
- Right = settings, grouped and prioritized.

## In scope

### Layout / information architecture
- Keep left sidebar as meeting history.
- Make center the primary current-meeting workspace:
  - recording state / timer / status,
  - start/stop controls,
  - delayed live subtitle display during recording,
  - final transcript preview after recording,
  - lightweight Markdown text editor for edited transcript.
- Make right side the settings panel:
  - common settings visible first,
  - settings grouped clearly,
  - advanced settings collapsible,
  - settings auto-collapse or visually de-emphasize during recording so center captions dominate.

### Language model
- Keep existing UI language setting: Chinese / English / German.
- UI language must be labeled as **界面语言** and treated as app preference.
- First pass meeting/transcription language is **fixed Chinese**.
- Do not expose a confusing meeting-language selector until multi-language support is intentionally designed.
- If shown, spoken language should appear as a non-confusing readout like `转写语言：中文` rather than a broad language picker.

### Markdown editor
- Machine-generated transcript remains `final.md`.
- User-edited Markdown is stored separately, e.g. `edited.md` or `user-edited.md`.
- If user-edited file does not exist, initialize editor content from `final.md`.
- Save user edits only to the edited file.
- SRT/JSON do not need to sync from user edits.

## Out of scope / non-goals
- No rich Markdown editor.
- No segment-by-segment subtitle editor.
- No automatic reverse-sync from edited Markdown to SRT/JSON.
- No multi-language meeting-language selector in first pass.
- No auto language detection in first pass.
- No translation feature.
- No zero-latency subtitle claim; current capability is delayed live draft transcription.

## Decision boundaries
OMX may decide without further confirmation:
- Exact SwiftUI implementation structure for left/center/right console layout.
- Exact file name for the edited Markdown if it is clearly separate from `final.md`.
- Exact grouping labels for right settings, as long as app settings and meeting/transcription settings are separated.
- Whether settings collapse is automatic, manual, or both during recording, as long as recording emphasizes center captions.

Ask before changing:
- Adding non-Chinese meeting-language support.
- Adding translation.
- Replacing the lightweight text editor with a rich editor.
- Changing export contracts for SRT/JSON.

## Constraints
- SwiftUI macOS app.
- Local-only workflow.
- Keep existing bundled Whisper/model behavior.
- Keep Chinese transcription default (`-l zh`, no `-tr`).
- Preserve existing history and export flow.

## Acceptance criteria
1. Main window visually separates history, current meeting workspace, and settings.
2. UI language control is not inside recording controls and is clearly labeled as interface language.
3. Center workspace clearly shows recording/subtitle state during recording.
4. Center workspace supports lightweight Markdown editing after a transcript exists.
5. Editing does not overwrite `final.md`; it writes a separate user-edited Markdown file.
6. Right settings prioritize common settings and group advanced settings clearly.
7. During recording, settings do not dominate the UI; center captions/status are visually primary.
8. First pass meeting transcription language remains Chinese-only and does not present a misleading multi-language selector.
9. Tests cover edited Markdown artifact behavior and default Chinese transcription behavior.
10. App builds and packages successfully.

## Brownfield evidence
- `ContentView.swift` currently has left history but puts most controls/output in a single detail scroll.
- `Localization.swift` already supports UI language strings for Chinese/English/German.
- `WhisperProcessTranscriber` now defaults to Chinese transcription.
- `LiveTranscriptionPipeline` supports delayed live draft segments.

## Recommended next step
Run `$ralplan` against this spec, then implementation via `$team` or direct execution depending on plan size.
