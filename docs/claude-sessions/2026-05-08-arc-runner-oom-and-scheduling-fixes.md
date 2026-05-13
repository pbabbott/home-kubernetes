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

---

### 5. Second OOM — cross-scale-set co-location

**Problem:** After topology spread was scoped per-scale-set, amd64 and dind runners were still free to land on the same node (different scale sets = no spread constraint between them). During a subsequent intensive turbo build:
- worker-1: amd64 runner `xqjj7` (566 MB+ and climbing) + dind runner `fh8px` + Prometheus + system pods
- Node hit global OOM — kernel OOM killer fired and killed `longhorn-manage` (oom_score_adj=1000, BestEffort) first, destabilizing the node → NodeNotReady again

**Kernel evidence:**
```
oom-kill: global_oom, task=longhorn-manage, pid=3447421, oom_score_adj=1000
Out of memory: Killed process 3447421 (longhorn-manage) anon-rss:223824kB
```

**Fix:** Hard pod anti-affinity (`requiredDuringSchedulingIgnoredDuringExecution`) added to both scale sets, preventing co-location:

```yaml
# arc-runner-amd64: repel dind runners
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    - topologyKey: kubernetes.io/hostname
      labelSelector:
        matchLabels:
          app.kubernetes.io/instance: non-prod-gen2-dind-runner

# arc-runner-dind-amd64: repel amd64 runners
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    - topologyKey: kubernetes.io/hostname
      labelSelector:
        matchLabels:
          app.kubernetes.io/instance: non-prod-gen2-amd64-runner
```

**Commit:** `b61dd91`

**Result after applying:** amd64 runner on worker-2, dind runner on worker-1 — confirmed separate nodes.

---

## State at session end

- All fixes applied and reconciled: `b61dd91` (apps-ks at `2dcb08bc`)
- `arc-runner-amd64` v5, `arc-runner-dind-amd64` v7 — both live
- All 4 nodes Ready
- amd64 and dind runners permanently separated by hard anti-affinity

## Key findings

- `kube-reserved` without `enforceNodeAllocatable` + `kubeReservedCgroup` = scheduler accounting only, no real cgroup CPU cap on kubepods
- NodeNotReady was **OOM** in both incidents, not CPU starvation
- **Incident 1:** amd64 runner stacking (pre topology-spread fix) → 2x builds on same node
- **Incident 2:** amd64 + dind co-location (different scale sets) → combined memory exceeded physical RAM
- Final topology: each node holds at most one runner type; builds can't combine to exhaust node memory
