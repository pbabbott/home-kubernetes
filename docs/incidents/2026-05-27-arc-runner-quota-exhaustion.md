# Incident: ARC Runner Quota Exhaustion (2026-05-27)

## Summary

GitHub Actions jobs queuing in prod-gen2 due to `arc-runners` namespace ResourceQuota blocking new runner pods from starting.

## Timeline

- **~02:14 UTC** — User reports jobs queuing in prod GH Actions
- **~02:22 UTC** — Investigation begins; ARC controller logs show quota errors
- **~02:40 UTC** — Root cause confirmed; fixes applied and pushed

## Root Cause

Three compounding over-provisioning issues in `arc-runners` namespace:

### 1. Ephemeral-storage quota too low (immediate blocker)

`ResourceQuota.limits.ephemeral-storage` was `100Gi`. Each dind pod counted **40Gi** against quota:
- `runner` container: `limits.ephemeral-storage: 20Gi` (explicit)
- `dind` sidecar container: `20Gi` from LimitRange default (container had `resources: {}`)

With 2 dind pods + infra pods at 71Gi, quota rejected any new pod requesting 40Gi.

ARC controller error:
```
pods "prod-gen2-dind-runner-..." is forbidden: exceeded quota: arc-runners,
requested: limits.ephemeral-storage=40Gi, used: limits.ephemeral-storage=71Gi,
limited: limits.ephemeral-storage=100Gi
```

### 2. LimitRange CPU default too high (secondary bottleneck)

`LimitRange` applied `cpu: 2` as default limit to containers with no explicit resources. Each dind pod had two such containers:
- `dind` sidecar (`resources: {}`) → 2 CPU from LimitRange
- `init-dind-externals` init container (`resources: {}`) → 2 CPU from LimitRange

Pod effective CPU = runner(1) + dind-sidecar(2) = **3 CPU per dind pod**.  
With 4 pods running, the `limits.cpu: 12` quota was saturated.

### 3. Runner container ephemeral-storage limits over-provisioned

Both `runner` and `dind` containers had `limits.ephemeral-storage: 20Gi` despite bulk writes going to mounted emptyDir volumes, not the container overlay layer.

## Fixes Applied

| File | Change |
|------|--------|
| `arc-runners-resourcequota.yaml` | `limits.ephemeral-storage` 100Gi→200Gi, `limits.cpu` 12→20, `limits.memory` 24Gi→30Gi, `pods` 12→16 |
| `arc-runners-limitrange.yaml` | Default `cpu` 2→500m, `memory` 4Gi→2Gi, `ephemeral-storage` 20Gi→5Gi |
| `arc-runner-dind-amd64-helmrelease.yaml` | Runner container ephemeral 20Gi→5Gi, dind container ephemeral 20Gi→5Gi, runner cpu limit 1000m→750m, var-lib-docker emptyDir 20Gi→10Gi |
| `arc-runner-amd64-helmrelease.yaml` | CPU limit 2→1, request 1→500m |

## Post-Fix State

- Quota: `cpu 13/20`, `ephemeral-storage 86/200Gi`, `memory 28/30Gi`, `pods 7/16`
- Multiple dind runners now running concurrently (was stuck at 1)

## Lessons

- LimitRange defaults silently apply to chart-injected sidecar/init containers — audit when setting quota limits
- ARC dind runner pods have containers injected by the chart (`dind`, `init-dind-externals`) that inherit namespace defaults; add explicit resource specs or keep LimitRange defaults conservative
- Memory quota (30Gi) is still tight at current load; monitor if more runner types are added
