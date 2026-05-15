# Whisper Model Strategy

VoiceCaptioner should not download every Whisper model by default.

Recommended model tiers:

- `tiny`: test/smoke only. Fast, low quality.
- `base`: quick preview and low-resource fallback.
- `small`: default v1 recommendation. Practical quality/speed balance.
- `medium`: quality mode for better transcripts when latency is acceptable.
- `large-v3-turbo`: optional high-quality/fast large-family model if disk and compute allow.
- `large-v3`: optional maximum quality. Do not require it for v1 because it is large and slow to download.

Not recommended as default downloads:

- `.en` variants unless the UI explicitly adds English-only optimization.
- all quantized variants up front. Add them later as an advanced model picker.

Download command:

```bash
scripts/download-whisper-model.sh small
```

Use a China-friendly mirror when reachable:

```bash
VOICE_CAPTIONER_MODEL_MIRROR=hf-mirror scripts/download-whisper-model.sh small
```

The script writes only under `Models/` and does not install global dependencies.

## Local-Only Model Policy

- Transcription must run through a user-configured local executable and local model path.
- The app may offer an explicit model download action, but it must never download a model during record, stop, export, or history browsing without a direct user action.
- Manual model selection is first-class for offline users and for users who keep models outside the repository.
- Model binaries (`*.bin`, `*.gguf`, partial downloads, and temporary downloads) must stay out of Git. Commit only small manifest/metadata files.
- Release smoke evidence should name the model tier/path used, but should not require committing the model binary.

Current local note:

- `Models/ggml-large-v3.bin` is incomplete/invalid unless its manifest says otherwise.
