# media gen2 reconciliation checklist (delete when done)

## pre-flight (before push/reconcile)

- [x] Add `.dockerconfigjson` field to `vaults/Homelab/items/harbor.local.abbottland.io - admin`
- [x] Verify `PrivateInternetAccess.com` and `qbittorrent.local.abbottland.io` items readable from prod-gen2 op-connect
- [x] Confirm `192.168.4.124:/volume1/Media` NFS export allows prod-gen2 node IPs

## post-reconcile: infra checks

- [x] `operator.1password.io/type: kubernetes.io/dockerconfigjson` honored — operator v1.8.1 does NOT honor this annotation; manually patched secret and pinned with `operator.1password.io/item-version` annotation. **Tech debt**: upgrade op-connect chart to operator ≥1.9.0 to fix permanently — regcred will revert to Opaque if 1Password item is edited.
- [x] `image-reflector-controller` + `image-automation-controller` pods running in `flux-system` — FluxInstance was missing these components; patched manually, now running.
- [x] `kubectl -n flux-system get imagerepository,imagepolicy` — resolves to `0.1.0` (2 tags found) ✓
- [x] `kubectl -n media get pv,pvc` — `media-pv` Bound, all 5 config PVCs Bound on longhorn ✓
- [x] prod-gen2 nodes have `/dev/net/tun` ✓
- [x] `NET_ADMIN` capability not blocked — no PodSecurity admission labels on media namespace ✓
- [x] hostPort conflicts — none ✓

## post-reconcile: NFS permissions

- [x] PGID=1000 set in `servarr-env` configmap. NFS dirs (`media/`, `torrents/`, `usenet/`) are `drwxrwxrwx` — no chown needed ✓

## post-reconcile: app wiring

- [x] Prowlarr: Radarr + Sonarr added as apps (fullSync) ✓
- [x] Radarr + Sonarr: qBittorrent download client configured ✓
- [x] VPN connected: tun0 up, PIA toronto405, port 49615 forwarded ✓

## post-reconcile: DNS

- [x] `dig qbittorrent.local.abbottland.io` → `192.168.6.28` ✓
- [x] All 6 UIs reachable ✓ — gluetun + gluetun-sync return 404 on `/` (expected, no root endpoint)

## media stack URLs

| App | URL |
|-----|-----|
| qBittorrent | https://qbittorrent.local.abbottland.io |
| Gluetun | https://gluetun.local.abbottland.io |
| Gluetun Sync | https://gluetun-sync.local.abbottland.io |
| Prowlarr | https://prowlarr.local.abbottland.io |
| Radarr | https://radarr.local.abbottland.io |
| Sonarr | https://sonarr.local.abbottland.io |

## note: image auto-update

`ImageUpdateAutomation` not configured — gluetun-sync pinned at `0.1.0`. Tag bumps require manual commit for now.
