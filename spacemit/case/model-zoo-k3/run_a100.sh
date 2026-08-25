#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage: $0 <zh|en> <output.wav> <text> [repeat]" >&2
  exit 2
fi

# K3 topology on the target board: CPU 0-7 = X100, CPU 8-15 = A100.
# The SpaceMIT EP binds its worker threads directly, so the SSH user's
# inherited cpuset (normally 0-7) does not need to be widened.
export SPACEMIT_TTS_EP_THREADS="${SPACEMIT_TTS_EP_THREADS:-8}"
export SPACEMIT_TTS_EP_AFFINITY="${SPACEMIT_TTS_EP_AFFINITY:-8;9;10;11;12;13;14;15}"
# Warm up once during engine initialization; the first user request then uses
# the same already-compiled EP shapes as subsequent requests.
export SPACEMIT_TTS_WARMUP_RUNS="${SPACEMIT_TTS_WARMUP_RUNS:-1}"
repeat="${4:-1}"
if ! [[ "$repeat" =~ ^[1-9][0-9]*$ ]]; then
  echo "repeat must be a positive integer" >&2
  exit 2
fi

exec "$(dirname "$0")/run.sh" "$1" "$2" "$3" spacemit "$SPACEMIT_TTS_EP_AFFINITY" "$repeat"
