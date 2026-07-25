# ARC Runner IO Changes — 2026-07-25

See `2026-07-25-io-recommendations.md` for full analysis.

## Changes

### 1. arc-dind-daemon-configmap.yaml — Docker concurrent download limit
- **Field:** `daemon.json` → added `max-concurrent-downloads: 2`, `max-concurrent-uploads: 2`
- **Old:** no limit (Docker default = 3 per daemon)
- **New:** 2 per daemon
- **Why:** Finding 1 — 5 dind runners at default=3 = 15 concurrent layer writes during startup burst, spiking node disk throughput to 275 MB/s. Throttling to 2 cuts peak concurrent writes from 15→10 (~33% reduction).

### 2. arc-runner-amd64-helmrelease.yaml — minRunners
- **Field:** `minRunners`
- **Old:** 1
- **New:** 2
- **Why:** Finding 3 — amd64 cold starts add 279–294s startup latency during bursts. Second warm runner absorbs initial burst spike without queuing.
