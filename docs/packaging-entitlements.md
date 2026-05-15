# Packaging, Permissions, and Entitlements

VoiceCaptioner is local-first. Packaging must preserve the same boundaries used by the SwiftPM smoke targets: local audio files, local transcripts, local model files, and no hidden network calls.

## Minimum Runtime

- macOS 15 or newer for ScreenCaptureKit microphone output (`SCStreamOutputTypeMicrophone`, `captureMicrophone`).
- Xcode/Swift toolchain capable of building the SwiftPM package with macOS 15 APIs.
- User-granted microphone permission.
- User-granted Screen & System Audio Recording permission for the packaged app.
- User-selected meeting output folder for recordings, chunks, transcripts, exports, and history index updates.
- User-selected local `whisper.cpp` executable and model path, or an explicit user-triggered model download into an approved local model directory.

## Info.plist Usage Descriptions

A packaged `.app` must include user-facing permission strings:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>VoiceCaptioner records your microphone locally as a separate meeting track.</string>
<key>NSScreenCaptureUsageDescription</key>
<string>VoiceCaptioner captures system audio locally as a separate meeting track.</string>
```

macOS may present this as Screen & System Audio Recording depending on OS version. The app must not attempt to bypass TCC; the user must approve the prompt in System Settings.

## Sandbox / Hardened Runtime Notes

Recommended for distribution:

- Enable hardened runtime.
- Enable App Sandbox only after validating ScreenCaptureKit capture and user-selected output folders in a signed build.
- Add audio input entitlement when sandboxed:

```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

- Use user-selected folders or security-scoped bookmarks for meeting output roots outside the app container.
- Use user-selected file access or security-scoped bookmarks for manual model paths and manual `whisper.cpp` executable paths outside the app container.
- Keep all generated audio, chunks, transcript drafts, final exports, and history metadata inside the selected meeting output root unless the user explicitly exports elsewhere.
- Do not require global helpers, virtual audio devices, shell profile edits, package-manager installs, or machine-level configuration changes.

## V1 Packaged App Workflow

The packaged app should document and exercise this exact local workflow:

1. Open VoiceCaptioner.
2. Select or create a local meeting output root.
3. Select a local `whisper.cpp` executable and local model file, or intentionally download a model to a local model directory.
4. Start recording through the unified ScreenCaptureKit provider path.
5. Stop recording; the app writes separated `audio/system.wav` and `audio/microphone.wav` source tracks plus metadata.
6. Start post-stop local transcription over derived chunks. The app may show draft progress while chunks complete, but transcription is local process execution only.
7. Finalize transcript exports as Markdown, SRT, and JSON.
8. Reopen meeting history and verify the meeting can be browsed and exports regenerated from local artifacts.

No cloud transcription, background model download, global service, or hidden network call is allowed in this v1 path.

## Capture Gate Requirement

Only the unified ScreenCaptureKit provider path is accepted for live app recording. The older split-recorder path remains useful as smoke/fallback evidence but failed the drift threshold in repeated 30-second runs.

Before shipping a packaged build, rerun:

```bash
swift build
swift test
swift run unified-capture-smoke 30
```

Then perform a signed-app manual smoke:

1. Launch the app.
2. Select an output folder.
3. Grant microphone and Screen & System Audio Recording permissions if prompted.
4. Start recording.
5. Stop after at least 30 seconds.
6. Verify the meeting folder contains:
   - `audio/system.wav`
   - `audio/microphone.wav`
   - `metadata.json`
   - optional `chunks/chunks.json` after chunk manifest regeneration
7. Confirm metadata records observed timing for both source tracks and drift below the gate threshold.

## Transcription and Export Verification

Use fake-process tests for fast, deterministic package readiness checks:

```bash
swift test --filter WhisperProcessTranscriberTests
swift test --filter RollingTranscriptionPipelineTests
swift test --filter TranscriptTests
```

Use a real local model smoke before release when a local `whisper.cpp` executable and model file are available:

1. Confirm the selected executable and model live in user-approved local paths.
2. Record or provide a short local WAV fixture.
3. Run post-stop transcription through the app path, not a cloud service.
4. Verify generated draft/final transcript segments have sane timestamps.
5. Export Markdown, SRT, and JSON.
6. Reopen history and regenerate exports from the saved meeting folder.

Do not commit model binaries, generated recordings, chunks, transcript outputs, or `.tmp` smoke artifacts.

## Release Checklist

Record PASS/FAIL evidence for every item before a release claim:

- Build: `swift build`.
- Full test suite: `swift test`.
- Unified capture smoke: `swift run unified-capture-smoke 30` with permission behavior noted.
- Fake local Whisper smoke: `swift test --filter WhisperProcessTranscriberTests`.
- Rolling chunk/transcript pipeline smoke: `swift test --filter RollingTranscriptionPipelineTests`.
- Export regression smoke: `swift test --filter TranscriptTests`.
- Manual real-model smoke with local executable and model path.
- Signed packaged-app smoke covering record, stop, local transcribe, export, history reopen, and regeneration.
- Git hygiene check confirming no model binaries, generated audio, transcript exports, `.tmp`, or `.build` artifacts are staged.

A release is not signed-off until the signed packaged-app smoke passes. SwiftPM target success is necessary but not sufficient for packaged release claims.

## Network Boundary

The app must not contact cloud transcription services. Model download, if exposed in UI, must be an explicit user action and must write only to a user-approved local model directory. Manual model selection remains first-class.
