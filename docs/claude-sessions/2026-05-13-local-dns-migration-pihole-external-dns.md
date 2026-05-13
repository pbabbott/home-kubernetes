# Local DNS Migration: Wildcard → Per-Service Records via External-DNS + Pihole

## Problem

`*.local.abbottland.io → 192.168.6.28` wildcard in pihole causes pods with default `ndots:5`
to incorrectly resolve external names (e.g. `api.github.com.local.abbottland.io → 192.168.6.28`),
breaking outbound HTTPS/SSH from unpatched pods.

## Goal

Replace wildcard with per-service A records managed by a new `external-dns-pihole` instance
using the pihole webhook provider. Unknown `*.local.abbottland.io` names return NXDOMAIN,
letting the DNS search chain fall through to correct public addresses.

## What Was Implemented

### New Files Created

- `infra/base/external-dns/external-dns-pihole-helmrelease.yaml`
  - HelmRelease for `external-dns` chart v1.15.0 using webhook provider
  - Webhook: `ghcr.io/mwalbeck/external-dns-pihole-webhook:1` (pihole v5 API compatible)
  - Pihole server: `http://pihole.pihole.svc.cluster.local:8081`
  - Password from `pihole-admin-secret` (via 1Password)
  - `--label-filter=pihole-dns-enabled=true` — separate from cloudflare instance
  - `txtPrefix: "_extdns-local."`, `managedRecordTypes: [A]`, `policy: sync`
  - `txtOwnerId` and `domainFilters` set per-cluster via overlay patches

- `infra/base/external-dns/pihole-admin-onepassword.yaml`
  - `OnePasswordItem` → `pihole-admin-secret` in `external-dns` namespace
  - 1Password path: `vaults/Homelab/items/pihole.local.abbottland.io (bananapi)`

### Modified Files

**Kustomization — base:**
- `infra/base/external-dns/kustomization.yaml` — added 2 new resources

**Kustomization — cluster overlays:**
- `infra/prod-gen2/external-dns/kustomization.yaml`
  - Patch: `txtOwnerId: prod-gen2-pihole`, `domainFilters: ["local.abbottland.io"]`
- `infra/non-prod-gen2/external-dns/kustomization.yaml`
  - Patch: `txtOwnerId: non-prod-gen2-pihole`, `domainFilters: ["local.non-prod.abbottland.io"]`

**HTTPRoutes — label + annotation added to all HTTPS routes:**
- `applications/base/haproxy/httproute.yaml`
- `applications/base/asustor/httproute.yaml`
- `applications/base/proxmox/httproute.yaml`
- `applications/base/harbor/httproute.yaml`
- `applications/base/pihole/httproute.yaml`
- `applications/base/podinfo/podinfo-httproute.yaml`
- `infra/base/kube-prometheus-stack/grafana-httproute.yaml`
- `infra/base/kube-prometheus-stack/prometheus-httproute.yaml`
- `infra/base/onepassword/op-connect-httproute.yaml`
- `infra/prod-gen2/longhorn/longhorn-httproute.yaml`
- `applications/base/dashy/templates/httproute.yaml` (Helm chart template — HTTPS route only)

Each got:
```yaml
labels:
  pihole-dns-enabled: "true"
annotations:
  external-dns.alpha.kubernetes.io/target: "192.168.6.28"
```

### Key Decisions

- **Target IP `192.168.6.28` for both clusters** — HAProxy at that IP fronts both prod-gen2
  and non-prod-gen2; no separate non-prod IP needed.
- **flux-web HTTP→HTTPS redirect route skipped** — not an HTTPS backend, no DNS record needed.
- **Dashy via chart template** — since dashy HTTPRoute is Helm-generated, label/annotation
  added directly to `applications/base/dashy/templates/httproute.yaml` (HTTPS route only;
  HTTP→HTTPS redirect route left clean).

## Remaining Manual Steps

1. Flux reconcile / wait for `external-dns-pihole` HelmRelease to deploy
2. Verify A records created: `nslookup grafana.local.abbottland.io 192.168.4.144`
3. Remove `*.local.abbottland.io` wildcard from pihole local DNS settings
4. Re-verify services still resolve
5. Confirm `api.github.com.local.abbottland.io → NXDOMAIN`
