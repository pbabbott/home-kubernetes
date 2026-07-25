# ARC Runner IO Investigation — 2026-07-25

## Data Sources
- Grafana prod Prometheus: 24h range, step 300s
- Node exporter disk IO metrics (per-node, per-device)
- HelmRelease files: `applications/base/arc/arc-runner-*-helmrelease.yaml`
- `kubectl get pvc -n arc-runners`
- `kubectl get configmap arc-dind-daemon-config -n arc-runners`

## Current Config

| Scale Set | min | max | Runner Mem limit | dind Mem limit | var-lib-docker |
|-----------|-----|-----|------------------|----------------|----------------|
| dind      | 2   | 5   | 3Gi              | 3Gi            | emptyDir 20Gi  |
| amd64     | 1   | 8   | 4Gi              | —              | —              |

pnpm store PVC: Longhorn RWX, 20Gi, `dataLocality: disabled`, 3 replicas

## Findings

### Finding 1 — Docker concurrent download burst (PRIMARY IO CAUSE)
Node disk throughput spiked to **275 MB/s** and `node_disk_io_time_seconds_total` rate hit **8.75** during CI bursts when 5–6 dind runners start simultaneously.

Root cause: Docker daemon default `max-concurrent-downloads: 3`. With 5 dind runners starting in parallel, up to 15 concurrent layer writes hit node-local disk (emptyDir `/var/lib/docker`). Node `192.168.6.25:sda` currently at 42% busy with only 4 active runners — will saturate under full load.

Fix: Add `"max-concurrent-downloads": 2` to `arc-dind-daemon-config`. Reduces concurrent pulls from 15 to 10 during full saturation; smooths IO burst without reducing throughput.

### Finding 2 — Longhorn RWX pnpm store NFS contention
`arc-pnpm-store` (Longhorn RWX, `dataLocality: disabled`) serves all runners via NFS from a single Longhorn-managed NFS export node. With up to 13 concurrent runners all reading/writing pnpm's content-addressable store, this NFS endpoint becomes the IO bottleneck for dependency installation steps.

Longhorn RWX = block device on one node exported via NFSv4. All other nodes access over cluster network. pnpm performs many small random reads on cache hit, many writes on new deps. This pattern is expensive on NFS.

**This is an architectural issue.** Recommended long-term fix: migrate `arc-pnpm-store` to NAS NFS (`192.168.4.124`) for dedicated NFS throughput, or use `dataLocality: strict-local` with runner node affinity (requires single-node scheduling). Short-term: no config-only fix.

### Finding 3 — Startup latency p95 = 279–294s
Consistently ~5 minutes when runners cold-start. With `minRunners=2` for dind and `minRunners=1` for amd64, job bursts above those warm-pool sizes wait the full startup duration before being dispatched. Observed `prod-gen2-dind-runner-sln4c-runner-wwzwq` actively in `Init:0/2` during investigation.

Startup time breakdown (estimated):
- `init-dind-externals` cp: ~5s
- `dind` dockerd startup + probe: up to 120s
- Docker image layer pull (ghcr.io, no Harbor proxy): variable — likely primary contributor to 279s p95

Fix A: Add ghcr.io proxy to Harbor and register in daemon.json registry-mirrors.
Fix B: Increase amd64 `minRunners: 1 → 2` to reduce cold starts for the amd64 pool.

### Finding 4 — Desired hit 11, maxRunners total = 13
During recent burst: `gha_desired_runners` = 11, `gha_registered_runners` = 6. 5 jobs queued waiting for runners. Pool ceiling (8 amd64 + 5 dind = 13) is adequate but cold-start latency makes the queue painful.

### Finding 5 — No OOM evidence
Peak amd64 pod memory: 3273Mi (limit 4Gi — fine). Peak dind pod memory: 3097Mi (sum of runner+dind containers, limits 6Gi total — fine). No OOM kills detected.

## Changes Applied

### 1. daemon.json — max-concurrent-downloads
**File:** `applications/base/arc/arc-dind-daemon-config.yaml` (or inline configmap)
**Change:** Added `"max-concurrent-downloads": 2`
**Expected:** IO burst during startup drops ~33% (15→10 concurrent writes per burst event)

### 2. amd64 HelmRelease — minRunners 1→2
**File:** `applications/base/arc/arc-runner-amd64-helmrelease.yaml`
**Change:** `minRunners: 1 → 2`
**Expected:** Reduces cold-start queue for amd64 jobs during bursts

## Architectural Recommendations (Not Applied)

| Issue | Recommended Fix | Effort |
|-------|----------------|--------|
| pnpm store NFS contention | Migrate PVC to NAS NFS (192.168.4.124) | Medium |
| ghcr.io pulls no mirror | Add Harbor proxy-ghcrio project + daemon.json entry | Low |
| dind layer cache eviction | Consider BuildKit persistent cache PVC instead of emptyDir | High |
