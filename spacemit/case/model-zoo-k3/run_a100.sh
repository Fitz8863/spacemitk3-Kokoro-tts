#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=affinity.sh
source "$script_dir/affinity.sh"

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <zh|en> <output.wav> <text> [repeat] [--cores CORE_LIST]" >&2
  echo "  CORE_LIST: comma/range list, e.g. 8,10,12 or 8-15" >&2
  exit 2
fi

lang="$1"
out="$2"
text="$3"
shift 3
repeat=1
cores="${SPACEMIT_TTS_EP_CORES:-${SPACEMIT_TTS_EP_AFFINITY:-8-15}}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cores|--ep-cores)
      if [[ $# -lt 2 ]]; then
        echo "$1 requires a core list" >&2
        exit 2
      fi
      cores="$2"
      shift 2
      ;;
    --cores=*|--ep-cores=*)
      cores="${1#*=}"
      shift
      ;;
    '' )
      echo "unexpected empty argument" >&2
      exit 2
      ;;
    *)
      if [[ "$1" =~ ^[1-9][0-9]*$ && "$repeat" == 1 ]]; then
        repeat="$1"
        shift
      else
        echo "unknown argument: $1" >&2
        exit 2
      fi
      ;;
  esac
done

# K3 topology: CPU 0-7 = X100, CPU 8-15 = A100.  The selected list is passed
# to the EP worker pool; the application process itself need not be moved.
ep_affinity=$(normalize_core_list "$cores")
core_count=$(core_count_from_affinity "$ep_affinity")
if [[ -n "${SPACEMIT_TTS_EP_THREADS:-}" && "$SPACEMIT_TTS_EP_THREADS" != "$core_count" ]]; then
  echo "SPACEMIT_TTS_EP_THREADS=$SPACEMIT_TTS_EP_THREADS does not match the selected core count $core_count" >&2
  exit 2
fi
export SPACEMIT_TTS_EP_THREADS="$core_count"
export SPACEMIT_TTS_EP_CORES="$cores"
export SPACEMIT_TTS_EP_AFFINITY="$ep_affinity"
# Warm up once during engine initialization; the first user request then uses
# the same already-compiled EP shapes as subsequent requests.
export SPACEMIT_TTS_WARMUP_RUNS="${SPACEMIT_TTS_WARMUP_RUNS:-1}"

exec "$script_dir/run.sh" "$lang" "$out" "$text" spacemit "$ep_affinity" "$repeat"
