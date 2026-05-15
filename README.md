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

## V1 Local Workflow

The supported v1 product path is local-only and post-stop transcription oriented:

1. Choose a meeting output root on disk.
2. Choose a local `whisper.cpp` executable and a local model file from `Models/` or a user-selected path.
3. Record with the unified ScreenCaptureKit capture path so system audio and microphone audio are written as separated source tracks.
4. Stop recording before transcription starts.
5. Generate chunk manifests from the recorded sources, run local Whisper transcription over derived chunks, and keep rolling draft artifacts under the meeting folder.
6. Finalize transcript exports as Markdown, SRT, and JSON.
7. Browse folder-indexed meeting history and regenerate transcript/export artifacts from local meeting data.

No cloud transcription, hidden network service, global helper, virtual audio driver, or shell-profile modification is part of v1.

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

## Local App Bundle

For double-click local use, build or copy `whisper.cpp`'s `whisper-cli` into `Resources/whisper-cli`, then package:

```bash
cp /path/to/whisper-cli Resources/whisper-cli
chmod +x Resources/whisper-cli
scripts/package-local-app.sh
open dist/VoiceCaptioner.app
```

The app prefers the bundled `Contents/Resources/whisper-cli` automatically. The settings UI still keeps **Choose…** as a manual fallback if you want to override the executable. Downloaded model binaries remain local in `Models/` and are selected by the app/model picker; they are intentionally ignored by Git.

SwiftPM writes to the project-local `.build` directory.

For release integration, also capture smoke evidence for the local transcription path:

```bash
swift test --filter WhisperProcessTranscriberTests
swift test --filter RollingTranscriptionPipelineTests
swift test --filter TranscriptTests
```

`WhisperProcessTranscriberTests` uses fake local binaries/fixtures and is the fast regression check for the post-stop transcription adapter. Real-model smoke remains manual because it requires a user-selected local `whisper.cpp` binary and model file.

## Release Checklist

Before a release claim, record PASS/FAIL evidence for:

- `swift build` from `voice-captioner/`.
- `swift test` from `voice-captioner/`.
- `swift run unified-capture-smoke 30` with microphone and Screen & System Audio Recording permission granted.
- Fake local Whisper smoke via `swift test --filter WhisperProcessTranscriberTests`.
- Chunk/pipeline/export regressions via `swift test --filter RollingTranscriptionPipelineTests` and `swift test --filter TranscriptTests`.
- Manual real-model smoke using a local `whisper.cpp` executable and local model file; do not download models implicitly during the smoke.
- Manual packaged-app smoke from a signed build: select output folder, grant permissions, record, stop, transcribe locally, export Markdown/SRT/JSON, reopen history, and verify generated artifacts remain inside the selected local folders.

Do not claim a signed packaged release until the signed-app smoke has been performed on the packaged app, not only SwiftPM targets.

## Environment Safety

Do not install or modify global machine dependencies from project scripts. Use local build outputs, local temporary directories, and the project-local `Models/` folder for model experiments.

More detail:

```text
docs/environment-safety.md
docs/packaging-entitlements.md
docs/model-strategy.md
```

## Model Files

Large Whisper model files should live under:

```text
Models/
```

Model binaries are ignored by Git.
