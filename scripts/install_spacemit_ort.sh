#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <spacemit-ort-bundle> [prefix]" >&2
  echo "  default prefix: /usr/local" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 2
fi

source_root=$(readlink -f -- "$1")
prefix="${2:-/usr/local}"
if [[ ! -d "$source_root/include" || ! -d "$source_root/lib" ]]; then
  echo "invalid SpaceMIT ORT bundle: expected include/ and lib/: $source_root" >&2
  exit 2
fi

if [[ ! -w "$prefix" && ${EUID:-$(id -u)} -ne 0 ]]; then
  exec sudo "$0" "$source_root" "$prefix"
fi

install -d "$prefix/include" "$prefix/lib"
cp -a "$source_root/include/." "$prefix/include/"

shopt -s nullglob
libraries=("$source_root"/lib/*.so "$source_root"/lib/*.so.*)
if [[ ${#libraries[@]} -eq 0 ]]; then
  echo "no shared libraries found under $source_root/lib" >&2
  exit 2
fi
for library in "${libraries[@]}"; do
  cp -a "$library" "$prefix/lib/"
done

# Make the installation visible to the dynamic loader.  A non-root custom
# prefix remains usable through LD_LIBRARY_PATH; only a root/sudo installation
# writes the global ld.so configuration.
if command -v ldconfig >/dev/null 2>&1; then
  conf=/etc/ld.so.conf.d/spacemit-ort.conf
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    printf '%s\n' "$prefix/lib" > "$conf"
    ldconfig
  elif command -v sudo >/dev/null 2>&1 && [[ ! -w "$conf" ]]; then
    sudo sh -c 'printf "%s\n" "$1" > "$2" && ldconfig' \
      sh "$prefix/lib" "$conf"
  else
    echo "warning: could not update $conf; use LD_LIBRARY_PATH=$prefix/lib" >&2
  fi
fi

printf 'Installed SpaceMIT ORT headers and libraries to %s\n' "$prefix"
printf 'Next configure without SPACEMIT_ORT_ROOT so CMake uses system paths.\n'
