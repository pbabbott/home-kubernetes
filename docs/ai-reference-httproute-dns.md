# HTTPRoute DNS: Cloudflare vs Pihole

Two external-dns instances manage DNS for gen2 clusters. Each handles a different domain and requires different HTTPRoute configuration.

## Domain Split

| Provider | Domain pattern | Access | Target |
|----------|---------------|--------|--------|
| Cloudflare | `*.non-prod.abbottland.io` | Public internet | `abbottland.io` (CNAME, Cloudflare-proxied) |
| Pihole | `*.local.non-prod.abbottland.io` | LAN only | `192.168.6.28` (A record, direct to gateway) |

The `local.` subdomain prefix distinguishes internal from public. Internal routes use `istio-ingress`; public routes use `istio-ingress-public`.

## Gateways

Two Gateways in `istio-system`, both backed by the same `istio-system-istio-ingress` Service:

**`istio-ingress`** — internal traffic, annotation `192.168.6.28`
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
  annotations:
    external-dns.alpha.kubernetes.io/target: "192.168.6.28"  # informational only — actual target comes from Gateway annotation
spec:
  parentRefs:
    - name: istio-ingress
      namespace: istio-system
      sectionName: https                # internal listener
  hostnames:
    - myapp.local.non-prod.abbottland.io
```

Result in pihole: `myapp.local.non-prod.abbottland.io A 192.168.6.28`

## Cloudflare HTTPRoute (public)

```yaml
metadata:
  labels:
    external-dns-enabled: "true"        # picked up by external-dns (cloudflare) instance
  annotations:
    external-dns.alpha.kubernetes.io/target: abbottland.io
    external-dns.alpha.kubernetes.io/cloudflare-proxied: "true"
spec:
  parentRefs:
    - name: istio-ingress-public          # public Gateway — annotation abbottland.io
      namespace: istio-system
      sectionName: https-public
  hostnames:
    - myapp.non-prod.abbottland.io
```

Result in Cloudflare: `myapp.non-prod.abbottland.io CNAME abbottland.io` (proxied)

## How external-dns Picks Up Routes

- `external-dns-pihole` watches routes with label `pihole-dns-enabled=true`, domain filter `local.non-prod.abbottland.io`
- `external-dns` (cloudflare) watches routes with label `external-dns-enabled=true`, domain filter `non-prod.abbottland.io`
- Target comes from the **Gateway annotation** that the HTTPRoute's `parentRef` points to — NOT the HTTPRoute annotation (ignored by v0.15.x). Routes referencing `istio-ingress` resolve to `192.168.6.28` (A); routes referencing `istio-ingress-public` resolve to `abbottland.io` (CNAME).
- DNS records appear within ~1 minute (sync interval)

## Adding a New Service

**Internal only (pihole):** add `pihole-dns-enabled: "true"` label, parent `istio-ingress` `sectionName: https`, hostname `*.local.<cluster-domain>.abbottland.io`.

**Public (cloudflare):** add `external-dns-enabled: "true"` label, annotations `external-dns.alpha.kubernetes.io/target: abbottland.io` + `cloudflare-proxied: "true"`, parent **`istio-ingress-public`** `sectionName: https-public`, hostname `*.<cluster-domain>.abbottland.io`.

**Both:** create two separate HTTPRoutes — one per Gateway.

## Hostname Conventions by Cluster

| Cluster | Internal domain | Public domain |
|---------|----------------|---------------|
| non-prod-gen2 | `*.local.non-prod.abbottland.io` | `*.non-prod.abbottland.io` |
| prod-gen2 | `*.local.abbottland.io` | `*.abbottland.io` |

Cluster-specific hostnames are usually patched via kustomize overlay (base uses placeholder, overlay patches the actual hostname).

## Gen3 staging patterns (Phase 6, gen2 -> gen3 moves)

Moving an app with a hostname identical to gen2's: stage it on gen3 UNLABELLED, test with `curl --resolve <host>:443:192.168.6.29`, then flip in one merge (remove from gen2 + add the label on gen3). Never label a gen3 route whose hostname gen2 still serves.

- Kustomize apps: gen3 overlay references the base DIRECTORY and strips the label and `.28` annotation with JSON patches.
- Helm charts that hardcode the label (e.g. `applications/base/dashy`): add a HelmRelease `postRenderers` kustomize JSON patch removing `/metadata/labels/pihole-dns-enabled`; delete it in the flip commit.
- Charts that add the label via a postRenderer (flux-operator-mcp): remove `/spec/postRenderers` while staging, restore on the flip.
- Gen3's flux-operator is Ansible-installed (no HelmRelease), so its UI route is a standalone HTTPRoute in `clusters/prod-gen3/flux-gitops/` (backend `flux-operator:9080`); a base HelmRelease `dependsOn: flux-operator` must be patched out.
- The record target comes from the Gateway annotation (gen3 = 192.168.6.29), not the route's `.28` annotation. Gen3 external-dns is `upsert-only`: if the record stays `.28` after ~2 cycles, delete it via the Pi-hole API and gen3 recreates it (see `ai-reference-pihole-api.md`).
