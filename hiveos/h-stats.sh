#!/usr/bin/env bash
# h-stats.sh — read CPPminer's HiveOS stats endpoint and export $khs + $stats.
# CPPminer's --api-port serves GET /hiveos -> {"khs": <number>, "stats": {...}}.
# Sourced by the HiveOS agent; must NOT echo to stdout.
khs=0
stats="null"

API_PORT="${CUSTOM_API_PORT:-4028}"
resp="$(curl -s --max-time 3 "http://127.0.0.1:${API_PORT}/hiveos" 2>/dev/null || true)"

if [[ -n "$resp" && "$resp" != *'"404'* && "$resp" != *"Not Found"* ]]; then
  if command -v jq >/dev/null 2>&1; then
    khs="$(printf '%s' "$resp" | jq -r '.khs // 0' 2>/dev/null || echo 0)"
    s="$(printf '%s' "$resp" | jq -c '.stats // empty' 2>/dev/null || true)"
    [[ -n "$s" ]] && stats="$s"
  else
    # No jq: pass the whole payload as stats; try to grab khs with grep.
    stats="$resp"
    k="$(printf '%s' "$resp" | grep -oE '"khs"[[:space:]]*:[[:space:]]*[0-9.]+' | grep -oE '[0-9.]+$' || true)"
    [[ -n "$k" ]] && khs="$k"
  fi
fi
