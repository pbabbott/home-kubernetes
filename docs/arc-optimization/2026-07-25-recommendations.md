# ARC Runner Optimization Recommendations
Date: 2026-07-25

## Data Sources
- Grafana prod: `arc-runner-scale-set` dashboard (24h range)
- Grafana prod: `Kubernetes / Compute Resources / Namespace (Pods)` — namespace `arc-runners` (24h range)
- HelmReleases: `applications/base/arc/arc-runner-amd64-helmrelease.yaml`, `arc-runner-dind-amd64-helmrelease.yaml`

## Current Config

| Scale Set | min | max | Runner CPU req/limit | Runner Mem req/limit | DinD Mem limit |
|-----------|-----|-----|----------------------|----------------------|----------------|
| amd64     | 1   | 3   | 500m / 1250m         | 1Gi / 2.5Gi          | —              |
| dind      | 1   | 3   | 250m / 1000m         | 1Gi / 2.5Gi          | 2Gi            |

## Findings

### 1. Startup latency — p95 ~280–294s
Runner startup consistently takes ~5 minutes at p95. dind runner is primary offender: must pull `docker:dind`, start daemon, pass startup probe, then start runner. With `minRunners=1`, any burst hits cold-start latency immediately.

### 2. maxRunners cap too low
`gha_desired_runners` spiked to 7 during active CI but total cap is 6 (3+3). Jobs queued. dind was consistently saturated at 3 concurrent jobs. amd64 was mostly idle during those periods — dind is the bottleneck.

### 3. OOM kills on amd64 runner
Pod `prod-gen2-amd64-runner-...-b998g` observed at 3.7 GiB before disappearing (limit 2.5Gi → OOM kill). Pod `runner-7hhxk` hit 2.17 GiB. pnpm/Node.js builds spike memory during large dependency tree installs.

### 4. dind sidecar memory limit tight
Multiple dind pods showed runner container at 800MiB–1.5Gi with dind sidecar on top. Current dind limit is 2Gi. Large Docker builds (layer cache, concurrent pulls) push this.

### 5. Required anti-affinity is overly restrictive
Both scale sets have `requiredDuringSchedulingIgnoredDuringExecution` anti-affinity against each other. amd64 and dind runners cannot share nodes. With max 3+3=6 runners this requires 6 distinct schedulable nodes — can silently block scheduling on small clusters.

## Recommendations

### Priority 1 — Fix OOM kills (amd64 memory limit)
**File:** `applications/base/arc/arc-runner-amd64-helmrelease.yaml`
```yaml
resources:
  limits:
    memory: "4Gi"   # was 2.5Gi
```

### Priority 2 — Reduce cold-start latency (dind minRunners)
**File:** `applications/base/arc/arc-runner-dind-amd64-helmrelease.yaml`
```yaml
minRunners: 2   # was 1
```
Tradeoff: ~4.5Gi RAM always reserved for warm dind runner.

### Priority 3 — Increase dind throughput ceiling (maxRunners)
**File:** `applications/base/arc/arc-runner-dind-amd64-helmrelease.yaml`
```yaml
maxRunners: 5   # was 3
```
Cluster handled 4 concurrent dind runners comfortably in observed data.

### Priority 4 — Increase dind memory limits
**File:** `applications/base/arc/arc-runner-dind-amd64-helmrelease.yaml`
```yaml
# runner container
resources:
  limits:
    memory: "3Gi"   # was 2.5Gi

# dind sidecar
resources:
  limits:
    memory: "3Gi"   # was 2Gi
```
Also consider adding `--max-concurrent-downloads 3` to dockerd args to reduce peak pull memory.

### Priority 5 — Relax cross-scale-set anti-affinity
**Files:** both HelmReleases

Change `requiredDuringSchedulingIgnoredDuringExecution` → `preferredDuringSchedulingIgnoredDuringExecution` (weight: 100) for the cross-scale-set rule. Hard anti-affinity between amd64 and dind provides little benefit and restricts scheduling.

## Summary Table

| Change | File | Old | New |
|--------|------|-----|-----|
| amd64 memory limit | arc-runner-amd64-helmrelease.yaml | 2.5Gi | 4Gi |
| dind minRunners | arc-runner-dind-amd64-helmrelease.yaml | 1 | 2 |
| dind maxRunners | arc-runner-dind-amd64-helmrelease.yaml | 3 | 5 |
| dind runner memory limit | arc-runner-dind-amd64-helmrelease.yaml | 2.5Gi | 3Gi |
| dind sidecar memory limit | arc-runner-dind-amd64-helmrelease.yaml | 2Gi | 3Gi |
| cross-scale anti-affinity | both HelmReleases | required | preferred |
