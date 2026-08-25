#!/usr/bin/env bash
set -euo pipefail

base_url='https://archive.spacemit.com/spacemit-ai/model_zoo/tts/kokoro'
cache_dir="${KOKORO_MODEL_CACHE:-${HOME}/.cache/models/tts/kokoro-tts}"
mkdir -p "$cache_dir"

if command -v curl >/dev/null 2>&1; then
  fetch() { curl --fail --location --retry 3 --output "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget --continue --output-document="$2" "$1"; }
else
  echo '需要 curl 或 wget' >&2
  exit 1
fi

for spec in \
  'kokoro-v1.0-en.tar.gz 2ad4fb48bebdd97a0a052fa90513265e' \
  'kokoro-v1.1-zh.tar.gz c3d93d0d6b1b0dffc32db318d2605738'; do
  read -r archive expected_md5 <<<"$spec"
  target="$cache_dir/$archive"
  if [[ ! -f "$target" ]]; then
    echo "下载 $archive"
    fetch "$base_url/$archive" "$target"
  fi
  actual_md5=$(md5sum "$target" | awk '{print $1}')
  if [[ "$actual_md5" != "$expected_md5" ]]; then
    echo "MD5 校验失败: $archive" >&2
    echo "expected=$expected_md5 actual=$actual_md5" >&2
    exit 1
  fi
  echo "MD5 OK: $archive"
  tar -xzf "$target" -C "$cache_dir"
  python3 - "$target" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).unlink(missing_ok=True)
PY
done

echo "模型已准备到: $cache_dir"
