# HTTPRoute DNS: Cloudflare vs Pihole

Two external-dns instances manage DNS for gen2 clusters. Each handles a different domain and requires different HTTPRoute configuration.

## Domain Split

| Provider | Domain pattern | Access | Target |
|----------|---------------|--------|--------|
| Cloudflare | `*.non-prod.abbottland.io` | Public internet | `abbottland.io` (CNAME, Cloudflare-proxied) |
| Pihole | `*.local.non-prod.abbottland.io` | LAN only | `192.168.6.28` (A record, direct to gateway) |

The `local.` subdomain prefix distinguishes internal from public. Both use the same Istio gateway (`istio-ingress` in `istio-system`) but different listeners.

## Gateway Listeners

```
https        → *.local.abbottland.io    (internal TLS, wildcard-local-tls cert)
https-public → *.abbottland.io          (public TLS, wildcard-public-tls cert)
http         → port 80, no hostname filter
```

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
    - name: istio-ingress
      namespace: istio-system
      sectionName: https-public         # public listener
  hostnames:
    - myapp.non-prod.abbottland.io
```

Result in Cloudflare: `myapp.non-prod.abbottland.io CNAME abbottland.io` (proxied)

## How external-dns Picks Up Routes

- `external-dns-pihole` watches routes with label `pihole-dns-enabled=true`, domain filter `local.non-prod.abbottland.io`
- `external-dns` (cloudflare) watches routes with label `external-dns-enabled=true`, domain filter `non-prod.abbottland.io`
- Both read from the same Gateway. Target IP comes from the **Gateway annotation** (`external-dns.alpha.kubernetes.io/target: 192.168.6.28`), not the HTTPRoute annotation. See `ai-reference-external-dns-pihole.md` for details.
- DNS records appear within ~1 minute (sync interval)

## Adding a New Service

**Internal only (pihole):** add `pihole-dns-enabled: "true"` label, use `sectionName: https`, hostname `*.local.<cluster-domain>.abbottland.io`.

**Public (cloudflare):** add `external-dns-enabled: "true"` label, annotation `external-dns.alpha.kubernetes.io/target: abbottland.io` + `cloudflare-proxied: "true"`, use `sectionName: https-public`, hostname `*.<cluster-domain>.abbottland.io`.

**Both:** add both labels and both hostnames in separate HTTPRoutes (or one route with both parent refs if the service needs both).

## Hostname Conventions by Cluster

| Cluster | Internal domain | Public domain |
|---------|----------------|---------------|
| non-prod-gen2 | `*.local.non-prod.abbottland.io` | `*.non-prod.abbottland.io` |
| prod-gen2 | `*.local.abbottland.io` | `*.abbottland.io` |

Cluster-specific hostnames are usually patched via kustomize overlay (base uses placeholder, overlay patches the actual hostname).
