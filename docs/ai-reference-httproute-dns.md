# HTTPRoute DNS: Cloudflare vs Pihole

Two external-dns instances manage DNS on the gen3 cluster (`prod-gen3`). Each handles a different domain and requires different HTTPRoute configuration.

## Domain Split

| Provider | Domain pattern | Access | Target |
|----------|---------------|--------|--------|
| Cloudflare | `*.abbottland.io` | Public internet | `abbottland.io` (CNAME, Cloudflare-proxied) |
| Pihole | `*.local.abbottland.io` | LAN only | `192.168.6.29` (A record, gen3 HAProxy) |

The `local.` subdomain prefix distinguishes internal from public. Internal routes use `istio-ingress`; public routes use `istio-ingress-public`.

## Gateways

Two Gateways in `istio-system`, both backed by the same `istio-system-istio-ingress` Service:

**`istio-ingress`** — internal traffic, annotation `192.168.6.29`
```
http         → port 80, no hostname filter
https        → *.local.abbottland.io    (internal TLS, wildcard-local-tls cert)
```

**`istio-ingress-public`** — public/Cloudflare traffic, annotation `abbottland.io`
```
https-public → *.abbottland.io          (public TLS, wildcard-public-tls cert)
```

**Why two Gateways:** external-dns v0.15.x `gateway-httproute` source reads the DNS target exclusively from the Gateway annotation — HTTPRoute-level `external-dns.alpha.kubernetes.io/target` annotations are ignored. Two Gateways with different annotations let each external-dns instance resolve the correct target.

## Pihole HTTPRoute (internal/local)

```yaml
metadata:
  labels:
    pihole-dns-enabled: "true"          # picked up by external-dns-pihole instance
spec:
  parentRefs:
    - name: istio-ingress
      namespace: istio-system
      sectionName: https                # internal listener
  hostnames:
    - myapp.local.abbottland.io
```

Result in pihole: `myapp.local.abbottland.io A 192.168.6.29`. Do NOT add a per-route `target` annotation: it is ignored (target comes from the Gateway).

## Cloudflare HTTPRoute (public)

```yaml
metadata:
  labels:
    external-dns-enabled: "true"        # picked up by external-dns (cloudflare) instance
  annotations:
    external-dns.alpha.kubernetes.io/cloudflare-proxied: "true"   # still needed; the target comes from the Gateway
spec:
  parentRefs:
    - name: istio-ingress-public          # public Gateway — annotation abbottland.io
      namespace: istio-system
      sectionName: https-public
  hostnames:
    - myapp.abbottland.io
```

Result in Cloudflare: `myapp.abbottland.io CNAME abbottland.io` (proxied)

## How external-dns Picks Up Routes

- `external-dns-pihole` watches routes with label `pihole-dns-enabled=true`, domain filter `local.abbottland.io`
- `external-dns` (cloudflare) watches routes with label `external-dns-enabled=true`, domain filter `abbottland.io`
- Target comes from the **Gateway annotation** that the HTTPRoute's `parentRef` points to — NOT the HTTPRoute annotation (ignored by v0.15.x). Routes referencing `istio-ingress` resolve to `192.168.6.29` (A); routes referencing `istio-ingress-public` resolve to `abbottland.io` (CNAME).
- DNS records appear within ~1 minute (sync interval)

## Adding a New Service

**Internal only (pihole):** add `pihole-dns-enabled: "true"` label, parent `istio-ingress` `sectionName: https`, hostname `<app>.local.abbottland.io`.

**Public (cloudflare):** add `external-dns-enabled: "true"` label, annotation `cloudflare-proxied: "true"`, parent **`istio-ingress-public`** `sectionName: https-public`, hostname `<app>.abbottland.io`.

**Both:** create two separate HTTPRoutes — one per Gateway.

## Hostnames

Internal: `<app>.local.abbottland.io`. Public: `<app>.abbottland.io`. Overlays patch hostnames only when base and cluster differ.

## Gen3 route patterns

- A new route is only given DNS by adding the label on purpose. If a hostname is served by another cluster/backend, stage unlabelled and test with `curl --resolve <host>:443:192.168.6.29`, then flip.
- Helm charts that hardcode the label (e.g. `apps/base/platform/dashy`): use a HelmRelease `postRenderers` kustomize JSON patch removing `/metadata/labels/pihole-dns-enabled` while staging.
- Gen3's flux-operator is Ansible-installed (no HelmRelease), so its UI route is a standalone HTTPRoute in `clusters/prod-gen3/flux-gitops/` (backend `flux-operator:9080`).
- Gen3 Pi-hole external-dns is `sync` + `registry: noop` (see `ai-reference-external-dns-pihole.md`): a record with no labelled route or `DNSEndpoint` is deleted. If a record stays wrong after ~2 cycles, delete it via the Pi-hole API (see `ai-reference-pihole-api.md`) and external-dns recreates it.
- Routes carry no `target` annotation (it is ignored); do not add one.
