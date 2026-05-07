# Longhorn Prometheus PVC Degraded - Fix & Hardening

**Date:** 2026-05-06

## Problem

PVC `pvc-d15fe5c2-0e82-4cb0-ac72-0e1b743264e7` (Prometheus in `kube-prometheus-stack`) showed degraded health in Longhorn UI.

## Root Cause

Worker-1 had a brief reconnect at `2026-05-05T21:35:35Z`. Longhorn started rebuilding replica `r-c17ea56f` on worker-1. Rebuild stalled at **65%** with:

```
context deadline exceeded while syncing volume-snap-daily-ba-9a306968-0b53-4c9b-9d15-4edba7c3f2cd.img
```

Daily backup snapshots accumulated on the volume (default group, retain=2, but snapshot files are large for a 20Gi Prometheus PVC). The sync timed out due to Longhorn's default `engineReplicaTimeout` of 8 seconds.

## Immediate Fix

Deleted the stuck `WO` replica to force Longhorn to reschedule:

```bash
kubectl delete replica -n longhorn-system pvc-d15fe5c2-0e82-4cb0-ac72-0e1b743264e7-r-c17ea56f
```

New replica `r-9c102382` landed on worker-3 and began syncing cleanly.

Also patched the live volume label to stop future backups immediately:

```bash
kubectl label volume -n longhorn-system pvc-d15fe5c2-0e82-4cb0-ac72-0e1b743264e7 \
  recurring-job-group.longhorn.io/default=disabled --overwrite
```

## Declarative Changes (commit `13d2d43`)

**`infra/base/longhorn/longhorn-helm-release.yaml`**
- Added `engineReplicaTimeout: 30` to `defaultSettings` (was 8s)

**`infra/base/kube-prometheus-stack/kube-prometheus-stack-helm-release.yaml`**
- Added `recurring-job-group.longhorn.io/default: disabled` label to `volumeClaimTemplate.metadata.labels` — opts Prometheus PVC out of daily backup job on any future PVC recreation

## Notes

- Prometheus data doesn't need backup; backing it up only creates large snapshot files that slow replica rebuilds
- The 3-replica volume (`numberOfReplicas: 3`) had replicas on worker-1 and worker-2; worker-3 now holds the third after rebuild
- Suggested but not implemented: PrometheusRule alert for `longhorn_volume_robustness == 2`
