# GitHub ARC Runner Optimization Plan

## Findings (kubectl-verified, 2026-06-01)

### 1. Controller has no resource limits — confirmed

`kubectl get pod arc-controller-... -n arc-systems -o jsonpath='{...resources}'` returns `{}`.
No LimitRange exists in `arc-systems` namespace. Controller runs completely unconstrained.

**Evidence:** `ephemeralrunner` reconcile p95 spiked to **22,500ms** over 24h, avg 1,074ms.
Root cause of startup latency outliers (p95 max **282s**).

### 2. dind sidecar running with LimitRange defaults — kustomization patch is a no-op

The ARC chart renders the dind container as `initContainers[].restartPolicy: Always` (native k8s sidecar), not `spec.containers[1]`.

The prod kustomization patches `path: /spec/values/template/spec/containers/1/resources/...` — this targets `spec.containers[1]`, which does **not exist** on dind pods. The patch silently does nothing.

Live pod confirms dind sidecar is running with LimitRange namespace defaults:
- `cpu limit: 500m` (intended: not explicitly set, but too low for Docker daemon)
- `memory limit: 2Gi` (intended patch was 5Gi — never landed)

**Evidence:** dind CPU throttle under build load contributes to exec p95 max of **847s** (~14 min).

### 3. Pod quota at exact maximum

ResourceQuota `pods: 16` in `arc-runners`. At peak scale:
- 8 amd64 runner pods + 6 dind runner pods = 14
- 2 support pods (actions-cache-server, turborepo-remote-cache) = 2
- **Total: 16 = exactly at quota**

Any rolling update, restart, or extra pod during peak will be rejected.

### 4. CPU quota has minimal headroom

ResourceQuota `limits.cpu: 22`. At full scale:
- amd64: 8 × 1250m = 10,000m
- dind: 6 × (1000m runner + 500m dind sidecar) = 9,000m
- support: 500m + 500m = 1,000m
- **Total: 20,000m** → 2 cores headroom

If dind sidecar CPU limit is raised (see change #2), headroom shrinks further.

---

## Changes Implemented (2026-06-01)

> **Note on dind sidecar resources:** The chart (`gha-runner-scale-set` 0.14.1) injects the `dind` container as an `initContainers[].restartPolicy: Always` sidecar — it cannot be overridden via `template.spec.initContainers` in values without creating a duplicate container name. The only viable mechanism without rewriting the full dind setup is the namespace LimitRange default. Change 2 uses that approach.

### Change 1 — ResourceQuota raised

**File:** `applications/base/arc/arc-runners-resourcequota.yaml`

| Field | Before | After |
|-------|--------|-------|
| `pods` | `"16"` | `"20"` |
| `limits.cpu` | `"22"` | `"28"` |
| `limits.memory` | `80Gi` | `80Gi` (unchanged) |
| `limits.ephemeral-storage` | `200Gi` | `200Gi` (unchanged) |

Removes zero-headroom pod ceiling and accommodates dind CPU increase.

### Change 2 — dind sidecar CPU raised via LimitRange

**File:** `applications/base/arc/arc-runners-limitrange.yaml`

| Field | Before | After |
|-------|--------|-------|
| `default.cpu` | `500m` | `1000m` |

The dind sidecar gets no explicit resources from the chart — it inherits LimitRange namespace defaults. Raising default CPU from 500m to 1000m gives the Docker daemon 2× more CPU headroom. Memory default unchanged (2Gi is sufficient for the daemon; image layers use ephemeral storage).

Also removed a dead patch from `applications/prod-gen2/arc/kustomization.yaml` that was targeting `containers/1/resources/limits/memory: 5Gi` on the dind HelmRelease. That path (`spec.containers[1]`) does not exist on dind pods — the patch was a no-op.

### Change 3 — Controller resource limits added

**File:** `applications/base/arc/arc-controller-helmrelease.yaml`

Added under `values:`:
```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
```

Prevents controller CPU starvation during burst scaling. Targets the 22.5s `ephemeralrunner` reconcile spikes.

---

## Rollback

System was **working well** before these changes. To revert each change independently:

### Rollback Change 1 — ResourceQuota

`applications/base/arc/arc-runners-resourcequota.yaml`:
```yaml
spec:
  hard:
    pods: "16"
    limits.cpu: "22"
    limits.memory: 80Gi
    limits.ephemeral-storage: 200Gi
```

No pod impact — quota changes take effect immediately.

### Rollback Change 2 — LimitRange + restore dead patch

`applications/base/arc/arc-runners-limitrange.yaml` — revert `default.cpu` to `500m`:
```yaml
      default:
        cpu: 500m
        memory: 2Gi
        ephemeral-storage: 5Gi
```

LimitRange only affects **new** pods. Existing dind runner pods keep their current resources until they are replaced (ephemeral runners recycle per job, so rollback takes effect within one job cycle).

Optionally restore the dead patch to `applications/prod-gen2/arc/kustomization.yaml` (it was already a no-op, so omitting is safe):
```yaml
      - op: replace
        path: /spec/values/template/spec/containers/1/resources/limits/memory
        value: "5Gi"
```

### Rollback Change 3 — Controller limits

`applications/base/arc/arc-controller-helmrelease.yaml` — remove the `resources:` block entirely:
```yaml
  values:
    metrics:
      controllerManagerAddr: ":8080"
      listenerAddr: ":8080"
      listenerEndpoint: "/metrics"
    flags:
      logLevel: "info"
    dnsConfig:
      options:
        - name: ndots
          value: "2"
```

Triggers controller pod restart. Brief pause in runner reconciliation (~10–30s) while pod comes back up.

---

## Verification

```bash
# Confirm controller has limits
kubectl get pod -n arc-systems -l app.kubernetes.io/name=gha-rs-controller \
  -o jsonpath='{.items[0].spec.containers[0].resources}'

# Confirm dind sidecar CPU (check next dind runner pod that spawns)
kubectl get pod -n arc-runners -l app.kubernetes.io/instance=prod-gen2-dind-runner \
  -o json | python3 -c "
import json,sys
pod=json.load(sys.stdin)['items'][0]
for c in pod['spec'].get('initContainers',[]):
    if c['name']=='dind':
        print(c.get('resources',{}))
"

# Confirm quota
kubectl describe resourcequota arc-runners -n arc-runners
```

Monitor `ephemeralrunner` reconcile p95 in Grafana dashboard `arc-runner-scale-set` for 24h after changes land.
