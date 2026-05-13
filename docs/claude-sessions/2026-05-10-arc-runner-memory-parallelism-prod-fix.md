# 2026-05-10 — ARC Runner Memory Bump, Parallelism, and Prod Anti-Affinity Fix

## Context

Follow-up to 2026-05-08 OOM incidents. Both prod and nonprod clusters received more RAM.
Goal: increase runner memory limits and unlock parallelism where safe.

## Node allocatable memory (current)

| Cluster | Workers | Allocatable RAM |
|---------|---------|----------------|
| nonprod | worker-1,2,3 | ~3.28 GiB each |
| prod    | worker-1,2,3 | ~5.24 GiB each |

Previous nonprod allocatable was ~2.79 GiB (+~490 MB). Prod nodes are significantly larger.

---

## Issues resolved

### 1. Prod anti-affinity and topology spread were silently broken

**Problem:** Base HelmReleases hardcode `non-prod-gen2-*-runner` instance names in:
- `podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].labelSelector`
- `topologySpreadConstraints[0].labelSelector`

The prod-gen2 kustomization patched `releaseName` and `runnerScaleSetName` to `prod-gen2-*-runner`,
but did not patch the affinity/spread selectors. On prod, the anti-affinity was pointing at
`non-prod-gen2-dind-runner` which doesn't exist — so amd64 and dind runners could freely
co-locate on the same prod node. Topology spread was similarly ineffective (spread not scoped
per-scale-set on prod).

**Fix:** Added JSON 6902 patches to `applications/prod-gen2/arc/kustomization.yaml`:
- Anti-affinity selectors: `non-prod-gen2-*` → `prod-gen2-*`
- Topology spread selectors: `non-prod-gen2-*` → `prod-gen2-*`

---

### 2. Memory limits increased

**Base changes (nonprod-safe, 3.28 GiB nodes):**

`applications/base/arc/arc-runner-amd64-helmrelease.yaml`:
- runner memory request: `512Mi` → `1Gi`
- runner memory limit: `2Gi` → `2.5Gi`
- maxRunners: `2` → `3`

`applications/base/arc/arc-runner-dind-amd64-helmrelease.yaml`:
- runner container memory request: `512Mi` → `1Gi`
- runner container memory limit: `2Gi` → `2.5Gi`
- maxRunners: `2` → `3`
- dind container: unchanged (req 512Mi, limit 4Gi)

**Prod-gen2 overlay (5.24 GiB nodes — additional patches):**
- amd64 runner limit: `2.5Gi` → `4Gi`
- dind runner container limit: `2.5Gi` → `3Gi`
- dind/dind container limit: `4Gi` → `5Gi`

---

### 3. Parallelism unlocked

maxRunners bumped from 2 → 3 in base. With 3 worker nodes and hard anti-affinity between
scale sets, each node can hold at most one runner type. This allows all 3 nodes to serve
runners simultaneously (e.g. 2 amd64 + 1 dind, or 3 amd64, etc.).

ResourceQuota (`limits.memory: 24Gi`) covers all scheduling combinations — no change needed.

---

## Commit

`aa9e51a` — `fix(arc): bump runner memory, parallelism, and fix prod anti-affinity`

## Reconciliation confirmed

All 4 HelmReleases reached Ready after Flux reconciled:

| Release | Cluster | Helm version |
|---------|---------|-------------|
| non-prod-gen2-amd64-runner | nonprod | v7 |
| non-prod-gen2-dind-runner  | nonprod | v9 |
| prod-gen2-amd64-runner     | prod    | v6 |
| prod-gen2-dind-runner      | prod    | v8 |

## Key findings

- Prod anti-affinity was broken since initial port — runners could co-locate and OOM prod nodes
- Base HelmRelease instance names must be patched in per-cluster kustomizations when releaseName changes
- Prod nodes have ~60% more RAM than nonprod; per-cluster memory limit overlays worthwhile
- ResourceQuota (24Gi namespace cap) is sufficient for maxRunners=3 across both scale sets
