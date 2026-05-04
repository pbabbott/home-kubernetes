# 2026-05-03 — podinfo public access debugging

## Goal
Make `https://podinfo.abbottland.io/` accessible externally.

## What was investigated

### 1. Istio AuthorizationPolicy blocking external IPs
- `internal-apps-ip-allowlist` in `istio-system` — ALLOW policy with `ipBlocks` restricted to RFC1918 ranges
- Ambient mode ztunnel drops L7 HTTP-attribute rules (`hosts`, `notHosts`, `remoteIpBlocks`) but enforces L4 `ipBlocks`
- External IPs matched no ALLOW rule → denied
- **Fix applied:** patched policy to add rule with `ipBlocks: ["0.0.0.0/0", "::/0"]` — temporary, flux reconcile will restore

### 2. Missing router port forward
- Gateway service is NodePort only (no MetalLB/kube-vip): port 443 → nodePort 30443
- No port forward 443 → node:30443 at home router
- **Fix:** user manually added port forward on router

### 3. Cloudflare SSL "Flexible" mode → redirect loop
- Cloudflare proxies `podinfo.abbottland.io` (confirmed via Cloudflare proxy IPs in dig)
- Flexible SSL mode: Cloudflare→origin connects on **HTTP** (port 80/30080)
- Origin `http` listener has `podinfo-public-http-to-https` HTTPRoute → 301 to `https://podinfo.abbottland.io/`
- Cloudflare passes 301 verbatim → client already on HTTPS → infinite loop
- Confirmed with curl: HTTP/2 301 → `https://podinfo.abbottland.io/` repeating
- **Fix needed:** Cloudflare dashboard → SSL/TLS → set to **Full (Strict)**

## Infrastructure context
- `podinfo-public` HTTPRoute (23h old at time of session) — hostname `podinfo.abbottland.io`, parentRef `istio-ingress` `https-public` listener
- `wildcard-public-tls` cert: `*.abbottland.io`, Let's Encrypt via cert-manager, valid until Jul 2026
- `cloudflare-ddns` manages only apex `abbottland.io` A record
- external-dns (`prod-gen2` TXT owner) manages CNAME `podinfo.abbottland.io` → `abbottland.io`

## Pending
- Cloudflare SSL/TLS mode still needs to be changed to Full (Strict) by user
- Temporary auth policy patch will be reverted on next flux reconcile (intended)
