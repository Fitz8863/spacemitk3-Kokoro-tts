#!/usr/bin/env bash
# Helpers for converting a user-facing core list into the semicolon-separated
# format accepted by SpaceMIT EP.

normalize_core_list() {
  local raw="$1"
  local token start end core
  local -a tokens expanded
  local -A seen=()

  # Comma, semicolon, colon and whitespace are accepted as separators.  Ranges
  # such as 8-15 are expanded so the command line stays readable.
  raw="${raw//,/ }"
  raw="${raw//;/ }"
  raw="${raw//:/ }"
  read -r -a tokens <<< "$raw"
  if [[ ${#tokens[@]} -eq 0 ]]; then
    echo "core list must not be empty" >&2
    return 2
  fi

  for token in "${tokens[@]}"; do
    if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start=$((10#${BASH_REMATCH[1]}))
      end=$((10#${BASH_REMATCH[2]}))
      if (( start > end )); then
        echo "invalid core range: $token" >&2
        return 2
      fi
      for ((core = start; core <= end; core++)); do
        if [[ -n "${seen[$core]+x}" ]]; then
          echo "duplicate core in list: $core" >&2
          return 2
        fi
        seen[$core]=1
        expanded+=("$core")
      done
    elif [[ "$token" =~ ^[0-9]+$ ]]; then
      core=$((10#$token))
      if [[ -n "${seen[$core]+x}" ]]; then
        echo "duplicate core in list: $core" >&2
        return 2
      fi
      seen[$core]=1
      expanded+=("$core")
    else
      echo "invalid core list item: $token (use e.g. 8,10,12 or 8-15)" >&2
      return 2
    fi
  done

  local joined=""
  for core in "${expanded[@]}"; do
    if [[ -n "$joined" ]]; then
      joined+=';'
    fi
    joined+="$core"
  done
  printf '%s' "$joined"
}

core_count_from_affinity() {
  local affinity="$1"
  local -a cores
  IFS=';' read -r -a cores <<< "$affinity"
  printf '%s' "${#cores[@]}"
}
