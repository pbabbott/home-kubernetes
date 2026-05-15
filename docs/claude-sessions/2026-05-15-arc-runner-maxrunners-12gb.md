# Session: ARC Runner maxRunners Bump After 12 GB Node Upgrade
**Date:** 2026-05-15  
**Branch:** main

## What We Did

Verified the prod-gen2 worker node RAM upgrade to 12 GB had propagated, then recalculated safe maxRunners ceilings and applied them to the prod overlay.

## Context

Prior session (2026-05-13) set prod maxRunners to 5 for both scale sets and added 2Gi memory requests. Workers were 8 GB at that time (~7.4 GiB allocatable). User upgraded nodes to 12 GB.

## Node State After Upgrade

| Node | Allocatable Memory | Allocatable CPU |
|------|--------------------|-----------------|
| tf-prod-k8s-worker-1 | 11.13 GiB | 3650m |
| tf-prod-k8s-worker-2 | 11.13 GiB | 3650m |
| tf-prod-k8s-worker-3 | 11.13 GiB | 3650m |
| **Total** | **33.4 GiB** | **10.95 CPU** |

## Analysis

Memory is now abundant (33.4 GiB total). CPU is the binding constraint.

| Pod type | Memory request | CPU request | Max/node (CPU) | Cluster max |
|----------|---------------|-------------|----------------|------------|
| amd64 runner | 2 Gi | 1.0 | 3 | 9 |
| dind runner (both containers) | 2.5 Gi | 1.5 | 2 | 6 |

## Changes Made

**File:** `applications/prod-gen2/arc/kustomization.yaml`

- `arc-runner-amd64` maxRunners: 5 → **8** (leaves ~1 CPU/node headroom)
- `arc-runner-dind-amd64` maxRunners: 5 → **6** (CPU-ceiling: 2/node × 3 nodes)

**Commit:** `0c3bedb feat(arc): increase prod-gen2 maxRunners after 12GB node upgrade`

## Notes

- Non-prod unchanged (base: maxRunners:3, 1Gi memory requests)
- Runners use `arc-runner-low` priority — other workloads preempt naturally
- CPU requests are the real scheduler gate, not memory
