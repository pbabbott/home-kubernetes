# op-connect HTTPRoute — Gen2 Clusters

**Date:** 2026-05-10
**Commit:** 248d729

## Goal

Expose `op-connect` via HTTPRoute on both gen2 clusters. Was previously only present in gen1 homelab (via nginx Ingress).

## What Was Done

### Discovery
- op-connect already deployed in gen2 via `infra/base/onepassword/` HelmRelease
- Actual service name deployed by helm chart: `onepassword-connect` (not `op-connect`) on port `8080`
- Gen2 networking uses Gateway API (HTTPRoute → `istio-ingress` in `istio-system`) — not nginx Ingress

### Changes

**`infra/base/onepassword/op-connect-httproute.yaml`** (new)
- HTTPRoute pointing `onepassword-connect:8080` via `istio-ingress` https section
- Default hostname: `op-connect.local.abbottland.io`

**`infra/base/onepassword/kustomization.yaml`**
- Added `op-connect-httproute.yaml` to resources

**`infra/prod-gen2/onepassword/kustomization.yaml`**
- Patch: hostname → `op-connect.local.abbottland.io`

**`infra/non-prod-gen2/onepassword/kustomization.yaml`**
- Patch: hostname → `op-connect.local.non-prod.abbottland.io`

## URLs

| Cluster | URL |
|---------|-----|
| prod-gen2 | `https://op-connect.local.abbottland.io` |
| non-prod-gen2 | `https://op-connect.local.non-prod.abbottland.io` |
