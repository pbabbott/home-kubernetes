# Session: Media *arr Postgres Deadlock Fix

**Date:** 2026-05-16

## What happened

Prowlarr, Radarr, and Sonarr were stuck in `ContainerCreating` after a rolling update triggered by the postgres migration commit (`feat(media): configure postgres for prowlarr, radarr, sonarr`).

## Root causes (two, chained)

### 1. OnePasswordItem vault item name mismatch
`postgres-credentials` OnePasswordItem failed with:
> `Failed to retrieve item: No items found with identifier "PostgreSQL NAS ASUSTOR"`

The vault item didn't exist in 1Password yet. The secret was never created, so new pods would have failed with missing secretKeyRef even after the PVC issue was resolved. **Fix:** User created the item in 1Password UI; restarted op-connect and operator to force re-sync. Secret came up Ready within ~10s.

### 2. RWO PVC deadlock during cross-node rolling update
- Config PVCs (`prowlarr-config`, `radarr-config`, `sonarr-config`) are Longhorn **ReadWriteOnce**
- Old pods ran on **worker-1**; rolling update scheduled new pods on **worker-2**
- Longhorn RWO can only attach to one node — new pods on worker-2 stuck in `ContainerCreating` waiting for PVCs held by old pods on worker-1
- Deployment default strategy (`RollingUpdate`) never terminates old pod until new pod is ready — classic deadlock

**Fix (immediate):**
1. Deleted old pods on worker-1 to release PVC attachments
2. Old ReplicaSets respawned pods on worker-3 (creating a second race) — scaled old RS to 0 manually
3. New pods attached PVCs on worker-2 and came up cleanly

**Fix (permanent):**
Added `strategy: type: Recreate` to all three deployments. With Recreate, old pod terminates before new pod starts — PVC is guaranteed released before new pod schedules.

### SSA complication
Flux dry-run initially rejected the strategy change because the live deployments had `rollingUpdate.maxSurge`/`maxUnavailable` defaulted. Had to `kubectl patch` the live objects to replace the entire `strategy` field via JSON patch before Flux could reconcile cleanly.

## Commits

- `ff1ab77` — `fix(media): use Recreate strategy for *arr deployments`
- `f4522c3` — `fix(media): explicitly null rollingUpdate for Recreate strategy` (reverted approach)
- `a71dbe5` — `fix(media): remove rollingUpdate null, live objects already patched`

## Final state

All three services Running on worker-2 with postgres config. `postgres-credentials` secret provisioned. `apps-ks` kustomization reconciling (Flux SSA still pending final reconcile at session end).

## Prevention

- Any deployment with a Longhorn RWO PVC **must use `strategy: type: Recreate`** — rolling updates across nodes will always deadlock
- When adding new `secretKeyRef` env vars, ensure the secret (or its OnePasswordItem) is created **before** the deployment change lands, or deploy them together and accept a brief pending period
