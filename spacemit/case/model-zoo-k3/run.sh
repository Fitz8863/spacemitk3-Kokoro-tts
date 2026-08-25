#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=affinity.sh
source "$script_dir/affinity.sh"

usage() {
  cat >&2 <<USAGE
用法:
  $0 <zh|en> <output.wav> <text> [spacemit|cpu] [ep-cores] [repeat] [选项]
  $0 <zh|en> <output.wav> --interactive [spacemit|cpu] [ep-cores] [repeat] [选项]
  $0 <zh|en> --list-voices [--voices-dir DIR]

选项:
  --voice NAME             选择音色，如 af_heart、af_bella、zf_001
  --voices-dir DIR         外部音色目录（目录内放 NAME.bin 或 NAME.npy）
  --voice-path FILE        直接指定一个音色文件，优先级最高
  --provider NAME          spacemit 或 cpu
  --cores LIST             EP 核列表，如 8,10 或 8-15
  --repeat N               重复合成 N 次
  --interactive            进入交互式常驻模式
  --list-voices            列出实际目录中的音色
USAGE
}

if [[ $# -lt 1 ]]; then usage; exit 2; fi
lang="$1"
shift
case "$lang" in
  zh) engine='kokoro:zh'; default_voice='zf_001';;
  en) engine='kokoro:en'; default_voice='af_heart';;
  *) echo "language must be zh or en" >&2; exit 2;;
esac

interactive=false
list_voices=false
provider='spacemit'
out=''
text=''
voice="$default_voice"
voices_dir=''
voice_path=''
cores=''
repeat='1'
positional=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interactive)
      interactive=true; shift;;
    --list-voices)
      list_voices=true; shift;;
    --voice|--speaker)
      [[ $# -ge 2 ]] || { echo "$1 requires a voice name" >&2; exit 2; }
      voice="$2"; shift 2;;
    --voice=*|--speaker=*)
      voice="${1#*=}"; shift;;
    --voices-dir)
      [[ $# -ge 2 ]] || { echo "$1 requires a directory" >&2; exit 2; }
      voices_dir="$2"; shift 2;;
    --voices-dir=*)
      voices_dir="${1#*=}"; shift;;
    --voice-path)
      [[ $# -ge 2 ]] || { echo "$1 requires a file" >&2; exit 2; }
      voice_path="$2"; shift 2;;
    --voice-path=*)
      voice_path="${1#*=}"; shift;;
    --provider)
      [[ $# -ge 2 ]] || { echo "$1 requires spacemit or cpu" >&2; exit 2; }
      provider="$2"; shift 2;;
    --provider=*)
      provider="${1#*=}"; shift;;
    --cores|--ep-cores)
      [[ $# -ge 2 ]] || { echo "$1 requires a core list" >&2; exit 2; }
      cores="$2"; shift 2;;
    --cores=*|--ep-cores=*)
      cores="${1#*=}"; shift;;
    --repeat)
      [[ $# -ge 2 ]] || { echo "$1 requires a positive integer" >&2; exit 2; }
      repeat="$2"; shift 2;;
    --repeat=*)
      repeat="${1#*=}"; shift;;
    --)
      shift
      while [[ $# -gt 0 ]]; do positional+=("$1"); shift; done;;
    -*)
      echo "unknown argument: $1" >&2; usage; exit 2;;
    *)
      positional+=("$1"); shift;;
  esac
done

# Preserve the historical positional contract used by run_a100.sh and by old
# deployment scripts: provider, EP core list and repeat may follow the text.
if [[ ${#positional[@]} -gt 0 && -z "$out" ]]; then
  if [[ "$interactive" == false && "$list_voices" == false ]]; then
    out="${positional[0]}"
    positional=("${positional[@]:1}")
    if [[ ${#positional[@]} -gt 0 ]]; then text="${positional[0]}"; positional=("${positional[@]:1}"); fi
  elif [[ "$interactive" == true ]]; then
    out="${positional[0]}"
    positional=("${positional[@]:1}")
  fi
fi

# The normal command has the output file before text.  The parser above also
# accepts the old call shape because run_a100.sh invokes this script with both
# values as the first positional arguments after the language.
if [[ "$interactive" == false && "$list_voices" == false && -z "$text" && ${#positional[@]} -gt 0 ]]; then
  text="${positional[0]}"
  positional=("${positional[@]:1}")
fi

if [[ ${#positional[@]} -gt 0 ]]; then
  case "${positional[0]}" in
    spacemit|cpu) [[ "$provider" == spacemit ]] && provider="${positional[0]}" || true; positional=("${positional[@]:1}");;
  esac
fi
if [[ ${#positional[@]} -gt 0 && -z "$cores" ]]; then cores="${positional[0]}"; positional=("${positional[@]:1}"); fi
if [[ ${#positional[@]} -gt 0 && "$repeat" == 1 ]]; then repeat="${positional[0]}"; positional=("${positional[@]:1}"); fi
if [[ ${#positional[@]} -gt 0 ]]; then
  echo "too many positional arguments: ${positional[*]}" >&2; usage; exit 2
fi

if ! [[ "$repeat" =~ ^[1-9][0-9]*$ ]]; then
  echo "repeat must be a positive integer" >&2; exit 2
fi
case "$provider" in
  spacemit|cpu) ;;
  *) echo "provider must be spacemit or cpu" >&2; exit 2;;
esac

repo_root=$(cd -- "$script_dir/../../.." && pwd)
tts_root="$repo_root/spacemit/model-zoo-tts"
if [[ -z "$voices_dir" ]]; then voices_dir="$repo_root/voices/$lang"; fi

list_actual_voices() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "音色目录不存在：$dir" >&2
    return 1
  fi
  find "$dir" -maxdepth 1 -type f \( -name '*.bin' -o -name '*.npy' \) -printf '%f\n' \
    | sed -E 's/\.(bin|npy)$//' | sort -u
}
if "$list_voices"; then
  echo "[$lang] 音色目录: $voices_dir"
  list_actual_voices "$voices_dir"
  exit 0
fi
if [[ -z "$out" ]]; then
  echo "missing output.wav" >&2; usage; exit 2
fi
if [[ "$interactive" == false && -z "$text" ]]; then
  echo "missing text (or use --interactive)" >&2; usage; exit 2
fi

# Prefer system-installed SpaceMIT ORT (/usr/local or /usr/lib). Set
# SPACEMIT_ORT_ROOT only when intentionally using an unpacked private bundle.
ort_root="${SPACEMIT_ORT_ROOT:-}"
case_home="$tts_root/.case-home"
model_cache="$case_home/.cache/models/tts/kokoro-tts"
mkdir -p "$model_cache"
if [[ -f "$repo_root/official-model-zoo/v1.0-en/kokoro-v1.0-en.q.onnx" ]]; then
  ln -sfn "$repo_root/official-model-zoo/v1.0-en" "$model_cache/kokoro-v1.0-en"
fi
if [[ -f "$repo_root/official-model-zoo/v1.1-zh/kokoro-v1.1-zh.q.onnx" ]]; then
  ln -sfn "$repo_root/official-model-zoo/v1.1-zh" "$model_cache/kokoro-v1.1-zh"
fi
export HOME="$case_home"
if [[ -n "$ort_root" ]]; then
  export LD_LIBRARY_PATH="$ort_root/lib:/usr/lib/riscv64-linux-gnu:/usr/local/lib:${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH}"
else
  export LD_LIBRARY_PATH="/usr/local/lib:/usr/lib/riscv64-linux-gnu:/usr/lib:${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH}"
fi
export KOKORO_VOICES_DIR="$voices_dir"
if [[ -n "$voice_path" ]]; then export KOKORO_VOICE_PATH="$voice_path"; else unset KOKORO_VOICE_PATH || true; fi
export SPACEMIT_TTS_WARMUP_RUNS="${SPACEMIT_TTS_WARMUP_RUNS:-1}"
if [[ "$provider" == spacemit ]]; then
  if [[ -z "$cores" ]]; then cores="${SPACEMIT_TTS_EP_CORES:-${SPACEMIT_TTS_EP_AFFINITY:-}}"; fi
  if [[ -n "$cores" ]]; then
    ep_affinity=$(normalize_core_list "$cores")
    core_count=$(core_count_from_affinity "$ep_affinity")
    if [[ -n "${SPACEMIT_TTS_EP_THREADS:-}" && "$SPACEMIT_TTS_EP_THREADS" != "$core_count" ]]; then
      echo "SPACEMIT_TTS_EP_THREADS=$SPACEMIT_TTS_EP_THREADS does not match selected core count $core_count" >&2
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
  cat >&2 <<EOF2
错误：找不到可执行文件：$demo
请先在板端编译：
  cmake -S "$tts_root" -B "$tts_root/build-k3"
  cmake --build "$tts_root/build-k3" -j4
系统安装模式不要设置 SPACEMIT_ORT_ROOT；私有 Bundle 才需要显式设置。
EOF2
  exit 127
fi

if "$interactive"; then
  exec "$demo" -l "$engine" --provider "$provider" --voice "$voice" -o "$out"
else
  exec "$demo" -p "$text" -l "$engine" --provider "$provider" --voice "$voice" -o "$out" --repeat "$repeat"
fi
