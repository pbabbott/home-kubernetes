# Local DNS Migration: Wildcard → Per-Service Records via External-DNS + Pihole

## Problem

`*.local.abbottland.io → 192.168.6.28` is a wildcard record in pihole.
This causes pods with default `ndots:5` to resolve external names like
`api.github.com` and `github.com` via the search-domain chain:

```
api.github.com.local.abbottland.io → 192.168.6.28  ← wrong
```

The ingress at 192.168.6.28 responds with a different TLS cert, breaking
outbound HTTPS/SSH from any pod that hasn't been patched with `ndots:1` or `ndots:2`.

## Goal

Replace the wildcard with per-service A records managed by external-dns
using the pihole provider. Any unknown `*.local.abbottland.io` name returns
NXDOMAIN, so the DNS search chain falls through to the correct public address.

```
api.github.com.local.abbottland.io → NXDOMAIN  ✓
api.github.com                     → 140.82.113.5 ✓
```

## Architecture

| Zone | Provider | Manager | Record type |
|------|----------|---------|-------------|
| `*.abbottland.io` | Cloudflare | existing `external-dns` | CNAME (proxied) |
| `*.local.abbottland.io` | Pihole | new `external-dns-pihole` | A → 192.168.6.28 |

The two external-dns instances use different label selectors so they don't
step on each other:

- Cloudflare: `--label-filter=external-dns-enabled=true`
- Pihole:     `--label-filter=pihole-dns-enabled=true`

## Pihole Details

| Field | Value |
|-------|-------|
| Service | `pihole.pihole.svc.cluster.local:8081` |
| Real host | `192.168.4.144:8081` (via EndpointSlice) |
| Version | **v5.18.2** (Docker tag 2024.05.0, FTL v5.25.2, Web v5.21) |
| Admin password | 1Password — retrieve via `OnePasswordItem` CRD |

## New Files to Create

### `infra/base/external-dns/external-dns-pihole-helmrelease.yaml`

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: external-dns-pihole
  namespace: flux-system
spec:
  interval: 4h
  targetNamespace: external-dns
  releaseName: external-dns-pihole
  dependsOn:
    - name: op-connect
      namespace: flux-system
  chart:
    spec:
      chart: external-dns
      version: "1.15.0"
      sourceRef:
        kind: HelmRepository
        name: external-dns
        namespace: flux-system
      interval: 12h
  values:
    provider:
      name: webhook
      webhook:
        image:
          repository: ghcr.io/mwalbeck/external-dns-pihole-webhook
          tag: "1"   # v1.x supports pihole v5 API
        env:
          - name: PIHOLE_SERVER
            value: "http://pihole.pihole.svc.cluster.local:8081"
          - name: PIHOLE_PASSWORD
            valueFrom:
              secretKeyRef:
                name: pihole-admin-secret
                key: password
    sources:
      - gateway-httproute
    policy: sync
    registry: txt
    txtPrefix: "_extdns-local."
    # txtOwnerId set per cluster via overlay patch
    domainFilters:
      - local.abbottland.io      # overridden per cluster
    managedRecordTypes:
      - A
    extraArgs:
      - --label-filter=pihole-dns-enabled=true
```

### `infra/base/external-dns/pihole-admin-onepassword.yaml`

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: pihole-admin-secret
  namespace: external-dns
spec:
  itemPath: "vaults/Homelab/items/pihole.local.abbottland.io (bananapi)"
```

### Per-cluster overlay patches

**`infra/prod-gen2/external-dns/kustomization.yaml`** — add patch:
```yaml
- op: add
  path: /spec/values/txtOwnerId
  value: prod-gen2-pihole
- op: replace
  path: /spec/values/domainFilters
  value: ["local.abbottland.io"]
```
target: `HelmRelease` name `external-dns-pihole`

**`infra/non-prod-gen2/external-dns/kustomization.yaml`** — same pattern,
domain `local.non-prod.abbottland.io`.

## Files to Modify — Add Pihole Label + Target Annotation

Add to every **HTTPS** local HTTPRoute (not the http-to-https redirects):

```yaml
metadata:
  labels:
    pihole-dns-enabled: "true"
  annotations:
    external-dns.alpha.kubernetes.io/target: "192.168.6.28"
```

### HTTPS HTTPRoutes needing labels

| File | Hostname (base default) |
|------|------------------------|
| `applications/base/haproxy/httproute.yaml` | `haproxy.local.*.abbottland.io` |
| `applications/base/asustor/httproute.yaml` | `asustor.local.*.abbottland.io` |
| `applications/base/proxmox/httproute.yaml` | `proxmox.local.*.abbottland.io` |
| `applications/base/harbor/httproute.yaml` | `harbor.local.*.abbottland.io` |
| `applications/base/pihole/httproute.yaml` | `pihole.local.*.abbottland.io` |
| `applications/base/podinfo/podinfo-httproute.yaml` | `podinfo.local.*.abbottland.io` |
| `infra/base/kube-prometheus-stack/grafana-httproute.yaml` | `grafana.local.*.abbottland.io` |
| `infra/base/kube-prometheus-stack/prometheus-httproute.yaml` | `prometheus.local.*.abbottland.io` |
| `infra/base/onepassword/op-connect-httproute.yaml` | `op-connect.local.abbottland.io` |
| `infra/prod-gen2/longhorn/longhorn-httproute.yaml` | `longhorn.local.abbottland.io` |
| `applications/base/flux-gitops/flux-web-http-to-https-httproute.yaml` | check — may be redirect only |

> **Note:** `dashy` HTTPRoute is generated by a HelmRelease. Add the label
> via `podLabels` or a Helm values override in its HelmRelease.

> **Note:** The target IP `192.168.6.28` is the prod-gen2 ingress.
> Non-prod will need a different target — confirm the non-prod ingress IP.

## Webhook Image

**Confirmed: pihole v5.18.2 → use `ghcr.io/mwalbeck/external-dns-pihole-webhook:1`**

The `mwalbeck` webhook uses pihole's v5 `/admin/api.php` endpoint.
Pin to tag `1` (latest v1.x) which tracks the v5-compatible major version.
If pihole is ever upgraded to v6, a different webhook will be required as
v6 completely replaced the auth and DNS API.

## Manual Steps (one-time)

1. Confirm non-prod ingress IP (equivalent of 192.168.6.28 for non-prod cluster).
3. After external-dns-pihole is running and records are created, **remove**
   the `*.local.abbottland.io` wildcard from pihole's local DNS settings.
   External-dns `policy: sync` will maintain the individual records going forward.

## Rollout Order

1. Create 1Password secret + external-dns-pihole HelmRelease
2. Add labels/annotations to HTTPRoutes (records get created in pihole)
3. Verify each service resolves correctly: `nslookup grafana.local.abbottland.io 192.168.4.144`
4. Remove pihole wildcard
5. Re-verify services still resolve
6. Verify `api.github.com.local.abbottland.io` returns NXDOMAIN
