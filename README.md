# PearlMiner SM89 (HiveOS / RTX 4070 Ti)

Custom PearlHash (pearlhash) miner for HiveOS, built automatically with GitHub Actions on every push to `main`.

**Recommended:** the SRBMiner flight sheet — SRBMiner-Multi has native `pearlhash` support and is pool-tested.

**Download custom miner:** [pearlminer_sm89-4.4.tar.gz](https://github.com/Hamid-80/pearlminer-sm89/releases/download/v4.4/pearlminer_sm89-4.4.tar.gz)

## Flight Sheets (JSON)

| File | Miner | Notes |
|---|---|---|
| [`hiveos-flight-sheet.json`](hiveos-flight-sheet.json) | `srbminer_custom` (SRBMiner-Multi 3.8.2) | ✅ recommended, quick start |
| [`hiveos-flight-sheet-custom-pearlminer_sm89.json`](hiveos-flight-sheet-custom-pearlminer_sm89.json) | custom `pearlminer_sm89` | this repo's own miner |

Import via Flight Sheet → Miner → Custom → Setup Miner Config → JSON editor `{...}`.

## Presets (two binaries in the package)

| Binary | Fragments / SM blocks | Use |
|---|---|---|
| `pearlminer_sm89` | 16 / 5 | default (max register reuse) |
| `pearlminer_sm89_lite` | 8 / 8 | more occupancy, fewer registers/spills |

Switch inside HiveOS: Extra config arguments → `--preset lite` (h-run.sh picks the binary).

## Benchmark on the rig (no pool needed)

```sh
cd /hive/miners/custom/pearlminer_sm89
./pearlminer_sm89 --benchmark 30
./pearlminer_sm89_lite --benchmark 30
```

Compare the `[Benchmark] ... TH/s` line of both, then keep the faster preset.

## CLI

```sh
--pool|-o HOST:PORT     --wallet|-u WALLET[.WORKER]   --worker|-w NAME
--gpu|-g INDEX          --cclock MHz                  --stats-file PATH
--benchmark [SECONDS]   --help
```

## HiveOS custom-miner conventions used

- `h-manifest.conf`: `CUSTOM_NAME`, `CUSTOM_VERSION`, `CUSTOM_CONFIG_FILENAME`, `CUSTOM_LOG_BASENAME`
- `h-config.sh` generates `miner.conf`
- `h-run.sh` launches the binary from `/hive/miners/custom/pearlminer_sm89`
- `h-stats.sh` is sourced by the HiveOS agent and defines `$khs` / `$stats`
- Archive `pearlminer_sm89-<version>.tar.gz` with inner folder `pearlminer_sm89/`

## Pool endpoints

- Kryptex: `prl-ae.kryptex.network:7048`
- Pearl Fortune (pool-tested for SRBMiner): `global.pearlfortune.org:8888`
