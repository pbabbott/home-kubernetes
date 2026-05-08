# 2026-05-08 — ARC Runner OOM & Scheduling Fixes

## Issues resolved

### 1. kube-reserved verification

Confirmed kube-reserved applied to all 3 workers:
- CPU: 4000m → **3650m** allocatable (250m kube + 100m system reserved)
- Memory: 3493060Ki → **2923716Ki** allocatable (~555Mi reserved)

**Finding:** kube-reserved is scheduler-accounting only. `kubepods.slice` has `cpu.max = max` (unlimited). No actual cgroup CPU enforcement. CPU protection relies on per-container CFS quotas, not a kubepods-level cap.

---

### 2. dind runner CPU limits raised

**Problem:** Turborepo pnpm builds saturate both `runner` and `dind` containers simultaneously. Previous 2-core limit per container was too restrictive — builds were getting throttled and not finishing.

**Fix:** `applications/base/arc/arc-runner-dind-amd64-helmrelease.yaml`
- `runner` CPU limit: `2` → `3`
- `dind` CPU limit: `2` → `3`

Total overcommit to 6 CPU limits, but effective ceiling is ~3.65 cores (kubepods allocatable). Kubelet stays protected by kube-reserved accounting.

**Commit:** `758c14c`

---

### 3. Topology spread scoped to per-scale-set

**Problem:** `topologySpreadConstraints.labelSelector` used `app.kubernetes.io/component=runner` globally — dind runners and amd64 runners counted against each other. When worker-2 held an amd64 runner and worker-1 held a dind runner, pending amd64 pods were forced to worker-3 (which was memory-full), blocking scheduling.

**Fix:** Added `app.kubernetes.io/instance` to the label selector in both HelmReleases so each scale set only counts its own pods.

```yaml
# arc-runner-amd64-helmrelease.yaml
labelSelector:
  matchLabels:
    app.kubernetes.io/component: runner
    app.kubernetes.io/instance: non-prod-gen2-amd64-runner

# arc-runner-dind-amd64-helmrelease.yaml
labelSelector:
  matchLabels:
    app.kubernetes.io/component: runner
    app.kubernetes.io/instance: non-prod-gen2-dind-runner
```

**Commit:** `e099ce9`

---

### 4. Grafana "no healthy upstream"

**Root cause:** Two amd64 runner pods stacked on worker-2 (topology spread wasn't scoped). Each ran a turborepo build consuming ~896 MB+ Node.js RSS. Node OOM triggered:

```
Out of memory: Killed process 2013854 (node) anon-rss:918028kB
Out of memory: Killed process 2010948 (turbo)
Out of memory: Killed process 2008326 (Runner.Listener)
```

When worker-2 OOM'd, it went NotReady. Grafana pod on worker-2 couldn't respond to its 1s readiness probe → removed from endpoints → Istio saw zero upstreams.

**Fix 1:** Topology spread fix (issue 3 above) prevents runner stacking — one amd64 runner per node max.

**Fix 2:** Increased Grafana readiness/liveness probe timeout from 1s → 10s to survive transient CPU pressure:
```yaml
grafana:
  readinessProbe:
    timeoutSeconds: 10
  livenessProbe:
    timeoutSeconds: 10
```
**Commit:** `339f61a`

---

## State at session end

- `758c14c` and `339f61a` applied via Flux (apps-ks and infra-ks reconciled to `d7aa5c3` and newer)
- `e099ce9` (topology spread fix) committed but **not yet reconciled** — Flux will pick it up on next interval or manual reconcile
- Worker-2 recovered and showing Ready at session end
- Pending runner pod `flj9b` still in queue until topology spread HelmRelease rolls

## Key findings

- `kube-reserved` without `enforceNodeAllocatable` + `kubeReservedCgroup` = scheduler accounting only, no real cgroup CPU cap on kubepods
- NodeNotReady was **OOM** (runner stacking), not CPU starvation — kube-reserved memory accounting did NOT prevent this
- Primary protection against node OOM: **topology spread `DoNotSchedule`** ensuring one runner per node
