# 2026-05-07 — ARC Runner Non-Prod Fixes

## Issues resolved

### 1. arc-runner-dind-amd64 HelmRelease failing (Flux apps-ks blocked)

**Symptom:** `apps-ks` kustomization stuck with `HelmRelease/flux-system/arc-runner-dind-amd64 status: 'Failed'`

**Root cause:** Helm upgrade failed with:
```
.spec.template.spec.volumes: duplicate entries for key [name="dind-sock"]
```
When `containerMode.type: dind`, the chart auto-injects a `dind-sock` volume. The HelmRelease values also explicitly declared it, causing a duplicate key error on server-side apply.

**Fix:** Removed explicit `dind-sock` volume from `applications/base/arc/arc-runner-dind-amd64-helmrelease.yaml`

**Commit:** `353f1af` — `fix(arc): remove duplicate dind-sock volume from dind runner`

---

### 2. Node saturation — worker-1 OOM-killing longhorn-manager

**Symptom:** After triggering GitHub Actions jobs, `tf-nonprod-k8s-worker-1` hit 95% CPU / 99% memory allocated. `longhorn-manager` OOM-killed 30+ times. Prometheus data volume degraded to 1/3 replicas (only worker-3 replica healthy). Node metrics became `<unknown>`.

**Root cause:**
- Both amd64 runner pods scheduled to same node (`topologySpreadConstraints.whenUnsatisfiable: ScheduleAnyway` allowed stacking when other nodes were also memory-heavy)
- Each runner had `1Gi` memory request; two runners = 2Gi on a 3.4 GiB node already hosting longhorn, prometheus, harbor, calico
- Node reached 3300Mi/3400Mi requests (99%) — any burst caused OOM kills of lower-priority pods

**Fix:** Both `arc-runner-amd64` and `arc-runner-dind-amd64` HelmReleases updated:
- `whenUnsatisfiable: ScheduleAnyway` → `DoNotSchedule` — enforces 1 runner per node, queues extras
- Memory requests: `1Gi` → `512Mi` (runner + dind containers) — reduces scheduler over-allocation; limits unchanged

**Files changed:**
- `applications/base/arc/arc-runner-amd64-helmrelease.yaml`
- `applications/base/arc/arc-runner-dind-amd64-helmrelease.yaml`

**Commit:** `55237b1` — `fix(arc): prevent runner node saturation in non-prod`

---

## State at session end

- Both commits pushed to `main`
- Flux reconciling — `apps-ks` should clear once HelmReleases upgrade successfully
- Worker-1 still recovering (jobs were still running at session end)
- Prometheus volume degraded — should self-heal once longhorn-manager stabilizes after memory pressure lifts
