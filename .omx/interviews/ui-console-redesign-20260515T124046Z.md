# Deep Interview Transcript: UI Console Redesign

- Date: 2026-05-15
- Profile: standard
- Context: brownfield VoiceCaptioner SwiftUI app
- Final ambiguity: 18% (threshold 20%)

## Rounds

1. **Intent / outcome**
   - User wants to solve confusion, not make the UI flashy: current UI is just a pile of functions, not arranged by customer/user experience.

2. **Concept split**
   - UI already supports Chinese/English/German.
   - Missing feature: meeting spoken/transcription language selection.
   - Important distinction: interface language is not meeting/transcription language.

3. **Right-side settings behavior**
   - User wants A/B/C combined:
     - Common settings visible first.
     - All settings clearly grouped.
     - Recording mode should auto-collapse settings to emphasize the center workspace.

4. **Center workspace editing scope**
   - Center should include current meeting status and subtitles during recording.
   - After recording, final transcript preview should support lightweight Markdown editing.
   - No heavy editor needed; user will send Markdown to other tools, formatting does not need to be perfect.

5. **Markdown artifact boundary**
   - Machine-generated original Markdown should remain untouched.
   - User edits should be stored in a separate Markdown file.

6. **Meeting/transcription language first pass**
   - First pass should only support Chinese for meeting/transcription language.
   - Defer multi-language selection, auto-detect, and translation.

## Pressure pass finding

Earlier assumption: "language" might be a unified app-level setting.
Pressure result: it must be split conceptually, but implementation can defer meeting-language controls by fixing v1 spoken language to Chinese. This prevents a misleading selector while preserving the design distinction.
