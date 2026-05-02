# Session: 2026-05-02 — external-dns setup + harbor fixes

## external-dns for gen2 clusters

Ported gen1 external-dns (bitnami/ingress) to gen2 clusters using Gateway API (HTTPRoute) as the source.

**Chart**: migrated to `kubernetes-sigs/external-dns` v1.15.0 (gen1 used bitnami which had a TODO to migrate).

**New files:**
- `infra/base/external-dns/` — namespace, HelmRepository, 1Password CF token secret, HelmRelease
- `infra/non-prod-gen2/external-dns/kustomization.yaml` — patches `txtOwnerId: non-prod-gen2`, `domainFilters: [non-prod.abbottland.io]`
- `infra/prod-gen2/external-dns/kustomization.yaml` — patches `txtOwnerId: prod-gen2`, `domainFilters: [abbottland.io]`

**Key config decisions:**
- `sources: [gateway-httproute]` — reads hostnames from HTTPRoute `spec.hostnames`
- `--label-filter=external-dns-enabled=true` — explicit opt-in, keeps `*.local.*` routes private
- `--cloudflare-proxied` — orange cloud on by default; per-route annotation `cloudflare-proxied: "false"` opts out
- `txtPrefix: _extdns.` — avoids conflicts with apex TXT records
- Per-cluster `txtOwnerId` prevents two clusters fighting over the same `abbottland.io` zone

**Public Gateway listener added** (`infra/base/istio/istio-ingress-gateway-api.yaml`):
- New `https-public` listener, base hostname `*.abbottland.io` / secret `wildcard-public-tls`
- cert-manager gateway-shim auto-issues wildcard cert (Gateway already has `cert-manager.io/cluster-issuer` annotation)
- non-prod overlay patches to `*.non-prod.abbottland.io` / `wildcard-public-non-prod-tls`
- Prod overlay leaves base values unchanged

**Podinfo public routes updated** (first gen2 workload with public DNS):
- `podinfo-public-httproute.yaml`: `sectionName: https` → `sectionName: https-public` (critical fix — old listener only matches `*.local.*`)
- Both public routes: added `external-dns-enabled: "true"` label + `target: abbottland.io` + `cloudflare-proxied: "true"` annotations

**Pattern for future public HTTPRoutes:**
```yaml
metadata:
  labels:
    external-dns-enabled: "true"
  annotations:
    external-dns.alpha.kubernetes.io/target: abbottland.io
    external-dns.alpha.kubernetes.io/cloudflare-proxied: "true"
spec:
  parentRefs:
    - name: istio-ingress
      namespace: istio-system
      sectionName: https-public   # <-- not "https" (that's local only)
```

**Commits:** `d7be2ea` (external-dns + public listener + podinfo), `3e76e62` (auth policy comments)

---

## harbor fix — updateStrategy + RWO cross-node deadlock

**Root cause:** harbor chart uses a single top-level `updateStrategy` key for all RWO-backed deployments (jobservice, registry). The helmrelease had `registry.updateStrategy` and `jobservice.updateStrategy` (nested) which the chart silently ignores, defaulting to `RollingUpdate`.

With RollingUpdate:
- Rolling upgrade creates new pod before terminating old
- If new pod scheduled to different node, RWO PVC (Longhorn) can't attach (still held by old pod on original node)
- Classic cross-node deadlock: new pod never ready → old pod never terminates → stuck forever

**Fix:** `applications/base/harbor/helmrelease.yaml` — moved `updateStrategy.type: Recreate` to root level, removed nested per-component keys.

**Recovery steps needed** (rollback cycle had reintroduced `rollingUpdate` fields on live deployments):
1. `kubectl patch deployment harbor-{jobservice,registry}` to remove `spec.strategy.rollingUpdate` field (`type: Recreate` alone is rejected if `rollingUpdate` sub-fields still present)
2. For prod: also manually scaled old RS to 0 to release PVC lock, allowing new pod to attach
3. Reset stalled HelmRelease: `kubectl patch helmrelease harbor --subresource=status` to clear `upgradeFailures` + `conditions`, then annotate `reconcile.fluxcd.io/requestedAt`

**Result:** both clusters upgraded cleanly (nonprod v7, prod v9), strategy now Recreate.

**Commit:** `c5c7153`

---

## Verification status at session end

| Resource | nonprod-gen2 | prod-gen2 |
|---|---|---|
| crds-ks | ✅ | ✅ |
| infra-ks | ✅ | ✅ |
| apps-ks | ✅ | ✅ |
| external-dns HelmRelease | ✅ v1.15.0 | ✅ v1.15.0 |
| harbor HelmRelease | ✅ | ✅ |
| public Gateway listener | added | added (base defaults) |
| podinfo public DNS | pending cert + DNS propagation | pending cert + DNS propagation |
