#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=affinity.sh
source "$script_dir/affinity.sh"

usage() {
  cat >&2 <<USAGE
用法:
  $0 <zh|en> <output.wav> <text> [repeat] [选项]
  $0 <zh|en> <output.wav> --interactive [选项]
  $0 <zh|en> --list-voices [--voices-dir DIR]

选项:
  --voice NAME             选择音色，如 af_bella、am_echo、zf_002
  --voices-dir DIR         外部音色目录
  --voice-path FILE        直接指定音色文件
  --cores LIST             选择 A100 核，如 8,10 或 8-15（默认 8-15）
  --repeat N               重复合成 N 次
  --interactive            交互式常驻输入
  --list-voices            列出实际可用音色
USAGE
}

[[ $# -ge 1 ]] || { usage; exit 2; }
lang="$1"
shift
case "$lang" in
  zh|en) ;;
  *) echo "language must be zh or en" >&2; exit 2;;
esac

list_voices=false
interactive=false
out=''
text=''
voice=''
voices_dir=''
voice_path=''
repeat='1'
cores="${SPACEMIT_TTS_EP_CORES:-${SPACEMIT_TTS_EP_AFFINITY:-8-15}}"
positional=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list-voices)
      list_voices=true; shift;;
    --interactive)
      interactive=true; shift;;
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

if "$list_voices"; then
  [[ ${#positional[@]} -eq 0 ]] || { echo "--list-voices does not take positional arguments" >&2; exit 2; }
  args=("$lang" --list-voices)
  [[ -n "$voices_dir" ]] && args+=(--voices-dir "$voices_dir")
  exec "$script_dir/run.sh" "${args[@]}"
fi

if [[ ${#positional[@]} -gt 0 ]]; then
  out="${positional[0]}"
  positional=("${positional[@]:1}")
fi
if "$interactive"; then
  [[ ${#positional[@]} -eq 0 ]] || { echo "interactive mode does not take text" >&2; usage; exit 2; }
else
  [[ ${#positional[@]} -gt 0 ]] || { echo "missing text (or use --interactive)" >&2; usage; exit 2; }
  text="${positional[0]}"
  positional=("${positional[@]:1}")
  if [[ ${#positional[@]} -gt 0 && "$repeat" == 1 && "${positional[0]}" =~ ^[1-9][0-9]*$ ]]; then
    repeat="${positional[0]}"
    positional=("${positional[@]:1}")
  fi
fi
[[ ${#positional[@]} -eq 0 ]] || { echo "too many positional arguments: ${positional[*]}" >&2; usage; exit 2; }
[[ -n "$out" ]] || { echo "missing output.wav" >&2; usage; exit 2; }
[[ "$repeat" =~ ^[1-9][0-9]*$ ]] || { echo "repeat must be a positive integer" >&2; exit 2; }

# K3 topology: 0-7=X100, 8-15=A100.  Only EP workers are pinned.
ep_affinity=$(normalize_core_list "$cores")
core_count=$(core_count_from_affinity "$ep_affinity")
if [[ -n "${SPACEMIT_TTS_EP_THREADS:-}" && "$SPACEMIT_TTS_EP_THREADS" != "$core_count" ]]; then
  echo "SPACEMIT_TTS_EP_THREADS=$SPACEMIT_TTS_EP_THREADS does not match selected core count $core_count" >&2
  exit 2
fi
export SPACEMIT_TTS_EP_THREADS="$core_count"
export SPACEMIT_TTS_EP_CORES="$cores"
export SPACEMIT_TTS_EP_AFFINITY="$ep_affinity"
export SPACEMIT_TTS_WARMUP_RUNS="${SPACEMIT_TTS_WARMUP_RUNS:-1}"

args=("$lang" "$out")
if "$interactive"; then
  args+=(--interactive)
else
  args+=("$text")
fi
args+=(--provider spacemit --cores "$ep_affinity" --repeat "$repeat")
[[ -n "$voice" ]] && args+=(--voice "$voice")
[[ -n "$voices_dir" ]] && args+=(--voices-dir "$voices_dir")
[[ -n "$voice_path" ]] && args+=(--voice-path "$voice_path")
exec "$script_dir/run.sh" "${args[@]}"
