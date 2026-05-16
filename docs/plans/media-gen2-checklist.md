# media gen2 reconciliation checklist (delete when done)

## pre-flight (before push/reconcile)

- [x] Add `.dockerconfigjson` field to `vaults/Homelab/items/harbor.local.abbottland.io - admin`:
  ```sh
  USER=$(op read "op://Homelab/harbor.local.abbottland.io - admin/username")
  PASS=$(op read "op://Homelab/harbor.local.abbottland.io - admin/password")
  AUTH=$(printf '%s:%s' "$USER" "$PASS" | base64 -w0)
  printf '{"auths":{"harbor.local.abbottland.io":{"auth":"%s"}}}' "$AUTH" \
    | op item edit "harbor.local.abbottland.io - admin" --vault Homelab ".dockerconfigjson[password]=$(cat -)"
  ```
- [x] Verify `PrivateInternetAccess.com` and `qbittorrent.local.abbottland.io` items readable from prod-gen2 op-connect
- [x] Confirm `192.168.4.124:/volume1/Media` NFS export allows prod-gen2 node IPs

## post-reconcile: infra checks

- [x] `operator.1password.io/type: kubernetes.io/dockerconfigjson` honored — operator v1.8.1 does NOT honor this annotation; manually patched secret and pinned with `operator.1password.io/item-version` annotation to prevent overwrite. Permanent fix: upgrade op-connect chart to operator >=1.9.0.
- [x] `image-reflector-controller` + `image-automation-controller` pods running in `flux-system` — FluxInstance was missing these components; patched manually, now running.
- [ ] `kubectl -n flux-system get imagerepository,imagepolicy` — gluetun-sync resolves a tag — BLOCKED: `harbor.local.abbottland.io/library/gluetun-sync` repo does not exist in Harbor. Image `gluetun-sync:0.0.10` must be built and pushed to Harbor before this resolves.
- [x] `kubectl -n media get pv,pvc` — `media-pv` Bound, all 5 config PVCs Bound on longhorn ✓
- [x] prod-gen2 nodes have `/dev/net/tun` (TUN kernel module) — confirmed via running gluetun container
- [x] `NET_ADMIN` capability not blocked — media namespace has no PodSecurity admission labels ✓
- [x] hostPort conflicts — ports 4000, 8000, 8888 (qbt pod), 9696, 7878, 8989 not used by other pods on same node ✓

## post-reconcile: NFS permissions

- [x] PGID changed 100→1000 for servarr apps — PGID=1000 set in `servarr-env` configmap. NFS dirs (`media/`, `torrents/`, `usenet/`) are `drwxrwxrwx` so gid 1000 can write without chown. ✓

## post-reconcile: app wiring (manual, in UIs)

- [ ] Prowlarr: add Radarr (`http://radarr.media:7878`) and Sonarr (`http://sonarr.media:8989`) as apps
- [ ] Radarr + Sonarr: add qBittorrent as download client (`http://qbittorrent-ui.media:8080`)
- [ ] Verify VPN connected: `kubectl -n media logs deploy/qbittorrent-vpn -c gluetun | grep -i "port forward"` — VPN connected (tun0 up, PIA toronto405), port forwarding enabled in config. Active forwarded port not yet confirmed (qbittorrent-vpn pod not fully ready).

## post-reconcile: DNS

- [x] `dig qbittorrent.local.abbottland.io` → `192.168.6.28` ✓
- [ ] All 6 UIs reachable: gluetun, gluetun-sync, qbittorrent, prowlarr, radarr, sonarr — prowlarr/radarr/sonarr reachable (200). gluetun/qbittorrent/gluetun-sync return 503 because qbittorrent-vpn pod not Ready (gluetun-sync container in ImagePullBackOff). Blocked by missing Harbor image.

## media stack URLs

| App | URL | Description |
|-----|-----|-------------|
| qBittorrent | https://qbittorrent.local.abbottland.io | Torrent client, tunneled via VPN |
| Gluetun | https://gluetun.local.abbottland.io | PIA VPN control API |
| Gluetun Sync | https://gluetun-sync.local.abbottland.io | Syncs VPN port to qBittorrent |
| Prowlarr | https://prowlarr.local.abbottland.io | Indexer aggregator for servarr |
| Radarr | https://radarr.local.abbottland.io | Automated movie downloads |
| Sonarr | https://sonarr.local.abbottland.io | Automated TV show downloads |

## note: image auto-update

`ImageUpdateAutomation` not configured — gluetun-sync pinned at `0.1.0`. Tag bumps require manual commit for now.

## blocker resolved: gluetun-sync image

Updated to `0.1.0` — image exists at `harbor.local.abbottland.io/library/gluetun-sync:0.1.0`.
