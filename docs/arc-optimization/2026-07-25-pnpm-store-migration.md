# ARC pnpm Store Migration — Longhorn → NAS NFS (2026-07-25)

## Why
`arc-pnpm-store` was backed by Longhorn RWX (`dataLocality: disabled`, 3 replicas).
Longhorn RWX = block volume on one node exported via NFSv4. All runner pods (up to 13)
access pnpm's content-addressable store over that NFS link. pnpm's small-file random IO
pattern is expensive on NFS under concurrent load. Node disk IO spiked to 8.75 rate
(~275 MB/s throughput) during CI bursts.

## What Changed
`applications/base/arc/arc-pnpm-store-persistentvolumeclaim.yaml`
- `storageClassName: longhorn` → `storageClassName: nas-storage`

NAS storage class: `nfs-subdir-external-provisioner` → `192.168.4.124:/volume1/ClusterStorage`
PVC subdir path pattern: `arc-runners-arc-pnpm-store`

## Migration Steps (manual)
1. Updated PVC YAML in repo, committed + pushed.
2. Deleted all runner pods in `arc-runners` namespace — in-flight jobs failed and re-queued.
3. Deleted old Longhorn PVC `arc-pnpm-store` in `arc-runners`.
4. Flux reconciled → new PVC created on `nas-storage`.
5. Runner pods restarted; pnpm store rebuilt from npm registry on first run.

## Trade-offs
- pnpm store starts empty — first run per package downloads from registry (slower).
  Subsequent runs use shared NAS cache (all runners benefit).
- NAS NFS (`192.168.4.124`) is dedicated hardware, not a Longhorn-managed export.
  Better throughput for concurrent small-file workloads.
- `archiveOnDelete: true` on `nas-storage` class — old data is archived, not deleted,
  if PVC is removed in future.

## Follow-up Opportunities
- Monitor NAS IO after migration to confirm improvement.
- If pnpm store rebuild latency is too painful after future PVC deletions, consider
  pre-warming via an init job or DaemonSet that seeds the NAS store from a snapshot.
- Consider `dataLocality: strict-local` for Longhorn RWO volumes in the arc-runners
  namespace to keep replica IO local to runner nodes.
- Investigate BuildKit persistent cache as alternative to shared pnpm store for dind
  runners (avoids NFS entirely for build steps).
- Harbor ghcr.io proxy: add proxy project for `ghcr.io` and register in daemon.json
  `registry-mirrors` to reduce startup image pull latency (currently ~5min p95).
