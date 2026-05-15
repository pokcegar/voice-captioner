# Packaging, Permissions, and Entitlements

VoiceCaptioner is local-first. Packaging must preserve the same boundaries used by the SwiftPM smoke targets: local audio files, local transcripts, local model files, and no hidden network calls.

## Minimum Runtime

- macOS 15 or newer for ScreenCaptureKit microphone output (`SCStreamOutputTypeMicrophone`, `captureMicrophone`).
- Xcode/Swift toolchain capable of building the SwiftPM package with macOS 15 APIs.
- User-granted microphone permission.
- User-granted Screen & System Audio Recording permission for the packaged app.

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
- Do not require global helpers, virtual audio devices, shell profile edits, or package-manager installs.

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

## Network Boundary

The app must not contact cloud transcription services. Model download, if exposed in UI, must be an explicit user action and must write only to a user-approved local model directory. Manual model selection remains first-class.
