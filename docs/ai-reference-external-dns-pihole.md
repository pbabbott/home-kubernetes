# External-DNS Pihole Configuration

## Architecture

Two external-dns instances in `external-dns` namespace:

| Instance | Provider | Label Filter | Domain | Target |
|----------|----------|-------------|--------|--------|
| `external-dns` | cloudflare | `external-dns-enabled=true` | `non-prod.abbottland.io` | `abbottland.io` (CNAME) |
| `external-dns-pihole` | pihole | `pihole-dns-enabled=true` | `local.non-prod.abbottland.io` | `192.168.6.28` (A) |

## Target Resolution Behavior (gateway-httproute source)

**Critical:** external-dns v0.15.x `gateway-httproute` source resolves record targets in this order:

1. **Gateway annotation** `external-dns.alpha.kubernetes.io/target` — takes priority
2. **Gateway `status.addresses`** — fallback if no annotation

HTTPRoute-level `external-dns.alpha.kubernetes.io/target` annotations are **ignored** for target resolution. They are only relevant when no Gateway annotation exists AND the Gateway uses a hostname address (in which case the HTTPRoute annotation won't help either).

**Consequence:** Both external-dns instances read from the same Gateway (`istio-ingress` in `istio-system`). Cloudflare routes carry `abbottland.io` inline on the HTTPRoute, so they are unaffected by the Gateway annotation value. Pihole external-dns uses the Gateway annotation directly.

**Current Gateway annotation:** `external-dns.alpha.kubernetes.io/target: 192.168.6.28`  
File: `infra/base/istio/istio-ingress-gateway-api.yaml`

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

## Adding a New Service to Pihole DNS

Label the HTTPRoute with `pihole-dns-enabled=true` and add the target annotation:

```yaml
metadata:
  labels:
    pihole-dns-enabled: "true"
  annotations:
    external-dns.alpha.kubernetes.io/target: 192.168.6.28
```

Note: the `target` annotation on the HTTPRoute is currently **not used** by external-dns (the Gateway annotation is used instead). Include it for documentation/future compatibility but the actual target comes from the Gateway annotation.

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

- `infra/base/external-dns/external-dns-pihole-helmrelease.yaml` — HelmRelease base config
- `infra/non-prod-gen2/external-dns/kustomization.yaml` — overlay: domainFilters
- `infra/base/external-dns/pihole-admin-onepassword.yaml` — OnePasswordItem for pihole secret
- `infra/base/istio/istio-ingress-gateway-api.yaml` — Gateway with target annotation
