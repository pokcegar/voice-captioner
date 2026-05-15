# voice-captioner

voice-captioner is an open-source, local-first macOS app for meeting capture and delayed transcription.

The v1 direction is intentionally narrow:

- Full SwiftUI Mac app.
- Whole-system output audio and microphone input as separated source tracks.
- Optional mixed audio as a derived export.
- Default 30-second delayed rolling transcript, adjustable by the user.
- Final transcript export as Markdown, SRT, and JSON.
- Folder-indexed meeting history.
- Whisper model downloader plus manual local model selection.
- No AI summary, chat, agent, or cloud processing in v1.

## Current Status

This repository currently contains the Swift package skeleton and tested core foundations:

- Meeting folder creation and folder-index history.
- Metadata model for separated audio tracks.
- Transcript segment merge and draft/final replacement.
- Markdown, SRT, and JSON transcript export.
- Whisper process adapter boundary.
- Model registry for downloaded/manual model files.
- Minimal SwiftUI app shell for settings/history scaffolding.

Native live capture is intentionally gated at the capture layer. Phase 1/2 capture work can continue, but broad UI/transcription integration must wait for the gate to pass. See:

```text
.omx/plans/capture-gate-mac-native.md
```

The current gate status is passed for the unified ScreenCaptureKit path: the split-recorder smoke remains documented as over-threshold, but `unified-capture-smoke` produced observed system/microphone timestamps and drift below the gate threshold. Live app flows should use the unified provider path, not the older split-recorder path.


## Native Capture Gate

Before enabling app flows that depend on live dual-track capture, update `.omx/plans/capture-gate-mac-native.md` with:

- macOS, Xcode, and Swift versions used for the run.
- Permission behavior for microphone and ScreenCaptureKit/system audio.
- Non-empty system and microphone smoke output paths and sizes.
- Per-track sample rate, channel count, first-sample timestamp, start offset, duration, measured drift, and drift tolerance.
- Fresh `swift test` and `swift build` results from this package.

`NativeMacCaptureProvider.start` still requires explicit `captureGatePassed: true` construction so app flows cannot accidentally bypass the gate; production UI should only use that enabled provider with the unified ScreenCaptureKit path.

## Build And Test

```bash
swift test
swift build
swift run unified-capture-smoke 30
```

SwiftPM writes to the project-local `.build` directory.

## Environment Safety

Do not install or modify global machine dependencies from project scripts. Use local build outputs, local temporary directories, and the project-local `Models/` folder for model experiments.

More detail:

```text
docs/environment-safety.md
```

## Model Files

Large Whisper model files should live under:

```text
Models/
```

Model binaries are ignored by Git.
