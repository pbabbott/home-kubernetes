# ARC Runner Parallelism - Prod Gen2

**Date:** 2026-05-13

## What we did

Relaxed scheduling constraints on prod-gen2 ARC runners to increase parallelism.

**File changed:** `applications/prod-gen2/arc/kustomization.yaml`

### Changes (applied to both `arc-runner-amd64` and `arc-runner-dind-amd64` patches)

1. **Removed hard cross-type anti-affinity**
   - `requiredDuringSchedulingIgnoredDuringExecution → []`
   - Previously: amd64 and dind runners could not share a node
   - With 3 worker nodes, this capped total concurrent runners to 3 across both types

2. **Relaxed topology spread constraint**
   - `whenUnsatisfiable: DoNotSchedule → ScheduleAnyway`
   - Spread across nodes is still preferred but won't block scheduling

3. **Bumped maxRunners**
   - `maxRunners: 3 → 5`
   - Allows up to 5 concurrent runners per type

### Why

Prod-gen2 has 3 worker nodes (`tf-prod-k8s-worker-1/2/3`). The hard anti-affinity between amd64 and dind runners meant each node could only host one runner type, limiting total simultaneous runners to 3. Relaxing to soft/preferred constraints lets all 3 nodes host either type.

Non-prod-gen2 unchanged.
