# Session: Remove Public URLs from non-prod-gen2

**Date:** 2026-05-16

## What we worked on

Continuation of a previous session that fixed Cloudflare DNS record creation for `non-prod.abbottland.io`. This session identified a deeper problem and made a architectural decision to remove the public surface entirely.

## Problem

After getting `podinfo.non-prod.abbottland.io` to appear in Cloudflare (previous session), navigating to `https://podinfo.non-prod.abbottland.io/` returned `ERR_SSL_VERSION_OR_CIPHER_MISMATCH`. Root cause: Cloudflare Universal SSL covers `*.abbottland.io` but NOT `*.non-prod.abbottland.io` (two levels deep). Disabling the Cloudflare proxy (orange cloud) fixes SSL but exposes the home public IP — unacceptable.

## Decision

Remove the entire public surface from non-prod-gen2. Non-prod is LAN-only going forward. Prod-gen2 retains all public infrastructure.

## Changes Made

### Commits

- `ebbc417` — `feat(non-prod-gen2): remove all public URLs from non-prod cluster` — initial attempt using `$patch: delete` in kustomize `patches:` list (did not work)
- `e71376b` — `fix(non-prod-gen2): use explicit resource lists to exclude public infra` — correct fix using explicit per-file resource lists

### What was removed (non-prod-gen2 only)

| Resource | Namespace |
|---|---|
| `cloudflare-ddns` Deployment | cert-manager |
| `external-dns` HelmRelease (Cloudflare) | flux-system |
| `cloudflare-api-token-secret` OnePasswordItem | external-dns |
| `istio-ingress-public` Gateway | istio-system |
| `podinfo-public` HTTPRoute | podinfo |
| `podinfo-public-http-to-https` HTTPRoute | podinfo |
| `podinfoPublic` dashy link | dashy HelmRelease values |
| `podinfo.non-prod.abbottland.io` CNAME | Cloudflare DNS (manual delete) |

### What was kept

- `cloudflare-api-token-secret` Secret in `cert-manager` namespace — still needed for DNS-01 challenges that issue `wildcard-local-non-prod-tls`
- All LAN infrastructure: `istio-ingress` Gateway, pihole external-dns, LAN HTTPRoutes

### Files modified

- `infra/non-prod-gen2/cert-manager/kustomization.yaml` — explicit file list, omits `cloudflare-ddns-deployment.yaml`
- `infra/non-prod-gen2/external-dns/kustomization.yaml` — explicit file list, omits cloudflare HR and OPI; keeps pihole HR + domainFilter patch
- `infra/non-prod-gen2/istio/kustomization.yaml` — explicit file list, omits `istio-ingress-public-gateway-api.yaml`; keeps LAN listener patches
- `applications/non-prod-gen2/podinfo/kustomization.yaml` — explicit file list, omits public HTTPRoute files; keeps LAN hostname patches
- `applications/non-prod-gen2/dashy/helmrelease.yaml` — removed `podinfoPublic` URL

## Key Finding: `$patch: delete` broken in kustomize v5.8.1

**Problem:** `$patch: delete` in kustomize `patches:` list (new format) does NOT remove resources from build output in v5.8.1. Tried both:
- `patches:` with inline YAML containing `$patch: delete` in metadata
- `patchesStrategicMerge:` with `$patch: delete` in metadata

Neither removed the matched resource from `kubectl kustomize` output.

**Workaround:** Explicit per-file resource references instead of referencing the base directory. Example:
```yaml
resources:
  - ../../base/cert-manager/namespace.yaml
  - ../../base/cert-manager/cert-manager-helm-release.yaml
  # cloudflare-ddns-deployment.yaml intentionally omitted
```

**Note:** `kubectl kustomize` locally rejects `../../` file references with a security error (`file is not in or below`), but Flux's kustomize-controller runs with `LoadRestrictionsNone` so cross-directory file references work in cluster. Verify with: `kubectl kustomize --load-restrictor=LoadRestrictionsNone <path>`.

## Verification

Post-deploy checks confirmed all public resources pruned and LAN resources intact:
```
NotFound: cloudflare-ddns Deployment, external-dns HelmRelease,
          cloudflare-api-token-secret OPI (external-dns ns),
          istio-ingress-public Gateway, podinfo-public HTTPRoutes

Present:  cloudflare-api-token-secret Secret (cert-manager ns),
          istio-ingress Gateway, external-dns-pihole HelmRelease,
          podinfo + podinfo-http-to-https HTTPRoutes (LAN)
```
