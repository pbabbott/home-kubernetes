# Session: nas.local.abbottland.io DNS via DNSEndpoint

**Date:** 2026-05-16  
**Commit:** `934a6eb`

## What we did

Added `nas.local.abbottland.io A 192.168.4.124` as a direct Pihole DNS record for the Asustor NAS, without routing through any HTTPRoute/ingress.

## Approach

Used external-dns `DNSEndpoint` CRD source rather than an HTTPRoute. Reasons:
- User wanted `nas.` to resolve directly to NAS IP — no proxy/ingress hop
- HTTPRoute would have routed traffic through `istio-ingress` first

## Files changed

| File | Change |
|------|--------|
| `crds/base/external-dns/dnsendpoint-crd.yaml` | Vendored DNSEndpoint CRD from external-dns chart 1.15.0 |
| `crds/base/external-dns/kustomization.yaml` | New CRD kustomization |
| `crds/prod-gen2/kustomization.yaml` | Added `../base/external-dns` |
| `crds/non-prod-gen2/kustomization.yaml` | Added `../base/external-dns` |
| `infra/base/external-dns/external-dns-pihole-helmrelease.yaml` | Added `crd` to sources, `crds.create: false` |
| `applications/prod-gen2/asustor/nas-dnsendpoint.yaml` | New `DNSEndpoint` → `nas.local.abbottland.io A 192.168.4.124` |
| `applications/prod-gen2/asustor/kustomization.yaml` | Added DNSEndpoint resource |

## Key decisions

- CRDs go in `crds/` folder (user convention) — not Helm-managed
- `crds.create: false` in HelmRelease prevents chart from managing the CRD
- `DNSEndpoint` needs label `pihole-dns-enabled: "true"` to pass external-dns label filter
- Kept `asustor.local.abbottland.io` HTTPRoute unchanged — `nas.` is a separate alias pointing directly to `192.168.4.124`

## Reconciliation

- `crds-ks` ✅ applied, CRD configured
- `external-dns-pihole` HelmRelease ✅ upgraded to v5 with `crd` source active
- `apps-ks` ✅ applied `934a6eb`, DNSEndpoint deployed
