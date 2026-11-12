#!/usr/bin/env bash
# h-run.sh — launch CPPminer (real Pearl backend) with the args from miner.conf.
set -euo pipefail

DIR="/hive/miners/custom/pearlminer_sm89"
cd "$DIR" || { echo "[h-run] ERROR: $DIR not found" >&2; exit 1; }

# Prefer the bundled libcudart.so (HiveOS may lack a CUDA toolkit install).
export LD_LIBRARY_PATH="$DIR:${LD_LIBRARY_PATH:-}"

BIN="./pearlminer_sm89"
if [[ ! -x "$BIN" ]]; then
  echo "[h-run] ERROR: $BIN missing or not executable" >&2
  ls -la "$DIR" >&2
  exit 1
fi

ARGS="$(cat miner.conf 2>/dev/null || true)"
if [[ -z "$ARGS" ]]; then
  echo "[h-run] WARN: miner.conf empty — using safe defaults (set wallet!)" >&2
  ARGS="--algo pearl --backend cuda --devices 0"
  ARGS+=" --pool stratum+tcp://prl-ae.kryptex.network:7048"
  ARGS+=" --wallet prl1CHANGE_ME --worker rig01 --api-port 4028"
fi

echo "[h-run] launching CPPminer (real Pearl cuPOW backend, sm89)" >&2
exec "$BIN" $ARGS
