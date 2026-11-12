#!/usr/bin/env bash
# h-config.sh — translate HiveOS flight-sheet env into CPPminer CLI args.
#
# Backend = CPPminer (real Pearl cuPOW: CUTLASS GEMM+XOR+jackpot, blake3 Merkle
# proof, plain_proof = base64(bincode proof) + gzip for type:"v2" pools).
#
# HiveOS sets: CUSTOM_URL (host:port), CUSTOM_TEMPLATE (wallet[.worker]),
# CUSTOM_USER_CONFIG (extra args), CUSTOM_PASS (pool password).
set -euo pipefail

CONF_FILE="/hive/miners/custom/pearlminer_sm89/miner.conf"
mkdir -p "$(dirname "$CONF_FILE")"

# Split "wallet.worker" (HiveOS template = %WAL%.%WORKER_NAME%). PRL addresses
# are bech32-like (prl1...) and contain no dot, so the first dot is the separator.
TEMPLATE="${CUSTOM_TEMPLATE:-}"
WALLET="${TEMPLATE%%.*}"
WORKER="${TEMPLATE#*.}"
if [[ -z "$WORKER" || "$WORKER" == "$TEMPLATE" ]]; then
  WORKER="${CUSTOM_WORKER_NAME:-${WORKER_NAME:-${HOSTNAME:-rig01}}}"
fi
[[ -z "$WALLET" ]] && { echo "[h-config] ERROR: no wallet in CUSTOM_TEMPLATE" >&2; exit 1; }

# CPPminer wants stratum+tcp://host:port
POOL="${CUSTOM_URL:-prl-ae.kryptex.network:7048}"
case "$POOL" in
  stratum+tcp://*|stratum2+tcp://*|stratum+ssl://*) ;;
  *) POOL="stratum+tcp://${POOL}" ;;
esac

# Pool password: Kryptex reads a custom share difficulty from it
# (--pool-pass d=2097152 is their default). HiveOS "pass" field -> CUSTOM_PASS.
POOL_PASS="${CUSTOM_PASS:-d=2097152}"

# Stats API port for h-stats.sh (CPPminer --api-port serves /hiveos).
API_PORT="${CUSTOM_API_PORT:-4028}"

# GPU index. HiveOS does not expose a per-card index for custom miners; default 0.
# Override with `--devices N` in Extra config (CUSTOM_USER_CONFIG) for multi-GPU
# (run one miner instance per GPU).
conf="--algo pearl --backend cuda --devices 0"
conf+=" --pool ${POOL}"
conf+=" --wallet ${WALLET} --worker ${WORKER}"
conf+=" --pool-pass ${POOL_PASS}"
conf+=" --api-port ${API_PORT}"
# User-provided extra args (e.g. --devices 1, --batch-size 2048, --verify).
conf+=" ${CUSTOM_USER_CONFIG:-}"

echo "$conf" > "$CONF_FILE"
echo "[h-config] wrote: $conf" >&2
