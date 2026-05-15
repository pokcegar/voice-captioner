# Release Checklist: voice-captioner

Use this checklist before claiming a release candidate. Fill in every item and attach log evidence.

## Required Environment and Scope
- [ ] macOS / Xcode / Swift versions captured
- [ ] Capture permissions test path approved (microphone + screen/system)
- [ ] Release branch up to date and clean
- [ ] No model binaries, recordings, transcript artifacts, `.tmp`, or `.build` files staged

## SwiftPM Verification
- [ ] `swift build`
  - Result: `PASS`
  - Evidence:
- [ ] `swift test`
  - Result: `PASS`
  - Evidence:
  - Tests run: 

## Integration Smoke Checks
- [ ] `swift run unified-capture-smoke 30`
  - Result: `PASS`
  - Permission behavior noted: 
  - System/Mic output files exist and non-empty
- [ ] `swift test --filter WhisperProcessTranscriberTests`
  - Result: `PASS`
  - Evidence:
- [ ] `swift test --filter RollingTranscriptionPipelineTests`
  - Result: `PASS`
  - Evidence:
- [ ] `swift test --filter TranscriptTests`
  - Result: `PASS`
  - Evidence:
- [ ] Manual real-model smoke (`whisper.cpp` + local model)
  - Result: `PASS` / `NOT RUN`
  - Model/path used:
  - Note (if N/A):

## Packaged App Readiness
- [ ] Signed app smoke run: record -> stop -> local transcribe -> export -> history reopen -> regeneration
  - Result: `PASS` / `NOT RUN`
  - Evidence notes:
- [ ] Post-release regression spot-checks on timeline/source drift and chunk timing are intact
  - Result:

## Release Integrity
- [ ] Git hygiene check confirms no model binaries or generated media/transcripts are tracked
- [ ] `.tmp` and `.build` remain local and out of release artifacts
- [ ] `.omx` checks updated if plan/test artifacts changed

## Recorded Evidence (sample from latest run)
- `swift test --filter WhisperProcessTranscriberTests --filter RollingTranscriptionPipelineTests --filter TranscriptTests`
  - `PASS (12 tests, 0 failures)`
- `swift test --filter AudioChunkExtractorTests --filter RollingTranscriptionPipelineTests`
  - `PASS (5 tests, 0 failures)`
- `swift run unified-capture-smoke 30`
  - `system_bytes=6029056`
  - `microphone_bytes=3011584`
  - `estimated_drift_seconds=0.052`
  - `drift_tolerance_seconds=0.102`
  - `option_b_passed=true`
