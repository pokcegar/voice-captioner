# Capture Gate: Native Mac Dual-Track Audio

Status: **passed via Option B unified ScreenCaptureKit timing path**

This gate blocks broad UI/transcription integration that depends on live dual-track capture. Phase 1/2 capture work may continue inside the native capture slice, but Phases 3/5/6 must not start until this document records a pass decision with fresh verification evidence.

The repository currently contains provider protocols, native microphone enumeration/permission checks, standalone split-recorder smoke paths, a unified ScreenCaptureKit audio/microphone smoke path, metadata fields for per-track timing, and an automated gate assessment. Option A split-recorder evidence failed the drift threshold, but Option B unified ScreenCaptureKit sample-buffer capture passed the 30-second timing gate with observed system and microphone timestamps.

## Gate Questions

- Can VoiceCaptioner capture whole-system output audio and microphone input as separate tracks using native macOS APIs?
- What minimum macOS and Xcode versions are required?
- Which permissions, entitlements, sandbox settings, and hardened runtime settings are required?
- What sample rate, channel count, and timestamp source are produced for each track?
- What is the observed start offset and drift between system and microphone tracks?
- What numeric drift tolerance should transcript merge/export use?
- If native capture fails, can an OBS fallback preserve separated tracks and local-only operation?

## Required Evidence Before Pass

- Supported macOS version.
- Supported Xcode version.
- Permission prompt behavior for microphone and screen/system audio capture.
- Entitlements and Info.plist permission descriptions.
- Non-empty `audio/system.wav` and `audio/microphone.wav` from one start/stop smoke test.
- Metadata containing session clock start, per-track first-sample timestamp, start offset, sample rate, channel count, and duration.
- Measured drift over at least one short test recording.
- Written go/no-go decision.
- Fresh `swift test` and `swift build` output from `voice-captioner/`.

## Current Decision

Go/no-go: **Go for native dual-track capture through the unified ScreenCaptureKit path; no-go for the old split-recorder Option A path.**

Reason: Repeated split-recorder Option A smoke runs produced machine-readable metadata but measured drift above the <= 100 ms threshold. The follow-up Option B unified ScreenCaptureKit sample-buffer path produced non-empty system and microphone WAV files, observed first-sample timestamps for both tracks, 0 s start-offset uncertainty, and drift below the 100 ms threshold. Broad UI/transcription work may now build on the unified provider path, while keeping the old split-recorder path as smoke/fallback evidence only.

## Environment Evidence

- Date: 2026-05-15 Asia/Shanghai.
- macOS: 26.4.1 (Build 25E253).
- Xcode: 26.5 (Build 17F42).
- Swift: 6.3.2 (`swiftlang-6.3.2.1.108 clang-2100.1.1.101`).
- Target: arm64 Apple macOS.
- Package minimum platform: macOS 15 in `Package.swift`.

## Capture Evidence Collected

- Microphone permission: user granted permission before smoke.
- Command: `swift test && swift run microphone-smoke`
- Result: 12 tests passed, then microphone smoke wrote `.tmp/capture-smoke/microphone.wav`.
- Output size: 385024 bytes.
- Screen/system audio permission: user granted ScreenCaptureKit capture permission after macOS prompt and Codex restart.
- Command: `swift run system-audio-smoke`
- Result: system audio smoke wrote `.tmp/capture-smoke/system.wav`.
- Output size: 591616 bytes.
- Command: `swift run dual-capture-smoke`
- Result: dual capture smoke wrote `.tmp/capture-smoke/dual-system.wav` and `.tmp/capture-smoke/dual-microphone.wav`.
- Started at: 2026-05-15T00:59:30Z.
- System output size: 614656 bytes.
- Microphone output size: 579584 bytes.

### 30-Second Option A Timing Smoke

Run 1:

- Date: 2026-05-15T01:59:01Z.
- Command: `swift run dual-capture-smoke 30`.
- Exit: 2, because the smoke completed and produced metadata but Option A failed the pass threshold.
- Metadata: `.tmp/capture-smoke/dual-metadata.json`.
- System output: `.tmp/capture-smoke/dual-system.wav`, 6029056 bytes, 48000 Hz, 2 channels, duration 31.38 s, first sample observed, first sample offset 0.099411964 s.
- Microphone output: `.tmp/capture-smoke/dual-microphone.wav`, 5994496 bytes, 48000 Hz, 1 channel, duration 31.2 s, first sample inferred, start-offset uncertainty 0.25 s.
- Start offset: -0.159147024 s.
- Estimated drift: 0.18 s.
- Numeric drift tolerance recorded by smoke: 0.23 s.
- Option A result: fail, because 0.18 s drift is greater than the required <= 0.10 s threshold.

Run 2:

- Date: 2026-05-15T01:59:48Z.
- Command: `swift run dual-capture-smoke 30`.
- Exit: 2, because the smoke completed and produced metadata but Option A failed the pass threshold.
- Metadata: `.tmp/capture-smoke/dual-metadata.json`.
- System output: `.tmp/capture-smoke/dual-system.wav`, 6029056 bytes, 48000 Hz, 2 channels, duration 31.38 s, first sample observed, first sample offset 0.096593976 s.
- Microphone output: `.tmp/capture-smoke/dual-microphone.wav`, 5998592 bytes, 48000 Hz, 1 channel, duration 31.221333333 s, first sample inferred, start-offset uncertainty 0.25 s.
- Start offset: -0.141470909 s.
- Estimated drift: 0.158666667 s.
- Numeric drift tolerance recorded by smoke: 0.208666667 s.
- Option A result: fail, because 0.158666667 s drift is greater than the required <= 0.10 s threshold.

Merge policy decision from the smoke assessment: transcript merge uses per-track timestamp offsets; derived mixed audio may use silence padding when needed and must never replace separated source tracks.

### 30-Second Option B Unified ScreenCaptureKit Timing Smoke

Run 1:

- Date: 2026-05-15T02:05:59Z.
- Command: `swift run unified-capture-smoke 30`.
- Exit: 0.
- Metadata: `.tmp/capture-smoke/unified-metadata.json`.
- System output: `.tmp/capture-smoke/unified-system.wav`, 6029056 bytes, 48000 Hz, 2 channels, duration 31.38 s, first sample observed, first sample offset 0.106163025 s.
- Microphone output: `.tmp/capture-smoke/unified-microphone.wav`, 3007488 bytes, 48000 Hz, 1 channel, duration 31.285333333 s, first sample observed, first sample offset 0.204558015 s.
- Start offset: -0.098394990 s.
- Start-offset uncertainty: 0 s.
- Estimated drift: 0.094666667 s.
- Numeric drift tolerance recorded by smoke: 0.144666667 s.
- Option B result: pass, because observed microphone timing eliminates inferred-start uncertainty and drift is <= 0.10 s.

Run 2:

- Date: 2026-05-15T02:09:01Z.
- Command: `swift run unified-capture-smoke 30`.
- Exit: 0.
- Metadata: `.tmp/capture-smoke/unified-metadata.json`.
- System output: `.tmp/capture-smoke/unified-system.wav`, 6029056 bytes, 48000 Hz, 2 channels, duration 31.38 s, first sample observed, first sample offset 0.103517056 s.
- Microphone output: `.tmp/capture-smoke/unified-microphone.wav`, 3010560 bytes, 48000 Hz, 1 channel, duration 31.317333333 s, first sample observed, first sample offset 0.163922071 s.
- Start offset: -0.060405016 s.
- Start-offset uncertainty: 0 s.
- Estimated drift: 0.062666667 s.
- Numeric drift tolerance recorded by smoke: 0.112666667 s.
- Option B result: pass, because observed microphone timing eliminates inferred-start uncertainty and drift is <= 0.10 s.

Provider decision: default `NativeMacCaptureProvider` now uses the unified ScreenCaptureKit recorder bridge for system and microphone capture, while still requiring the explicit `captureGatePassed: true` construction gate before start can be used by app flows.

## Verification Evidence

Baseline before concurrent source-scope edits:

- Command: `swift test`
- Result: PASS on 2026-05-15T01:33Z; 12 tests in 5 suites passed.
- Command: `swift build`
- Result: PASS on 2026-05-15T01:33Z; debug build completed.

Current final verification after shared source-scope fixes:

- Command: `swift test`
- Result: PASS on 2026-05-15T01:38Z; 19 tests in 7 suites passed.
- Command: `swift build`
- Result: PASS on 2026-05-15T01:38Z; debug build completed.

Current Option A/Option B assessment verification:

- Command: `swift build`
- Result: PASS on 2026-05-15T02:08Z.
- Command: `swift test`
- Result: PASS on 2026-05-15T02:08Z; 22 tests in 8 suites passed.
- Command: `swift run dual-capture-smoke 30`
- Result: completed twice and produced dual WAV files plus metadata, but exited 2 because Option A drift threshold failed.
- Command: `swift run unified-capture-smoke 30`
- Result: completed twice and produced dual WAV files plus metadata; latest run exited 0 with drift 0.062666667 s and start-offset uncertainty 0 s.

## Local-Only Constraints

- Use SwiftPM project-local `.build` outputs.
- Use project-local `.tmp/` for smoke recordings and temporary test files.
- Use project-local `Models/` for large Whisper model experiments.
- Do not install global dependencies, modify shell profiles, or permanently change system audio settings from project scripts.
- Prompted macOS permissions are acceptable only as user-controlled OS prompts; scripts must not attempt to bypass or persistently reconfigure them.

## Remaining Gate Work

- Keep app flows on the unified ScreenCaptureKit provider path; do not revive the split-recorder path for broad UI/transcription integration unless a future gate rerun proves it below threshold.
- Add app-level entitlements/Info.plist packaging documentation before distributing outside SwiftPM smoke mode.
- Re-run `swift test`, `swift build`, and `swift run unified-capture-smoke 30` after any provider, writer, or timestamp-policy change.
- Keep the merge policy as timestamp offsets for transcript merge; use silence padding only for derived mixed audio if needed.
