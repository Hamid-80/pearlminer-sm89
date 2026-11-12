#!/usr/bin/env bash
# build-sm89.sh — build the REAL Pearl miner (CPPminer, MIT) for sm89 / Ada Lovelace
# directly on your HiveOS rig (or any Linux box with an RTX 40-series GPU and the
# NVIDIA driver). Use this if you prefer not to use the prebuilt release tarball,
# or want to pin a different CPPminer version.
#
# Produces an installable HiveOS custom-miner package at
#   /tmp/pearlminer_sm89-<version>.tar.gz
# and (with --install) installs it into /hive/miners/custom/pearlminer_sm89/.
set -euo pipefail

CPPMINER_TAG="${CPPMINER_TAG:-v1.0}"
SM_ARCH="${SM_ARCH:-89}"          # 89 = Ada Lovelace (RTX 40). Use 86 for Ampere (RTX 30).
INSTALL="${1:-}"

echo "==> Building real Pearl miner: CPPminer ${CPPMINER_TAG} for sm_${SM_ARCH}"
echo "==> Requirements: CUDA Toolkit 12.x (nvcc), Rust (cargo), cmake, g++, git, curl"

command -v nvcc   >/dev/null || { echo "ERROR: nvcc not found. Install CUDA Toolkit 12.x." >&2; exit 1; }
command -v cargo  >/dev/null || { echo "ERROR: cargo not found. Install Rust (rustup)." >&2; exit 1; }
command -v cmake  >/dev/null || { echo "ERROR: cmake not found." >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Cloning CPPminer ${CPPMINER_TAG}"
git clone --depth 1 --branch "$CPPMINER_TAG" https://github.com/1640675651/CPPminer.git "$WORK/cppminer"

echo "==> Building (CUDA backend, sm_${SM_ARCH}; this takes ~15-30 min)"
CMAKE_BUILD_PARALLEL_LEVEL=2 bash "$WORK/cppminer/build.sh" --backend cuda --cuda-arch "$SM_ARCH"
test -x "$WORK/cppminer/build/cppminer"

echo "==> Staging HiveOS package"
PKG="$WORK/pearlminer_sm89"
mkdir -p "$PKG"
cp "$WORK/cppminer/build/cppminer" "$PKG/pearlminer_sm89"
chmod +x "$PKG/pearlminer_sm89"

# Bundle libcudart if present (HiveOS may lack a CUDA toolkit).
CUDART="$(find /usr/local/cuda* "${CUDA_PATH:-}" -name 'libcudart.so.*' -not -type l 2>/dev/null | head -1 || true)"
[[ -n "$CUDART" ]] && cp "$CUDART" "$PKG/" && ln -sf "$(basename "$CUDART")" "$PKG/libcudart.so.12" || true

# Wrapper scripts: download from this repo (master), or create inline if offline.
for f in h-manifest.conf h-config.sh h-run.sh h-stats.sh; do
  if curl -fsSL -o "$PKG/$f" "https://raw.githubusercontent.com/Hamid-80/pearlminer-sm89/master/hiveos/$f"; then
    :
  else
    echo "WARN: could not fetch $f from GitHub; copy it manually from hiveos/."
  fi
done
chmod +x "$PKG"/h-config.sh "$PKG"/h-run.sh "$PKG"/h-stats.sh 2>/dev/null || true
sed -i "s/^CUSTOM_VERSION=.*/CUSTOM_VERSION=6.0-local/" "$PKG/h-manifest.conf" 2>/dev/null || true

VERSION="6.0-local-sm${SM_ARCH}"
TARBALL="/tmp/pearlminer_sm89-${VERSION}.tar.gz"
tar -czf "$TARBALL" -C "$WORK" pearlminer_sm89
echo "==> Built: $TARBALL"
ls -la "$TARBALL"

if [[ "$INSTALL" == "--install" ]]; then
  echo "==> Installing to /hive/miners/custom/pearlminer_sm89"
  sudo mkdir -p /hive/miners/custom/
  sudo rm -rf /hive/miners/custom/pearlminer_sm89
  sudo tar -xzf "$TARBALL" -C /hive/miners/custom/
  sudo chmod +x /hive/miners/custom/pearlminer_sm89/*
  echo "==> Installed. Import hiveos-flight-sheet-custom-pearlminer_sm89.json in HiveOS."
fi
