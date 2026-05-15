#!/usr/bin/env bash
set -euo pipefail

MODEL="${1:-small}"
MIRROR="${VOICE_CAPTIONER_MODEL_MIRROR:-official}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS_DIR="${ROOT_DIR}/Models"

case "${MODEL}" in
  tiny|base|small|medium|large-v3|large-v3-turbo) ;;
  *)
    echo "unsupported model: ${MODEL}" >&2
    echo "supported: tiny base small medium large-v3 large-v3-turbo" >&2
    exit 64
    ;;
esac

case "${MIRROR}" in
  official)
    BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
    ;;
  hf-mirror)
    BASE_URL="https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main"
    ;;
  http://*|https://*)
    BASE_URL="${MIRROR%/}"
    ;;
  *)
    echo "unsupported mirror: ${MIRROR}" >&2
    echo "use official, hf-mirror, or a base URL" >&2
    exit 64
    ;;
esac

mkdir -p "${MODELS_DIR}"

FILENAME="ggml-${MODEL}.bin"
URL="${BASE_URL}/${FILENAME}"
DEST="${MODELS_DIR}/${FILENAME}"
MANIFEST="${MODELS_DIR}/ggml-${MODEL}.manifest.json"

echo "downloading ${URL}"
echo "to ${DEST}"

curl \
  --location \
  --fail \
  --continue-at - \
  --retry 5 \
  --retry-delay 3 \
  --connect-timeout 30 \
  --output "${DEST}" \
  "${URL}"

SIZE="$(stat -f '%z' "${DEST}")"
SHA256="$(shasum -a 256 "${DEST}" | awk '{print $1}')"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "${MANIFEST}" <<JSON
{
  "filename": "${FILENAME}",
  "path": "${DEST}",
  "source_url": "${URL}",
  "mirror": "${MIRROR}",
  "size_bytes": ${SIZE},
  "sha256": "${SHA256}",
  "status": "downloaded_unverified",
  "created_at_utc": "${CREATED_AT}"
}
JSON

echo "wrote ${MANIFEST}"
