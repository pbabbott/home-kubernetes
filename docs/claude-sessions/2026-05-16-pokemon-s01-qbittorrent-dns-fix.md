# Session: Pokemon S01 Download + qBittorrent DNS Fix

**Date:** 2026-05-16  
**Branch:** main  
**Commit:** `2d66996`

## What We Did

### Context (continued from previous session)
Previous session had set up Prowlarr indexers (Nyaa.si, AnimeTosho, LimeTorrents, TPB, Torrent Downloads), added Sonarr category sync for 5070 (TV/Anime), blocked French releases, and manually pushed a ColdFusion Pokemon 001-079 English Dub magnet to qBittorrent.

### Problem: Torrents Stuck in `metaDL`
User reported downloads stuck in "downloading metadata." Found two new torrents in qBittorrent both in `metaDL` with 0 seeders:
- `Pokemon Season 1 (Indigo League) [1997 - 1999] (Mixed x265 HEVC 10bit)` — added by Sonarr auto-grab
- `Pokemon: Indigo League - Season 1 (Episode 1-82) BRRip x264 [English-Audio] By [Tioking]`

Also confirmed ColdFusion 001-079 from prior session was no longer present (PVC retained during pod restarts but torrent was gone).

### Root Cause Analysis
1. Deleted the two stuck 0-seeder torrents
2. Added ColdFusion 001-079 magnet fresh (via Prowlarr proxy URL → resolved actual magnet hash `0f8478bf303bbe0e4c5bf159bbdefc823211af30`)
3. VPN confirmed working: external IP 212.32.48.108, portforward port 49615 active
4. Tracker status showed `"Host not found (authoritative)"` for all trackers despite `nslookup` resolving fine from container

**Root cause:** `ndots:5` (Kubernetes default) in `/etc/resolv.conf` causes hostnames with <5 dots (e.g. `tracker.opentrackr.org`) to be tried with search domains first. The `local.abbottland.io` search domain is served by pihole, which returns **authoritative NXDOMAIN** for `tracker.opentrackr.org.local.abbottland.io`. With an authoritative negative response, `getaddrinfo()` / libnss stops searching and returns failure — without ever trying the bare hostname.

Evidence: `nslookup` (uses its own resolver, ignores ndots) → resolves fine. `getent hosts tracker.opentrackr.org` → empty (uses getaddrinfo/NSS, hits authoritative NXDOMAIN).

qBittorrent uses `getaddrinfo()` internally → same failure path.

### Fix
Added `dnsConfig` to qbittorrent-vpn pod spec:

```yaml
spec:
  dnsConfig:
    options:
      - name: ndots
        value: "1"
```

File: `applications/base/media/qbittorrent-deployment.yaml`

With `ndots:1`, hostnames with 1+ dot are tried as absolute names first — trackers resolve immediately without hitting search domains.

### Deployment
- Committed: `2d66996 fix(media): set ndots=1 in qbittorrent-vpn pod dnsConfig`
- Pushed to GitHub (required because Flux pulls from remote, not local)
- Flux `apps-ks` reconciled automatically
- New pod: `qbittorrent-vpn-b96b445fb-mr8tx`
- Verified: `getent hosts tracker.opentrackr.org` → `93.158.213.92` ✓

### Tracker Status After Fix
- `http://nyaa.tracker.wf:7777/announce` → status=working, 5 seeds, 7 peers ✓
- `udp://tracker.opentrackr.org:1337/announce` → status=working, 4 seeds, 6 peers ✓
- UDP trackers on other ports → "Operation not permitted" (gluetun may block some UDP ports)

## Current State

| Torrent | State | Notes |
|---------|-------|-------|
| `[ColdFusion] Pokemon - Indigo League (001-079) English Dub Only` | metaDL (slow) | Trackers responding, low seed count (4-5), metadata retrieval pending |
| `Pokemon (1997) Season 1 S01 (MiXED x265 HEVC 10bit)` | error | Auto-grabbed by Sonarr, went to error state |
| `Pokemon Season 1 (Indigo League) (Mixed x265 HEVC 10bit)` | metaDL | Re-added by Sonarr automatic search, 3 leechers 0 seeds |

## Pending Work

1. **S01E80-82 gap**: ColdFusion covers eps 1-79 of 82. Need English dub source for the last 3 episodes (TVDB: "Friends to the End", "Pallet Party Panic", "A Scare in the Air").
   - Best candidates found: nothing clean with good seed counts
   - All TPB `Episodes 71-82` options have 0 seeders
   
2. **Sonarr auto-grab cleanup**: Sonarr is triggering automatic season searches and grabbing releases that go to error. May need to pause automatic searching for Pokemon or configure better quality profiles.

3. **ColdFusion download**: Should eventually start downloading once metadata obtained from the 4-5 seeds. Monitor progress.

## Key Debugging Commands

```bash
# Check torrent tracker status
curl -sL -c /tmp/qb_cookies2.txt -b /tmp/qb_cookies2.txt \
  "https://qbittorrent.local.abbottland.io/api/v2/torrents/trackers?hash=<hash>" -k

# Verify ndots fix in pod
kubectl exec -n media <pod> -c qbittorrent -- cat /etc/resolv.conf
kubectl exec -n media <pod> -c qbittorrent -- getent hosts tracker.opentrackr.org

# Check VPN status
kubectl exec -n media <pod> -c gluetun -- wget -qO- http://localhost:8000/v1/portforward
```
