# Session: Gluetun Healthz Endpoint & VPN Connectivity Fix

**Date:** 2026-05-16  
**Branch:** main

## What We Did

### 1. Exposed gluetun health endpoint at `/healthz`

- Discovered gluetun health server at port 9999 (default binds to `127.0.0.1` — loopback only)
- Added `HEALTH_SERVER_ADDRESS: "0.0.0.0:9999"` to `gluetun-configmap.yaml`
- Added port 9999 to deployment, service (with `name:` fields — required for multi-port Services), and HTTPRoute
- HTTPRoute rewrites `/healthz` → `/` on port 9999 (health server only responds at root)
- Updated dashy links to `/healthz` and `/status` for gluetun and gluetun-sync

**Files:** `gluetun-configmap.yaml`, `gluetun-service.yaml`, `qbittorrent-deployment.yaml`, `gluetun-httproute.yaml`, `dashy/templates/configmap.yaml`

### 2. Fixed RWO PVC multi-attach deadlock

- Rolling update scheduled new pod to different node; RWO PVCs already attached to old node → deadlock
- Added `strategy: type: Recreate` + `rollingUpdate: null` to `qbittorrent-deployment.yaml`
- Applied same fix to `prowlarr-deployment.yaml`, `radarr-deployment.yaml`, `sonarr-deployment.yaml`
- `rollingUpdate: null` is required — without it, server-side apply dry-run fails because existing resource has `rollingUpdate` defaults

### 3. Fixed VPN health check crash loop

**Symptom:** gluetun crashed every ~6s with `startup check: all check tries failed: lookup github.com: i/o timeout`

**Root cause:** Default `HEALTH_TARGET_ADDRESSES=cloudflare.com:443,github.com:443` requires DNS resolution at VPN startup, before gluetun's DoT DNS server has established upstream connections through the tunnel.

**Fix:** Set `HEALTH_TARGET_ADDRESSES: "1.1.1.1:443,8.8.8.8:443"` — bypasses DNS, TCP connects to IPs directly.

**Diagnostics along the way:**
- Routing table was correct (`0.0.0.0/1` + `128.0.0.0/1` via tun0)
- TCP to `140.82.112.3:443` (GitHub IP) worked — tunnel routing was fine
- `nslookup github.com` worked — DNS worked *after* startup, not *during*
- Route conflict errors (`RTNETLINK: File exists`) on internal VPN restarts were a symptom, not root cause

### 4. Fixed gluetun-sync 401 Unauthorized

**Symptom:** gluetun-sync `Error: Gluetun API error: 401 Unauthorized` on `GET /v1/portforward`

**Root cause:** Newer gluetun version changed control server to require auth on ALL routes by default — no public routes without `auth.toml`.

**Fix:**
- Created `gluetun-auth-configmap.yaml` with auth.toml allowing `GET /v1/portforward` without credentials
- Added volume mount at `/gluetun-auth/` and env var `HTTP_CONTROL_SERVER_AUTH_CONFIG_FILEPATH=/gluetun-auth/auth.toml`
- Added ConfigMap to `kustomization.yaml`

## Key Learnings

- Multi-port Kubernetes Services require `name:` on each port
- `rollingUpdate: null` must be explicit when setting `strategy.type: Recreate` via GitOps (server-side apply keeps existing defaults otherwise)
- gluetun health check DNS targets should use IPs, not hostnames, to avoid startup race with DoT resolver
- gluetun control server API requires auth.toml even for internal sidecar access in newer versions

## Final State

- `https://gluetun.local.abbottland.io/healthz` → HTTP 200
- `https://gluetun-sync.local.abbottland.io/status` → `mostRecentAttemptSuccessful: true`
- All 4 media deployments 1/1 Ready
- VPN connected to PIA CA Toronto, port 49615 forwarded
