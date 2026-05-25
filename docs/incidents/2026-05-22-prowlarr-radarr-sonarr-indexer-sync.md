# Prowlarr → Radarr/Sonarr Indexer Sync Broken

**Date:** 2026-05-22  
**Severity:** Medium (Radarr and Sonarr unable to search for releases)  
**Services:** Prowlarr, Radarr, Sonarr

## Symptoms

- Radarr and Sonarr indexer release searches returned 0 results
- All Radarr/Sonarr indexers showed `"enable": null` via API
- Prowlarr logs showed recurring 401 errors every ~6 hours:
  ```
  HTTP request failed: [401:Unauthorized] [GET] at [http://radarr:7878/api/v3/indexer]
  HTTP request failed: [401:Unauthorized] [GET] at [http://sonarr:8989/api/v3/indexer]
  ```
- Prowlarr logs also showed older sync failures:
  ```
  No Results in configured categories. See FAQ Entry: Prowlarr will not sync X Indexer to App
  HTTP request failed: [400:BadRequest] [POST] at [http://radarr:7878/api/v3/indexer?forceSave=true]
  ```

## Root Cause

Two separate issues:

**1. Stale API keys in Prowlarr app config**  
Prowlarr stores the API key for each downstream app (Radarr, Sonarr) in its application settings. After a cluster rebuild, the Radarr and Sonarr API keys rotated but Prowlarr's stored keys were not updated. This caused 401 errors on every sync attempt, preventing Prowlarr from reading or writing indexers.

**2. Stale internal indexer ID mappings in Prowlarr**  
Prowlarr maintains an internal mapping of Prowlarr indexer → Radarr/Sonarr indexer ID. After a cluster rebuild the old indexer IDs no longer exist. Prowlarr tries to GET/UPDATE those old IDs, gets 404, and should then re-add them. However, the per-app sync endpoint (`POST /api/v1/applications/{id}/sync`) does not properly re-add on 404 — it only re-tests and skips if it thinks the state is current. The `ApplicationIndexerSync` command (which syncs all apps at once) correctly detects the missing indexers and re-adds them.

## Remediation

### Step 1: Update API keys in Prowlarr

Prowlarr app IDs: Radarr = 1, Sonarr = 2.

```bash
# Get current app config
RADARR_APP=$(curl -s -L -k -H "X-Api-Key: <PROWLARR_API_KEY>" \
  "https://prowlarr.local.abbottland.io/api/v1/applications/1")

# Patch API key field and PUT back
UPDATED=$(echo "$RADARR_APP" | jq '
  .fields = (.fields | map(
    if .name == "apiKey" then .value = "<RADARR_API_KEY>"
    else .
    end
  ))
')
curl -s -L -k -X PUT \
  -H "X-Api-Key: <PROWLARR_API_KEY>" \
  -H "Content-Type: application/json" \
  "https://prowlarr.local.abbottland.io/api/v1/applications/1" \
  -d "$UPDATED"

# Repeat for Sonarr (app id 2) with SONARR_API_KEY
```

Current API keys are in `.env` at repo root:
- `PROWLARR_API_KEY` — used to auth to Prowlarr
- `RADARR_API_KEY` — goes into Prowlarr's Radarr app config
- `SONARR_API_KEY` — goes into Prowlarr's Sonarr app config

### Step 2: Delete stale indexers from Radarr and Sonarr

Prowlarr cannot update indexers whose IDs no longer exist in its internal mapping. Delete all existing indexers so Prowlarr re-adds them clean.

```bash
# List then delete all Radarr indexers
curl -s -L -k -H "X-Api-Key: <RADARR_API_KEY>" \
  "https://radarr.local.abbottland.io/api/v3/indexer" | jq '[.[] | {id, name}]'

for id in <id1> <id2> ...; do
  curl -s -L -k -X DELETE -H "X-Api-Key: <RADARR_API_KEY>" \
    "https://radarr.local.abbottland.io/api/v3/indexer/$id"
done

# Same for Sonarr
curl -s -L -k -H "X-Api-Key: <SONARR_API_KEY>" \
  "https://sonarr.local.abbottland.io/api/v3/indexer" | jq '[.[] | {id, name}]'

for id in <id1> <id2> ...; do
  curl -s -L -k -X DELETE -H "X-Api-Key: <SONARR_API_KEY>" \
    "https://sonarr.local.abbottland.io/api/v3/indexer/$id"
done
```

### Step 3: Trigger full sync via ApplicationIndexerSync command

**Critical:** use the `ApplicationIndexerSync` command, NOT the per-app `/api/v1/applications/{id}/sync` endpoint. The per-app endpoint does not properly re-add missing indexers; the command does.

```bash
curl -s -L -k -X POST \
  -H "X-Api-Key: <PROWLARR_API_KEY>" \
  -H "Content-Type: application/json" \
  "https://prowlarr.local.abbottland.io/api/v1/command" \
  -d '{"name": "ApplicationIndexerSync"}'

# Wait ~25 seconds then verify
```

### Step 4: Verify

```bash
# Radarr — should return results (use any movie ID from the library)
curl -s -L -k -H "X-Api-Key: <RADARR_API_KEY>" \
  "https://radarr.local.abbottland.io/api/v3/release?movieId=253" | jq 'length'

# Sonarr — should return results (use any series ID from the library)
curl -s -L -k -H "X-Api-Key: <SONARR_API_KEY>" \
  "https://sonarr.local.abbottland.io/api/v3/release?seriesId=4&seasonNumber=1" | jq 'length'
```

## Indexer Notes

Prowlarr indexer IDs (path in Torznab URL `http://prowlarr:9696/<ID>/`):

| Prowlarr ID | Name | Radarr | Sonarr | Notes |
|-------------|------|--------|--------|-------|
| 1 | The Pirate Bay | ✓ | ✓ | General movies + TV |
| 8 | Nyaa.si | ✓ | ✓ | Primarily anime |
| 9 | AnimeTosho | ✓ | ✓ | Primarily anime |
| 10 | LimeTorrents | ✗ | ✓ | No movie category results; TV results present |

Radarr excludes LimeTorrents because it returns 0 results in movie categories (2000–2090). Prowlarr skips it for Radarr automatically.

## Key Finding: Per-App Sync vs ApplicationIndexerSync Command

`POST /api/v1/applications/{id}/sync` — tests indexers and updates existing ones, but **does not re-add missing indexers** when Prowlarr's internal ID mapping is stale. Appears to complete silently with no error when there is nothing to do.

`POST /api/v1/command` with `{"name": "ApplicationIndexerSync"}` — full sync across all apps; detects missing indexers via 404 on the old ID and re-adds them. **This is the correct command to use.**

## Prevention

After any cluster rebuild that regenerates API keys:
1. Update Prowlarr's app configs for Radarr and Sonarr (Step 1)
2. Delete stale indexers from Radarr/Sonarr (Step 2)
3. Run `ApplicationIndexerSync` command (Step 3)

Steps 2 and 3 are needed because Prowlarr's internal ID mappings point to the old indexer IDs, which no longer exist after a rebuild.
