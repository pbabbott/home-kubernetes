# Session: Port Media Stack to prod-gen2

**Date:** 2026-05-15
**Branch:** main

## What we did

Planned and implemented porting the full gen1 media stack (`apps/media/`) to prod-gen2 (`applications/base/media/` + `applications/prod-gen2/media/`).

## Apps ported

- **qbittorrent** (with gluetun VPN sidecar + gluetun-sync port-forward sync)
- **prowlarr**
- **radarr**
- **sonarr**

## Key decisions

| Decision | gen1 | gen2 |
|----------|------|------|
| Bulk media (10Ti) | Static NFS PV → `192.168.4.124:/volume1/Media` | Same — ported as-is |
| Config PVCs | `nas-storage` RWX 1Mi | `longhorn` RWO (1–5Gi each) |
| Ingress | nginx Ingress + cert-manager | Istio Gateway API HTTPRoutes |
| Secrets | SealedSecret `regcred` | `OnePasswordItem` → `harbor.local.abbottland.io - admin` |
| Image automation | Not on gen2 FluxInstance | Enabled image-reflector + image-automation controllers |
| Ambient mode | N/A | Namespace explicitly NOT ambient (gluetun NET_ADMIN incompatible) |

## Files created

**`applications/base/media/`** — 41 files total:
- `namespace.yaml`, `media-pv.yaml`, `media-pvc.yaml`
- 5 Longhorn PVCs: `gluetun-config-pvc.yaml`, `qbittorrent-config-pvc.yaml`, `prowlarr-config-pvc.yaml`, `radarr-config-pvc.yaml`, `sonarr-config-pvc.yaml`
- 4 ConfigMaps: `gluetun-configmap.yaml`, `gluetun-sync-configmap.yaml`, `qbittorrent-configmap.yaml`, `servarr-env-configmap.yaml`
- 5 OnePasswordItems: `pia-credentials-onepassworditem.yaml`, `qbittorrent-credentials-onepassworditem.yaml`, `regcred-onepassworditem.yaml`, `regcred-flux-onepassworditem.yaml`
- 7 Services, 4 Deployments
- 12 HTTPRoutes (6 internal HTTPS + 6 HTTP→HTTPS redirects) for: gluetun, gluetun-sync, qbittorrent, prowlarr, radarr, sonarr
- 2 Flux image automation: `gluetun-sync-image-repository.yaml`, `gluetun-sync-image-policy.yaml`
- `kustomization.yaml`

**`applications/prod-gen2/media/kustomization.yaml`** — overlay pointing at base.

## Files modified

- `applications/prod-gen2/kustomization.yaml` — added `./media`
- `applications/prod-gen2/flux-gitops/fluxinstance.yaml` — added `image-reflector-controller` + `image-automation-controller`

## Cleanups applied during port

- Dropped `curl-container` debug sidecar from qbittorrent pod
- Fixed configmap name typo: `qbittorent-env` → `qbittorrent-env`
- Normalized `servarr-env` PGID from 100 → 1000 (match qbittorrent; NFS share uid:gid 1000:1000)

## Pre-flight required before merge

1. Add `.dockerconfigjson` field to `vaults/Homelab/items/harbor.local.abbottland.io - admin`:
   ```sh
   USER=$(op read "op://Homelab/harbor.local.abbottland.io - admin/username")
   PASS=$(op read "op://Homelab/harbor.local.abbottland.io - admin/password")
   AUTH=$(printf '%s:%s' "$USER" "$PASS" | base64 -w0)
   printf '{"auths":{"harbor.local.abbottland.io":{"auth":"%s"}}}' "$AUTH" \
     | op item edit "harbor.local.abbottland.io - admin" --vault Homelab \
         ".dockerconfigjson[password]=$(cat -)"
   ```
2. Verify Homelab vault items `PrivateInternetAccess.com` and `qbittorrent.local.abbottland.io` reachable from prod-gen2 op-connect.
3. Confirm `192.168.4.124:/volume1/Media` NFS export permits prod-gen2 node IPs.

## DNS / hostnames (all internal, pihole)

All six UIs on `*.local.abbottland.io`:
- `gluetun.local.abbottland.io` → gluetun-http:8000
- `gluetun-sync.local.abbottland.io` → gluetun-sync:4000
- `qbittorrent.local.abbottland.io` → qbittorrent-ui:8080
- `prowlarr.local.abbottland.io` → prowlarr:9696
- `radarr.local.abbottland.io` → radarr:7878
- `sonarr.local.abbottland.io` → sonarr:8989

## Known nuance: regcred Secret type

`OnePasswordItem` creates Opaque Secrets by default. Added `operator.1password.io/type: "kubernetes.io/dockerconfigjson"` annotation on both `regcred` and `regcred-flux` OnePasswordItems. Verify this annotation is honored by the installed operator version (chart `connect@1.17.0`) — if not, the Secret type may need manual patching post-apply.
