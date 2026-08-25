#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 6 ]]; then
  echo "Usage: $0 <zh|en> <output.wav> <text> [spacemit|cpu] [ep-affinity] [repeat]" >&2
  exit 2
fi
lang="$1"
out="$2"
text="$3"
provider="${4:-spacemit}"
ep_affinity="${5:-}"
repeat="${6:-1}"
if ! [[ "$repeat" =~ ^[1-9][0-9]*$ ]]; then
  echo "repeat must be a positive integer" >&2
  exit 2
fi

case "$lang" in
  zh) engine='kokoro:zh'; voice='zf_001';;
  en) engine='kokoro:en'; voice='af_heart';;
  *) echo "language must be zh or en" >&2; exit 2;;
esac
case "$provider" in
  spacemit|cpu) ;;
  *) echo "provider must be spacemit or cpu" >&2; exit 2;;
esac

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../../.." && pwd)
tts_root="$repo_root/spacemit/model-zoo-tts"
ort_root="${SPACEMIT_ORT_ROOT:-/home/spacemit/projects/qwen3-tts/spacemit-ort.riscv64.2.0.6}"
case_home="$tts_root/.case-home"
model_cache="$case_home/.cache/models/tts/kokoro-tts"
mkdir -p "$model_cache"
# Use the checked-in English package directly.  The Chinese ONNX is intentionally
# not stored in GitHub (>100 MB); the backend will download it on first use.
if [[ -f "$repo_root/official-model-zoo/v1.0-en/kokoro-v1.0-en.q.onnx" ]]; then
  ln -sfn "$repo_root/official-model-zoo/v1.0-en" "$model_cache/kokoro-v1.0-en"
fi
if [[ -f "$repo_root/official-model-zoo/v1.1-zh/kokoro-v1.1-zh.q.onnx" ]]; then
  ln -sfn "$repo_root/official-model-zoo/v1.1-zh" "$model_cache/kokoro-v1.1-zh"
fi
export HOME="$case_home"
export LD_LIBRARY_PATH="$ort_root/lib:/usr/lib/riscv64-linux-gnu:${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH}"
export SPACEMIT_TTS_WARMUP_RUNS="${SPACEMIT_TTS_WARMUP_RUNS:-1}"
if [[ "$provider" == spacemit ]]; then
  export SPACEMIT_TTS_EP_THREADS="${SPACEMIT_TTS_EP_THREADS:-4}"
  if [[ -n "$ep_affinity" ]]; then
    export SPACEMIT_TTS_EP_AFFINITY="$ep_affinity"
  fi
fi

if [[ "$provider" == spacemit ]] && command -v spacemit-tcm-smi >/dev/null 2>&1; then
  spacemit-tcm-smi -c >/dev/null 2>&1 || true
fi

exec "$tts_root/build-k3/bin/tts_file_demo" \
  -p "$text" -l "$engine" --provider "$provider" --voice "$voice" -o "$out" --repeat "$repeat"
