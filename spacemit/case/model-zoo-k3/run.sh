#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=affinity.sh
source "$script_dir/affinity.sh"

interactive=false
if [[ $# -ge 3 && "$3" == "--interactive" ]]; then
  interactive=true
  lang="$1"
  out="$2"
  shift 3
  provider="${1:-spacemit}"
  ep_cores="${2:-}"
  repeat="${3:-1}"
  if [[ $# -gt 3 ]]; then
    echo "too many arguments for interactive mode" >&2
    echo "Usage: $0 <zh|en> <output.wav> --interactive [spacemit|cpu] [ep-cores]" >&2
    exit 2
  fi
else
  if [[ $# -lt 3 || $# -gt 6 ]]; then
    echo "Usage: $0 <zh|en> <output.wav> <text> [spacemit|cpu] [ep-cores] [repeat]" >&2
    echo "  interactive: $0 <zh|en> <output.wav> --interactive [spacemit|cpu] [ep-cores]" >&2
    echo "  ep-cores: comma/range list, e.g. 8,10,12 or 8-15" >&2
    exit 2
  fi
  lang="$1"
  out="$2"
  text="$3"
  provider="${4:-spacemit}"
  ep_cores="${5:-}"
  repeat="${6:-1}"
fi

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
  if [[ -z "$ep_cores" ]]; then
    ep_cores="${SPACEMIT_TTS_EP_CORES:-${SPACEMIT_TTS_EP_AFFINITY:-}}"
  fi
  if [[ -n "$ep_cores" ]]; then
    ep_affinity=$(normalize_core_list "$ep_cores")
    core_count=$(core_count_from_affinity "$ep_affinity")
    if [[ -n "${SPACEMIT_TTS_EP_THREADS:-}" && "$SPACEMIT_TTS_EP_THREADS" != "$core_count" ]]; then
      echo "SPACEMIT_TTS_EP_THREADS=$SPACEMIT_TTS_EP_THREADS does not match the selected core count $core_count" >&2
      exit 2
    fi
    export SPACEMIT_TTS_EP_THREADS="$core_count"
    export SPACEMIT_TTS_EP_AFFINITY="$ep_affinity"
  else
    export SPACEMIT_TTS_EP_THREADS="${SPACEMIT_TTS_EP_THREADS:-4}"
  fi
fi

if [[ "$provider" == spacemit ]] && command -v spacemit-tcm-smi >/dev/null 2>&1; then
  spacemit-tcm-smi -c >/dev/null 2>&1 || true
fi

demo="$tts_root/build-k3/bin/tts_file_demo"
if [[ ! -x "$demo" ]]; then
  cat >&2 <<EOF
错误：找不到可执行文件：$demo
请先在板端编译 TTS demo：
  cmake -S "$tts_root" -B "$tts_root/build-k3" \
    -DONNXRUNTIME_INCLUDE_DIR="$ort_root/include" \
    -DONNXRUNTIME_LIB="$ort_root/lib/libonnxruntime.so"
  cmake --build "$tts_root/build-k3" -j4
EOF
  exit 127
fi

if "$interactive"; then
  exec "$demo" \
    -l "$engine" --provider "$provider" --voice "$voice" -o "$out"
else
  exec "$demo" \
    -p "$text" -l "$engine" --provider "$provider" --voice "$voice" -o "$out" --repeat "$repeat"
fi
