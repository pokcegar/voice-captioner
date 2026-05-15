# Capture Gate: Native Mac Dual-Track Audio

Status: **partially passed**

This gate blocks broad UI/transcription integration that depends on live dual-track capture. Phase 1/2 capture work may continue inside the native capture slice, but Phases 3/5/6 must not start until this document records a pass decision with fresh verification evidence.

The repository currently contains provider protocols, native microphone enumeration/permission checks, standalone microphone/system recording smoke paths, a dual-capture smoke path, and metadata fields for per-track timing. `NativeMacCaptureProvider.start` still intentionally throws `feasibilityGateNotPassed` until the cross-phase gate has complete timing/drift evidence and the provider coordinator is wired end-to-end.

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

Go/no-go: **No-go for broad UI/transcription integration that depends on full native dual-track capture.**

Reason: Microphone recording, standalone whole-system audio recording, same-command dual capture, and the Swift package test/build baseline are proven on this machine. The gate is not complete until shared timing metadata is emitted from live capture, start offset/drift are measured from the same session, a numeric drift tolerance is recorded, and `NativeMacCaptureProvider.start` no longer throws the feasibility-gate error.

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

## Verification Evidence

Baseline before concurrent source-scope edits:

- Command: `swift test`
- Result: PASS on 2026-05-15T01:33Z; 12 tests in 5 suites passed.
- Command: `swift build`
- Result: PASS on 2026-05-15T01:33Z; debug build completed.

Current final verification after concurrent source-scope edits:

- Command: `swift test`
- Result: FAIL on 2026-05-15T01:34Z during compile. Blocking errors are outside this docs/gate slice: `CaptureHandle` is used as a dictionary key without `Hashable`, `SystemAudioRecorder.stopWithMetadata()` has a circular `timingSnapshot` reference, and `CaptureSessionCoordinator` references missing `SystemAudioRecorder.firstSampleTime`.
- Command: `swift build`
- Result: FAIL on 2026-05-15T01:34Z with the same compile errors.

## Local-Only Constraints

- Use SwiftPM project-local `.build` outputs.
- Use project-local `.tmp/` for smoke recordings and temporary test files.
- Use project-local `Models/` for large Whisper model experiments.
- Do not install global dependencies, modify shell profiles, or permanently change system audio settings from project scripts.
- Prompted macOS permissions are acceptable only as user-controlled OS prompts; scripts must not attempt to bypass or persistently reconfigure them.

## Remaining Gate Work

- Record per-track sample rate, channel count, first-sample timestamp, start offset, and duration from the actual capture session metadata.
- Measure start offset and drift from at least one same-session dual-track recording.
- Define numeric drift tolerance for transcript merge/export.
- Decide whether transcript merge uses timestamp offsets or silence padding.
- Wire the native provider/coordinator only after metadata and drift evidence is available.
- Re-run and record `swift test` and `swift build` after the provider/coordinator slice lands.
