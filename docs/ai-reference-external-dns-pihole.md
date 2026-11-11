# External-DNS Pihole Configuration

## Architecture

Two external-dns instances in `external-dns` namespace:

| Instance | Provider | Label Filter | Domain | Target |
|----------|----------|-------------|--------|--------|
| `external-dns` | cloudflare | `external-dns-enabled=true` | `abbottland.io` | `abbottland.io` (CNAME) |
| `external-dns-pihole` | pihole | `pihole-dns-enabled=true` | `local.abbottland.io` | `192.168.6.29` (A) |

## Target Resolution Behavior (gateway-httproute source)

**Critical:** external-dns v0.15.x `gateway-httproute` source resolves record targets in this order:

1. **Gateway annotation** `external-dns.alpha.kubernetes.io/target` — takes priority
2. **Gateway `status.addresses`** — fallback if no annotation

HTTPRoute-level `external-dns.alpha.kubernetes.io/target` annotations are **ignored** for target resolution. They are only relevant when no Gateway annotation exists AND the Gateway uses a hostname address (in which case the HTTPRoute annotation won't help either).

**Consequence:** The two external-dns instances reference different Gateways. Public/Cloudflare routes use `istio-ingress-public` (annotation `abbottland.io`); internal/pihole routes use `istio-ingress` (annotation `192.168.6.29`). This is the only way to give each instance a different target — HTTPRoute annotations cannot override Gateway annotations.

**Gateway annotations:**
- `istio-ingress`: `external-dns.alpha.kubernetes.io/target: 192.168.6.29` — file `infra/base/networking/istio/istio-ingress-gateway-api.yaml`
- `istio-ingress-public`: `external-dns.alpha.kubernetes.io/target: abbottland.io` — file `infra/base/networking/istio/istio-ingress-public-gateway-api.yaml`

## Registry Setting

Use `registry: noop` for pihole — **not** `registry: txt`.

Pihole v5 does not support TXT records. With `registry: txt`, external-dns:
- Cannot write ownership TXT records → no records are "owned"
- With `policy: sync`, unowned records are skipped
- Result: external-dns logs "All records are already up to date" even when records are wrong

With `registry: noop`:
- No ownership tracking
- `policy: sync` deletes all records in the domain filter that shouldn't exist, adds what should
- Works correctly with pihole

## Policy on gen3
Gen2 external-dns is gone and the gen3 Pi-hole instance runs `policy: sync` + `registry: noop` on `local.abbottland.io`. With no ownership check it deletes ANY record in the domain that has no labelled route or DNSEndpoint: never add records by hand in the Pi-hole UI/API, use a `DNSEndpoint` (see `apps/prod-gen3/host-proxies/asustor/nas-dnsendpoint.yaml`). Config: `infra/prod-gen3/networking/external-dns/`. The Cloudflare instance (live on gen3, `sync`) uses `registry: txt` with owner id `prod-gen2` (inherited), so it only deletes records it owns.

## Adding a New Service to Pihole DNS

Label the HTTPRoute with `pihole-dns-enabled=true` (no target annotation needed):

```yaml
metadata:
  labels:
    pihole-dns-enabled: "true"
```

Note: a `target` annotation on the HTTPRoute is **ignored** by external-dns; the target always comes from the Gateway annotation.

External-dns reconciles every 1 minute. New HTTPRoutes are picked up automatically.

## Troubleshooting

```bash
# Check pod status
kubectl get pods -n external-dns

# Check logs for sync activity
kubectl logs -n external-dns -l app.kubernetes.io/instance=external-dns-pihole --tail=30

# Check HelmRelease status
flux get helmrelease external-dns-pihole -n flux-system

# Force reconcile HelmRelease
flux reconcile helmrelease external-dns-pihole -n flux-system --with-source

# Restart pod (force re-read of all resources)
kubectl rollout restart deployment external-dns-pihole -n external-dns

# Verify current pihole A records
PIHOLE_PASS=$(kubectl get secret pihole-admin-secret -n external-dns -o jsonpath='{.data.pw}' | base64 -d)
AUTH=$(echo -n "$PIHOLE_PASS" | sha256sum | awk '{print $1}' | tr -d '\n' | sha256sum | awk '{print $1}')
kubectl run -n default pihole-check --image=curlimages/curl --restart=Never \
  --env="AUTH=$AUTH" \
  -- sh -c "curl -s 'http://192.168.4.144:8081/admin/api.php?customdns&action=get&auth=\$AUTH'"
sleep 10 && kubectl logs pihole-check -n default && kubectl delete pod pihole-check -n default
```

## Key Files

- `infra/base/networking/external-dns/external-dns-pihole-helmrelease.yaml` — HelmRelease base config
- `infra/prod-gen3/networking/external-dns/kustomization.yaml` — overlay: domainFilters, txtOwnerId
- `infra/base/networking/external-dns/pihole-admin-onepassword.yaml` — OnePasswordItem for pihole secret
- `infra/base/networking/istio/istio-ingress-gateway-api.yaml` — Gateway with target annotation
