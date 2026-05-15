# Local Runtime Resources

Place the bundled `whisper-cli` executable here before packaging:

```bash
cp /path/to/whisper.cpp/build/bin/whisper-cli Resources/whisper-cli
chmod +x Resources/whisper-cli
```

`scripts/package-local-app.sh` copies `Resources/whisper-cli` into
`dist/VoiceCaptioner.app/Contents/Resources/whisper-cli` so the app can use it
by default. The UI still keeps a manual executable picker as a fallback.

Large model binaries stay in the project-local `Models/` folder for development
and are not committed. Users can select those `.bin` files from the app.
