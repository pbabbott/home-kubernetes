# Coder Install — prod-gen2

Coder at `https://coder.local.abbottland.io` (LAN only, pihole DNS).

## Files

```
applications/base/coder/
  coder-ns.yaml
  coder-helmrepository.yaml       # helm.coder.com/v2
  coder-db-helmrepository.yaml    # bitnami
  coder-db-helmrelease.yaml       # bitnami/postgresql, longhorn 8Gi
  coder-helmrelease.yaml          # coder v2, dependsOn: coder-db
  coder-httproute.yaml            # pihole DNS, istio-ingress https
  coder-http-to-https-httproute.yaml
  kustomization.yaml

applications/prod-gen2/coder/
  kustomization.yaml              # references base/coder
```

`./coder` added to `applications/prod-gen2/kustomization.yaml`.

## Scaling knobs

| What | Where | Down | Up |
|------|-------|------|----|
| Coder CPU | `coder-helmrelease.yaml` → `coder.resources.requests.cpu` | 50m | 500m+ |
| Coder memory | `coder-helmrelease.yaml` → `coder.resources.limits.memory` | 256Mi | 1Gi+ |
| Coder replicas | `coder-helmrelease.yaml` → `coder.replicaCount` | 1 | 2+ |
| PG CPU | `coder-db-helmrelease.yaml` → `primary.resources.requests.cpu` | 50m | 500m+ |
| PG memory | `coder-db-helmrelease.yaml` → `primary.resources.limits.memory` | 256Mi | 1Gi+ |
| PG disk | `coder-db-helmrelease.yaml` → `primary.persistence.size` | 2Gi | 20Gi+ |

## Teardown

**Remove from GitOps first, then clean up cluster.**

1. Remove `- ./coder` from `applications/prod-gen2/kustomization.yaml`
2. Delete `applications/prod-gen2/coder/` and `applications/base/coder/`
3. Commit + push — Flux will delete HelmReleases, which triggers Helm uninstall
4. Flux does NOT delete the namespace automatically; clean up manually:
   ```
   kubectl delete namespace coder
   ```
5. Longhorn PVC for postgres will also persist after namespace deletion if Longhorn's reclaim policy is `Retain`. Check and delete manually:
   ```
   kubectl get pv | grep coder
   # then delete any Released PVs
   ```
