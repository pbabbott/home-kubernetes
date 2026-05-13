# Pihole Admin API Reference

Pihole runs externally at `192.168.4.144:8081` (bananapi). Accessible from cluster via `pihole.pihole.svc.cluster.local:8081` (ClusterIP backed by EndpointSlice).

## Auth

Pihole v5 API auth token = `SHA256(SHA256(plaintext_password))`.

```bash
# Get password from cluster secret
PIHOLE_PASS=$(kubectl get secret pihole-admin-secret -n external-dns -o jsonpath='{.data.pw}' | base64 -d)

# Compute auth token
AUTH=$(echo -n "$PIHOLE_PASS" | sha256sum | awk '{print $1}' | tr -d '\n' | sha256sum | awk '{print $1}')
```

## Querying from Cluster

No curl/wget inside pihole container — use a debug pod:

```bash
kubectl run -n default pihole-debug --image=curlimages/curl --restart=Never \
  --env="AUTH=$AUTH" \
  -- sh -c "<curl commands using \$AUTH>"
sleep 10
kubectl logs pihole-debug -n default
kubectl delete pod pihole-debug -n default
```

## Custom DNS API Endpoints

All requests use `http://192.168.4.144:8081/admin/api.php`.

### A Records (custom DNS)

```bash
# List
curl -s "http://192.168.4.144:8081/admin/api.php?customdns&action=get&auth=$AUTH"
# Response: {"data":[["hostname","ip"],...]}

# Add
curl -s "http://192.168.4.144:8081/admin/api.php?customdns&action=add&ip=192.168.6.28&domain=foo.example.com&auth=$AUTH"

# Delete
curl -s "http://192.168.4.144:8081/admin/api.php?customdns&action=delete&ip=192.168.6.28&domain=foo.example.com&auth=$AUTH"
```

### CNAME Records

```bash
# List
curl -s "http://192.168.4.144:8081/admin/api.php?customcname&action=get&auth=$AUTH"
# Response: {"data":[["domain","target"],...]}

# Add
curl -s "http://192.168.4.144:8081/admin/api.php?customcname&action=add&domain=foo.example.com&target=bar.example.com&auth=$AUTH"

# Delete
curl -s "http://192.168.4.144:8081/admin/api.php?customcname&action=delete&domain=foo.example.com&target=bar.example.com&auth=$AUTH"
```

## Notes

- `customdns` = A/AAAA records stored in `/etc/pihole/custom.list`
- `customcname` = CNAME records stored in `/etc/dnsmasq.d/05-pihole-custom-cname.conf`
- Delete errors: `{"success":false,"message":"This domain/ip association does not exist"}` — record already gone or wrong ip/target value
- External-dns manages records in `local.non-prod.abbottland.io` domain
- Static host records (`elderwand`, `bananapi`, `nas`, etc.) are in `local.abbottland.io` — do not delete
