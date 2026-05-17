# 2026-05-17 — Radarr/Sonarr/Prowlarr Fix

## Trigger
Radarr posters not loading; suspected Prowlarr connection broken.

## Root Cause
Prowlarr DB was reset (pod restart 2026-05-16), generating a new API key and new indexer IDs. This caused two-way auth failures:
- Radarr/Sonarr stored old Prowlarr API key in their Prowlarr-managed indexers → 401 hitting `http://prowlarr:9696/{id}/api`
- Prowlarr stored old Radarr/Sonarr API keys in its app config → 401 syncing back to `http://radarr:7878` and `http://sonarr:8989`

Additionally, Prowlarr indexer IDs changed after DB reset. Radarr still referenced dead IDs 2 (TheRARBG) and 5 (Badass Torrents) which returned 401.

## Fixes Applied

### Radarr
1. Deleted stale Prowlarr-managed indexers referencing dead IDs 2 and 5
2. Updated Prowlarr's Radarr app config with correct API key (`c9cd03eee3bf452ea14d6ec12cad6311`)
3. Force-synced `ApplicationIndexerSync` → Prowlarr pushed 3 fresh indexers (The Pirate Bay, AnimeTosho, Nyaa.si)
4. Cleared stale indexer failure status via `DELETE /api/v3/indexerstatus`
5. Triggered `RefreshMovie` to re-download missing posters from TMDB (all `/config/MediaCover/*/poster.jpg` were missing from fresh PVC)

### Sonarr
1. Updated Prowlarr's Sonarr app config with correct API key (`eec4a8ff2a144d53bc620ab5419f7552`)
2. Cleared stale indexer failure status
3. Discovered "Torrent Downloads" has been failing in Prowlarr since **2026-03-07** (dead indexer)
4. Deleted Torrent Downloads from Prowlarr → auto-removed from Sonarr and Radarr via fullSync

## Final State
- Radarr health: clean
- Sonarr health: clean
- Prowlarr indexers: The Pirate Bay (1), Nyaa.si (8), AnimeTosho (9), LimeTorrents (10)
- Radarr indexers: The Pirate Bay, AnimeTosho, Nyaa.si
- Sonarr indexers: The Pirate Bay, AnimeTosho, Nyaa.si, LimeTorrents
- Radarr posters: downloading in background via RefreshMovie

## Other Observations (not changed)
- All Sonarr quality profiles have `upgradeAllowed: false` — won't auto-upgrade quality
- No recycle bin configured on either Radarr or Sonarr
- 20.8TB free on `/data/media/tv_shows`
