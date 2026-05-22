# 2026-05-22 — abbottland.io 522 incident fix

## Problem

`https://abbottland.io` returning Cloudflare 522 (connection timed out). All public `*.abbottland.io` routes affected.

## Investigation

Worked through the full stack top-down:

- **DNS**: resolved to Cloudflare proxy IPs — fine
- **Certs**: `apex-public-tls`, `wildcard-public-tls`, `wildcard-local-tls` all valid and Ready
- **Gateway**: `istio-ingress-public` programmed, listeners `https-public` and `https-public-apex` both UP with attached routes
- **HTTPRoute**: `blog-public` (namespace `blog`) bound to `https-public-apex`, status Accepted/ResolvedRefs
- **Backend**: blog pod Running/Ready, Next.js listening on 0.0.0.0:3000
- **HAProxy** (192.168.6.28): `prod-cluster-https` backend UP, routing to tfpw1-3
- **NodePort**: 30443 open on nodes
- **cloudflare-ddns logs**: `Failed to check if a zone named abbottland.io exists: Invalid access token (9109)` — failing continuously
- **external-dns logs**: `Failed to do run once: Invalid access token (9109)` — fatal on every run

## Root Cause

Cloudflare API token stored in 1Password (`Homelab` vault → `cloudflare_api_token`) was invalid. Token had been rotated on 05/21/2026 but the new token saved to 1Password was wrong/revoked.

Confirmed with direct API call:
```
curl -H "Authorization: Bearer <token>" https://api.cloudflare.com/client/v4/user/tokens/verify
→ {"success": false, "errors": [{"code": 1000, "message": "Invalid API Token"}]}
```

**Consequence**: `cloudflare-ddns` couldn't update the `abbottland.io` A record. Public IP had changed to `97.127.94.72` but Cloudflare had a stale origin IP → Cloudflare couldn't reach origin → 522.

All three consumers (cloudflare-ddns, external-dns, cert-manager) share the same `cloudflare-api-token-secret` from the same 1Password item path `vaults/Homelab/items/cloudflare_api_token`, confirmed by matching sha256 hashes across namespaces.

## Fix

1. Created new Cloudflare API token in Cloudflare dashboard (Zone:Read + Zone:Edit on abbottland.io)
2. Updated 1Password `cloudflare_api_token` item with new token
3. Force-reconciled both `OnePasswordItem`s to push new token to K8s secrets:
   ```bash
   kubectl --context prod-gen2 annotate onepassworditem cloudflare-api-token-secret -n cert-manager operator.1password.io/item-version- --overwrite
   kubectl --context prod-gen2 annotate onepassworditem cloudflare-api-token-secret -n external-dns operator.1password.io/item-version- --overwrite
   ```
4. `auto-restart: "true"` annotation triggered pod restarts automatically
5. DDNS immediately updated stale A record: `📡 Updated an outdated A record for abbottland.io`
6. `https://abbottland.io` → 200

## Notes

- Token format `cfut_` prefix (53 chars) is valid modern Cloudflare user API token format
- New token active from 2026-05-22, expires 2027-05-21
- cert-manager had a secondary unrelated error (7003 empty zone ID during ACME challenge cleanup) — certs are valid, non-blocking
