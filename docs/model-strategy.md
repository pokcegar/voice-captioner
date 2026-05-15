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

Current local note:

- `Models/ggml-large-v3.bin` is incomplete/invalid unless its manifest says otherwise.
