#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tts_root="$repo_root/spacemit/model-zoo-tts"
deps_root="$tts_root/.local-deps"
package_dir="$deps_root/packages"
mkdir -p "$package_dir"

packages=(libfftw3-dev libcurl4-openssl-dev libespeak-ng-dev libsndfile1-dev)
cd "$package_dir"
for package in "${packages[@]}"; do
  echo "下载 $package"
  apt download "$package"
done

for package_file in ./*.deb; do
  echo "解压 $package_file"
  dpkg-deb -x "$package_file" "$deps_root"
done

echo "本地依赖已准备到: $deps_root"
