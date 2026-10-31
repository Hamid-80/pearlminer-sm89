# PearlMiner SM89 (HiveOS / RTX 4070 Ti)

Custom PearlHash (pearlhash) miner for HiveOS, built automatically with GitHub Actions on every push to `main`.

**Recommended:** use the SRBMiner flight sheet JSON below — SRBMiner-Multi has native `pearlhash` support and is pool-tested.

**Download custom miner:** [pearlminer_sm89-4.3.tar.gz](https://github.com/Hamid-80/pearlminer-sm89/releases/download/v4.3/pearlminer_sm89-4.3.tar.gz)

## Flight Sheets (JSON)

| File | Miner | Notes |
|---|---|---|
| [`hiveos-flight-sheet.json`](hiveos-flight-sheet.json) | `srbminer_custom` (SRBMiner-Multi 3.8.2) | ✅ recommended, quick start |
| [`hiveos-flight-sheet-custom-pearlminer_sm89.json`](hiveos-flight-sheet-custom-pearlminer_sm89.json) | custom `pearlminer_sm89` | this repo's own miner |

Import via Flight Sheet → Miner → Custom → Setup Miner Config → JSON editor `{...}`.

## HiveOS custom-miner conventions used

Follows the official HiveOS custom miner integration docs:
- `h-manifest.conf` with `CUSTOM_NAME`, `CUSTOM_VERSION`, `CUSTOM_CONFIG_FILENAME`, `CUSTOM_LOG_BASENAME`
- `h-config.sh` generates `miner.conf`
- `h-run.sh` launches the binary from `/hive/miners/custom/pearlminer_sm89`
- `h-stats.sh` (sourced by the HiveOS agent) defines `$khs` and `$stats`
- Archive name `pearlminer_sm89-<version>.tar.gz` and inner folder `pearlminer_sm89/`

## Reference pool endpoints

- Kryptex: `prl-ae.kryptex.network:7048`
- Pearl Fortune (pool-tested for SRBMiner): `global.pearlfortune.org:8888`
