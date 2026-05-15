# Environment Safety

VoiceCaptioner development must not pollute or break the host machine environment.

Rules:
- Use project-local build outputs such as `.build`.
- Use project-local temporary folders such as `.tmp`.
- Use project-local or user-approved app support folders for model downloads.
- Do not install packages globally from scripts.
- Do not edit shell profiles from scripts.
- Do not permanently modify system audio settings from tests.
- Ask for explicit confirmation before any global dependency or machine-level change.

The large Whisper model, when downloaded for local testing, belongs under:

```text
Models/
```

This directory is intentionally ignored by Git.

## Capture Smoke Tests

Native capture smoke tests must stay local and reversible:

- Write recordings under `.tmp/capture-smoke/` or another project-local temporary directory.
- Use OS-managed microphone and ScreenCaptureKit prompts; do not script around macOS privacy controls.
- Do not install audio drivers, virtual devices, package managers, or helper tools globally as part of the capture gate.
- Do not permanently change input/output devices, sample-rate settings, or screen-recording permissions from project scripts.
- Keep generated audio, build output, and model binaries out of Git.
