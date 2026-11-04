#!/usr/bin/env bash
# Check DNS and plain TCP reachability for a Stratum endpoint from HiveOS/Linux.
# Usage: ./pool-check.sh host:port [host:port ...]
set -u

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 host:port [host:port ...]" >&2
  echo "Example: $0 prl-ae.kryptex.network:7048" >&2
  exit 2
fi

failed=0
for endpoint in "$@"; do
  # Accept host:port only; TLS/Stratum protocol is not tested by this script.
  if [[ "$endpoint" != *:* ]]; then
    echo "[ERROR] $endpoint: expected host:port" >&2
    failed=1
    continue
  fi
  host=${endpoint%:*}
  port=${endpoint##*:}
  if [[ -z "$host" || ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
    echo "[ERROR] $endpoint: invalid host or port" >&2
    failed=1
    continue
  fi

  echo "== $host:$port =="
  if ! command -v getent >/dev/null 2>&1; then
    echo "[ERROR] getent is not installed; cannot perform the DNS check."
    failed=1
    continue
  fi
  if ! getent ahosts "$host"; then
    echo "[FAIL] DNS lookup failed for $host"
    failed=1
    continue
  fi
  echo "[OK] DNS lookup succeeded"

  if command -v nc >/dev/null 2>&1; then
    if nc -z -w 5 "$host" "$port" >/dev/null 2>&1; then
      echo "[OK] TCP connection succeeded"
    else
      echo "[FAIL] TCP connection to $host:$port failed (timeout, firewall, wrong port, or pool unavailable)"
      failed=1
    fi
  elif command -v timeout >/dev/null 2>&1; then
    # Pass values as positional parameters; do not interpolate endpoint text as shell code.
    if timeout 5 bash -c 'exec 3<>/dev/tcp/$1/$2' _ "$host" "$port" 2>/dev/null; then
      echo "[OK] TCP connection succeeded"
    else
      echo "[FAIL] TCP connection to $host:$port failed (timeout, firewall, wrong port, or pool unavailable)"
      failed=1
    fi
  else
    echo "[ERROR] Neither nc nor timeout is installed; cannot test TCP reachability."
    failed=1
  fi
  echo "Note: TCP success confirms only that the port accepts connections; it does not verify Stratum login, jobs, TLS, or accepted shares."
done

exit "$failed"
