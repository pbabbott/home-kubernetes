# 2026-05-22 — Nonprod Gen2 Cluster Rebuild: Flux Recovery

## Context

User rebuilt the nonprod-gen2 cluster and needed all Flux resources brought to healthy state.
Several cascading bootstrap issues were discovered and fixed across both nonprod-gen2 and prod-gen2.

## Issues Fixed

### 1. Longhorn CRD Bootstrap Deadlock (both clusters)

`infra-ks` contained `longhorn-recurring-job.yaml` which uses the `longhorn.io/v1beta2` CRD.
Flux dry-runs all resources before applying — dry-run failed because Longhorn wasn't installed yet,
so Longhorn could never install. Classic chicken-and-egg.

**Fix:** Added pre-rendered Longhorn 1.9.2 CRDs to `crds/base/longhorn/` (rendered via `helm template`)
and included in both `crds/non-prod-gen2/` and `crds/prod-gen2/` kustomizations. CRDs now exist
before infra-ks applies, so dry-run passes.

Files changed:
- `crds/base/longhorn/longhorn-crds.yaml` (new, 22 CRDs)
- `crds/base/longhorn/kustomization.yaml` (new)
- `crds/non-prod-gen2/kustomization.yaml`
- `crds/prod-gen2/kustomization.yaml`

### 2. op-connect SealedSecret Decryption Failure (nonprod-gen2)

Fresh cluster generates new Sealed Secrets controller key — old ciphertext not portable.
`op-credentials` SealedSecret couldn't decrypt, so op-connect pods failed with
`CreateContainerConfigError: secret "op-credentials" not found`.

**Fix:** Re-ran `scripts/op-connect-secret.sh` for both clusters with fresh credentials files
from 1Password. Re-sealed and committed new ciphertext for both nonprod-gen2 and prod-gen2.

Files changed:
- `infra/non-prod-gen2/onepassword/op-credentials.yaml`
- `infra/prod-gen2/onepassword/op-credentials.yaml`

Reference plan created: `docs/plans/nonprod-gen2-cluster-rebuild-op-connect.md`

### 3. Pihole Circular Dependency Breaking infra-ks (both clusters)

`external-dns-pihole` in infra-ks needed the `pihole` Service to connect to the physical pihole device.
Pihole Service/EndpointSlice lived in `applications/`, gated by `apps-ks`, which `dependsOn: infra-ks`.
Result: infra-ks blocked on external-dns-pihole → external-dns-pihole blocked on pihole → pihole blocked on infra-ks.

**Fix:** Moved pihole from `applications/` to `infra/`. Pihole is just a Namespace + Service +
EndpointSlice pointing to a physical device at `192.168.4.144` — semantically infra, not an app.

Files moved:
- `applications/base/pihole/` → `infra/base/pihole/`
- `applications/non-prod-gen2/pihole/` → `infra/non-prod-gen2/pihole/`
- `applications/prod-gen2/pihole/` → `infra/prod-gen2/pihole/`
- Updated `infra/non-prod-gen2/kustomization.yaml` and `infra/prod-gen2/kustomization.yaml`
- Removed pihole from `applications/non-prod-gen2/kustomization.yaml` and `applications/prod-gen2/kustomization.yaml`

### 4. Longhorn PDB Not Applied (both clusters)

`PodDisruptionBudget/longhorn-system/longhorn-instance-manager` defined in `infra/base/longhorn/`
was never created on either cluster (prior infra-ks failures prevented apply from completing).
Flux health check timed out waiting for it.

**Fix:** Applied PDB directly on both clusters to unblock infra-ks. Flux will manage it going forward.

### 5. Cloudflare API Token Expired (prod-gen2)

`external-dns` Cloudflare provider failing with `Invalid access token (9109)`.
Token in 1Password item `cloudflare_api_token` (Homelab vault) expired 2026-05-18.
Confirmed via `curl https://api.cloudflare.com/client/v4/user/tokens/verify`.

**Fix:** User rotated token in Cloudflare (Edit Zone DNS, abbottland.io) and updated 1Password.
Force-reconciled OnePasswordItem in both `external-dns` and `cert-manager` namespaces.

## Multiple Stale HelmRelease Failures

Throughout the session, many HelmReleases had stale `Failed` status from prior failed installs
(timed out waiting for pods that eventually came up). Pattern: `flux suspend` + `flux resume`
clears the stale state and triggers a fresh reconcile.

Affected releases cleared: `op-connect`, `external-dns-pihole`, `external-dns` (both clusters).

## Final State

| Cluster | crds-ks | infra-ks | apps-ks |
|---------|---------|---------|---------|
| nonprod-gen2 | ✅ | ✅ | reconciling at session end |
| prod-gen2 | ✅ | ✅ | reconciling at session end |
