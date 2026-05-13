# Session: external-dns pihole A records fix

**Date:** 2026-05-13  
**Branch:** main  
**Commits:** `29824b5`, `69d3483`, `e511a8a`, `0ff3536`

## Goal

Get external-dns-pihole running and creating correct A records (`192.168.6.28`) for `*.local.non-prod.abbottland.io` services in pihole.

## Problems Found and Fixed

### 1. 1Password secret not created (`pihole-admin-secret`)
- `OnePasswordItem` CRD existed but op-connect operator had stale "not found" status
- Item was added to Homelab vault during session but operator didn't re-reconcile
- **Fix:** Force reconcile via `kubectl annotate` with a timestamp annotation

### 2. Secret key mismatch
- HelmRelease referenced `key: password` but 1Password field is named `pw`
- **Fix:** `infra/base/external-dns/external-dns-pihole-helmrelease.yaml` — change `key: password` → `key: pw`
- **Commit:** `29824b5`

### 3. Records created as CNAME → `abbottland.io` (wrong)
- **Root cause:** `gateway-httproute` source uses Gateway-level annotation for target, NOT HTTPRoute-level annotation
- Gateway had `external-dns.alpha.kubernetes.io/target: abbottland.io` → all records became CNAME to `abbottland.io`
- HTTPRoute annotations `192.168.6.28` were being silently ignored
- Cloudflare external-dns uses HTTPRoute annotation (its routes have `abbottland.io` inline)
- Pihole external-dns uses Gateway annotation/status (its HTTPRoute annotation was ignored)
- **Fix:** Change Gateway annotation from `abbottland.io` to `192.168.6.28`
- **File:** `infra/base/istio/istio-ingress-gateway-api.yaml`
- **Commit:** `e511a8a` (after `69d3483` which incorrectly removed annotation entirely)

### 4. `registry: txt` caused no-op syncs
- Pihole doesn't support TXT records
- `registry: txt` requires TXT ownership records to track what external-dns manages
- Without TXT records, external-dns considered ALL pihole records "unowned" → skipped syncing
- After Gateway annotation set to `192.168.6.28`, external-dns still said "All records already up to date"
- **Fix:** Switch to `registry: noop` — no ownership tracking, manages all records in `domainFilters` directly
- Removed `txtPrefix` and `txtOwnerId` overlay patch (not needed with noop)
- **Files:** `infra/base/external-dns/external-dns-pihole-helmrelease.yaml`, `infra/non-prod-gen2/external-dns/kustomization.yaml`
- **Commit:** `0ff3536`

## Final State

External-dns-pihole:
- Running, `registry: noop`, `policy: sync`
- Gateway annotation `192.168.6.28` → creates A records
- Deleted 9 stale CNAME records, added 9 A records to `192.168.6.28`
- Stable: "All records are already up to date" on subsequent syncs

Pihole A records (from external-dns):
- `grafana.local.non-prod.abbottland.io` → `192.168.6.28`
- `prometheus.local.non-prod.abbottland.io` → `192.168.6.28`
- `op-connect.local.non-prod.abbottland.io` → `192.168.6.28`
- `harbor.local.non-prod.abbottland.io` → `192.168.6.28`
- `haproxy.local.non-prod.abbottland.io` → `192.168.6.28`
- `asustor.local.non-prod.abbottland.io` → `192.168.6.28`
- `proxmox.local.non-prod.abbottland.io` → `192.168.6.28`
- `podinfo.local.non-prod.abbottland.io` → `192.168.6.28`
- `pihole.local.non-prod.abbottland.io` → `192.168.6.28`

Cloudflare external-dns: unaffected (uses HTTPRoute annotation `abbottland.io` directly).

## Key Learnings

- `gateway-httproute` source in external-dns v0.15.0: target priority is **Gateway annotation** > Gateway status address. HTTPRoute-level target annotations are NOT used for target resolution.
- `registry: txt` + pihole = broken sync loop. Always use `registry: noop` for pihole.
- Pihole `customdns` API returns A records. `customcname` API returns CNAME records. They are separate endpoints.
- Pihole API auth = `SHA256(SHA256(password))` as the `auth` query param.
