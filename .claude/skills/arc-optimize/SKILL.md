---
name: arc-optimize
description: Analyze ARC runner metrics via Grafana prod, review HelmRelease config, produce optimization recommendations, apply changes, and commit.
---

Investigate ARC runner performance, compare against current config, recommend and apply improvements. Follow steps in order.

## Step 1: Query Grafana prod — ARC dashboard

Fetch the ARC runner scale set dashboard (UID `arc-runner-scale-set`) using `mcp__grafana-prod__get_dashboard_by_uid` to confirm it's reachable. Then run the following Prometheus queries (datasource UID: `prometheus`) over the last 24h (`queryType: range`, `stepSeconds: 300`):

```
# Pool size
sum by (runner_scale_set_name) (gha_registered_runners{job="arc-listeners"})
sum by (runner_scale_set_name) (gha_running_jobs{job="arc-listeners"})
sum by (runner_scale_set_name) (gha_desired_runners{job="arc-listeners"})
sum by (runner_scale_set_name) (gha_assigned_jobs{job="arc-listeners"})

# Bounds (instant)
sum by (runner_scale_set_name) (gha_min_runners{job="arc-listeners"})
sum by (runner_scale_set_name) (gha_max_runners{job="arc-listeners"})

# Startup latency
histogram_quantile(0.95, sum by (le) (rate(gha_job_startup_duration_seconds_bucket{job="arc-listeners"}[30m])))
```

## Step 2: Query Grafana prod — compute resources

Query namespace `arc-runners` for CPU and memory (datasource UID: `prometheus`, range 24h, step 300s):

```
# CPU per pod
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="arc-runners", container!=""}[5m]))

# Memory per pod
sum by (pod) (container_memory_working_set_bytes{namespace="arc-runners", container!=""})
```

Look for: pods with high memory that disappear (OOM kill), consistently maxed CPU, pods with short time series (killed).

## Step 3: Read HelmReleases

Read both runner HelmReleases:
- `applications/base/arc/arc-runner-amd64-helmrelease.yaml`
- `applications/base/arc/arc-runner-dind-amd64-helmrelease.yaml`

Note: `minRunners`, `maxRunners`, resource requests/limits for both `runner` and `dind` containers, anti-affinity rules.

## Step 4: Review recent optimization history

Read all files in `docs/arc-optimization/` to understand what has already been applied. Do not re-recommend changes that are already in place.

## Step 5: Produce recommendation

Analyze findings across steps 1–4. Key things to assess:

| Signal | What it means |
|--------|---------------|
| p95 startup > 60s | minRunners too low — cold starts hurt job latency |
| desired consistently hits maxRunners | maxRunners too low — jobs are queuing |
| pods disappear mid-series with high memory | OOM kill — raise memory limit |
| dind sidecar at memory limit | Docker build cache exhausting limit — raise dind limit |
| required anti-affinity between scale sets | Can block scheduling if nodes are limited |
| long idle periods with many registered runners | minRunners too high — wasting resources |

Write findings to `docs/arc-optimization/<YYYY-MM-DD>-recommendations.md`. Include:
- Data sources and time range queried
- Current config table (min, max, resource limits per scale set)
- Numbered findings with supporting data
- Recommended changes with before/after values
- Priority ordering

## Step 6: Apply changes

Edit the HelmRelease files per recommendations. Common changes:

**`arc-runner-amd64-helmrelease.yaml`**
- `minRunners` / `maxRunners`
- `resources.limits.memory` on runner container
- Anti-affinity: `requiredDuringSchedulingIgnoredDuringExecution` → `preferredDuringSchedulingIgnoredDuringExecution` (weight: 100)

**`arc-runner-dind-amd64-helmrelease.yaml`**
- `minRunners` / `maxRunners`
- `resources.limits.memory` on runner container
- `resources.limits.memory` on dind sidecar (look for `image: docker:dind` block)
- Anti-affinity same as above

When converting required → preferred anti-affinity, preserve the longhorn `preferredDuringSchedulingIgnoredDuringExecution` rule already present — merge into the same list, don't drop it.

## Step 7: Log changes

Write `docs/arc-optimization/<YYYY-MM-DD>-changes.md` documenting:
- What was changed (file, field, old → new value)
- Why (which finding drove it)

## Step 8: Commit and push

```bash
git add applications/base/arc/arc-runner-amd64-helmrelease.yaml \
        applications/base/arc/arc-runner-dind-amd64-helmrelease.yaml \
        docs/arc-optimization/
git commit -m "perf(arc): optimize runner scale set config

<bullet summary of changes>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
git push
```

## Notes

- Prometheus datasource UID is `prometheus` on both grafana-prod and grafana-nonprod
- ARC dashboard UID: `arc-runner-scale-set`
- Compute resources namespace dashboard UID: `85a562078cdf77779eaa1add43ccec1e`
- dind runner pods carry two containers: `runner` (the GHA runner) and `dind` (docker daemon as init container with `restartPolicy: Always`)
- Startup latency metric is NaN when no jobs run — gaps are normal
- OOM kills show as pods with very high memory at last data point before series ends abruptly
- Both HelmReleases are in `applications/base/arc/` — changes apply to both prod-gen2 and non-prod-gen2 clusters via kustomize overlays
