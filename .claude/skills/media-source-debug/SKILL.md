---
name: media-source-debug
description: Debug why Sonarr/Radarr can't find sources — check indexer backoffs, search results, Prowlarr health
---

User says a movie or show has no sources, or search returns no results. Load `.env` for API keys. Follow these steps.

## Auth

```bash
source /workspaces/home-kubernetes/.env
RADARR_BASE=https://radarr.local.abbottland.io
SONARR_BASE=https://sonarr.local.abbottland.io
PROWLARR_BASE=https://prowlarr.local.abbottland.io
```

## Step 1: Find the media item

Radarr URLs use TMDB ID (e.g. `/movie/324857` → TMDB 324857):

```bash
# Find by TMDB ID
curl -s "$RADARR_BASE/api/v3/movie" -H "X-Api-Key: $RADARR_API_KEY" | \
  python3 -c "import sys,json; [print(m['id'],m['title']) for m in json.load(sys.stdin) if m['tmdbId']==324857 or m['id']==324857]"

# Sonarr
curl -s "$SONARR_BASE/api/v3/series" -H "X-Api-Key: $SONARR_API_KEY" | \
  python3 -c "import sys,json; [print(s['id'],s['title']) for s in json.load(sys.stdin)]"
```

## Step 2: Run interactive search

```bash
# Radarr (internal ID from step 1, NOT the TMDB ID)
curl -s "$RADARR_BASE/api/v3/release?movieId=<ID>" -H "X-Api-Key: $RADARR_API_KEY" | \
  python3 -c "
import sys,json
d=json.load(sys.stdin)
print('Results:', len(d) if isinstance(d,list) else d)
for r in d[:5]:
    print(r.get('indexer','?'), '|', r.get('title','?')[:60], '| seeds:', r.get('seeders',0))
"

# Sonarr
curl -s "$SONARR_BASE/api/v3/release?seriesId=<ID>&seasonNumber=<N>" -H "X-Api-Key: $SONARR_API_KEY" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print('Results:', len(d) if isinstance(d,list) else d)"
```

## Step 3: Check how many indexers are active

```bash
curl -s "$RADARR_BASE/api/v3/log?level=Info&pageSize=5" -H "X-Api-Key: $RADARR_API_KEY" | \
  python3 -c "import sys,json; [print(r['time'],r['message']) for r in json.load(sys.stdin)['records']]"
```

Look for `Searching indexers for [...]. N active indexers`. If N is less than the number of configured indexers, some are backed off or disabled.

## Step 4: Check Prowlarr indexer backoffs

Prowlarr uses **PostgreSQL** at `nas.local.abbottland.io:5432` (databases: `prowlarrdb`, `prowlarrlogdb`). **No SQLite file** — `/config` only has definitions and logs.

```bash
# Check current backoffs via API
curl -s "$PROWLARR_BASE/api/v1/indexerstatus" -H "X-Api-Key: $PROWLARR_API_KEY" | \
  python3 -c "import sys,json; [print('Indexer',s['indexerId'],'backed off until',s['disabledTill']) for s in json.load(sys.stdin)]"

# List indexers to map ID → name
curl -s "$PROWLARR_BASE/api/v1/indexer" -H "X-Api-Key: $PROWLARR_API_KEY" | \
  python3 -c "import sys,json; [print(i['id'],i['name'],i.get('enable')) for i in json.load(sys.stdin)]"
```

Note: the torznab endpoint returns the backoff directly if hit — test it:
```bash
# Port-forward and test torznab for a specific Prowlarr indexer (replace 1 with indexer ID)
kubectl port-forward -n media svc/prowlarr 19696:9696 &
sleep 3
curl -s "http://localhost:19696/1/api?apikey=$PROWLARR_API_KEY&t=movie&q=test&cat=2000"
kill %1
```

If the response is `<error code="429" description="Indexer is disabled till ...">`, the backoff is active **in-memory** even if the DB shows clear.

## Step 5: Clear Prowlarr backoff

The backoff lives in **both Postgres AND in-memory**. Must clear both.

### 1. Clear from Postgres

```bash
PG_PASS=$(kubectl get secret -n media postgres-credentials -o jsonpath='{.data.password}' | base64 -d)

kubectl run -n media pg-client --rm -it --image=postgres:alpine --restart=Never \
  --env="PGPASSWORD=$PG_PASS" -- \
  psql -h nas.local.abbottland.io -U postgres -d prowlarrdb \
  -c 'DELETE FROM "IndexerStatus" WHERE "ProviderId"=<ID>;'
```

Collation version mismatch warning is safe to ignore.

### 2. Flush in-memory state by restarting Prowlarr

```bash
kubectl rollout restart deployment/prowlarr -n media
kubectl rollout status deployment/prowlarr -n media
```

All config (indexers, app connections) is in Postgres — restart is safe. **However**: Prowlarr will re-test the indexer on startup. If the indexer is truly down (e.g. apibay.org returning 522), the backoff will immediately regenerate. Check whether the indexer is actually reachable before restarting.

### Verify the underlying indexer is working first

```bash
# Test the indexer directly via Prowlarr search (bypasses backoff)
curl -s "$PROWLARR_BASE/api/v1/search?query=test&indexerIds[]=<ID>" \
  -H "X-Api-Key: $PROWLARR_API_KEY" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print('Count:', len(d))"
```

If this returns 0, the indexer is actually down. Clearing the backoff won't help until it recovers.

## Step 6: Check indexer category config

```bash
curl -s "$RADARR_BASE/api/v3/indexer" -H "X-Api-Key: $RADARR_API_KEY" | \
  python3 -c "
import sys,json
for ix in json.load(sys.stdin):
    cats = next((f['value'] for f in ix['fields'] if f['name']=='categories'), [])
    seeds = next((f['value'] for f in ix['fields'] if f['name']=='minimumSeeders'), '?')
    print(ix['name'], '→ categories:', cats, '| minSeeders:', seeds)
"
```

Movie categories: `2000–2090`. TV categories: `5000–5090`.

## Step 7: Direct Prowlarr search

```bash
# Search all indexers for a movie
curl -s "$PROWLARR_BASE/api/v1/search?query=Incredibles+2&categories[]=2000&type=movie" \
  -H "X-Api-Key: $PROWLARR_API_KEY" | \
  python3 -c "
import sys,json
d=json.load(sys.stdin)
print('Total:', len(d))
for r in d[:5]:
    print(r.get('indexer','?'), '|', r.get('title','?')[:60], '| cats:', [c['id'] for c in r.get('categories',[])])
"

# Bypass backoff and search single indexer directly
curl -s "$PROWLARR_BASE/api/v1/search?query=<title>&indexerIds[]=<ID>" \
  -H "X-Api-Key: $PROWLARR_API_KEY" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print('Count:', len(d))"
```

Note: direct Prowlarr search ignores the backoff; Radarr/Sonarr respect it.

## Step 8: Add a missing indexer to Prowlarr

```bash
# Force Prowlarr to sync all indexers to connected apps
curl -s -X POST "$PROWLARR_BASE/api/v1/command" \
  -H "X-Api-Key: $PROWLARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "ApplicationIndexerSync"}' | python3 -c "import sys,json; d=json.load(sys.stdin); print('Status:', d.get('status'))"

# Add a new indexer (example: YTS)
curl -s -X POST "$PROWLARR_BASE/api/v1/indexer" \
  -H "X-Api-Key: $PROWLARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "YTS",
    "implementationName": "Cardigann",
    "implementation": "Cardigann",
    "configContract": "CardigannSettings",
    "enable": true,
    "appProfileId": 1,
    "priority": 1,
    "protocol": "torrent",
    "privacy": "public",
    "fields": [
      {"name": "definitionFile", "value": "yts"},
      {"name": "baseUrl", "value": "https://yts.bz/"},
      {"name": "apiurl", "value": "movies-api.accel.li"}
    ],
    "tags": []
  }' | python3 -c "import sys,json; d=json.load(sys.stdin); print('ID:', d.get('id'), d.get('name'))"
```

YTS auto-syncs to Radarr (movie-only, cats 2000/2040/2045/2060). Wait ~10s then verify in Radarr.

## Step 9: Fix "results show but only 3D/wrong quality"

Usually caused by `minimumSeeders` filtering out results with 0 seeders.

```bash
# Lower YTS minimum seeders to show all results (Radarr indexer ID 18 for YTS)
YTS_CONFIG=$(curl -s "$RADARR_BASE/api/v3/indexer/18" -H "X-Api-Key: $RADARR_API_KEY")
echo "$YTS_CONFIG" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for f in d.get('fields',[]):
    if f['name'] == 'minimumSeeders':
        f['value'] = 0
print(json.dumps(d))
" | curl -s -X PUT "$RADARR_BASE/api/v3/indexer/18" \
  -H "X-Api-Key: $RADARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d @- | python3 -c "import sys,json; d=json.load(sys.stdin); print('Updated:', d.get('name'))"
```

## Step 10: Fix indexer that won't sync — cardigann category bug

Some indexers (e.g. LimeTorrents) sync to Sonarr but not Radarr because keyword searches return results with no movie category. The cardigann definition scrapes category from page HTML that only appears on browse/RSS pages, not keyword search result pages. Prowlarr's sync test uses a keyword-less browse, but if that also fails to categorize, Radarr rejects it.

**Diagnose**: check Prowlarr warn logs after `ApplicationIndexerSync`:

```bash
curl -s "$PROWLARR_BASE/api/v1/log?level=Warn&pageSize=20" -H "X-Api-Key: $PROWLARR_API_KEY" | \
  python3 -c "
import sys,json
for r in json.load(sys.stdin).get('records',[]):
    if 'sync' in r.get('message','').lower() or 'category' in r.get('message','').lower():
        print(r['time'][:19], r['message'][:300])
"
```

If you see `No Results in configured categories`, the definition is failing to extract categories.

**Fix**: patch the cardigann YAML to hardcode category fallback to "Movies" instead of "Other":

```bash
# For LimeTorrents
kubectl exec -n media deployment/prowlarr --context prod-gen2 -- sh -c "
sed -i 's/default: \"{{ if .Result.category_is_tv_show }}TV shows{{ else }}Other{{ end }}\"/default: \"{{ if .Result.category_is_tv_show }}TV shows{{ else }}Movies{{ end }}\"/' /config/Definitions/limetorrents.yml
chmod 444 /config/Definitions/limetorrents.yml
grep -n 'Movies' /config/Definitions/limetorrents.yml | grep -v '^27:\|^31:\|^72:'
"
```

The `chmod 444` prevents Prowlarr's daily `IndexerDefinitionUpdate` task from overwriting the patch. If Prowlarr ever updates to a version that fixes the definition upstream, reset with `chmod 644` and let the update run.

Then re-sync to apps:

```bash
curl -s -X POST "$PROWLARR_BASE/api/v1/command" \
  -H "X-Api-Key: $PROWLARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "ApplicationIndexerSync"}' | python3 -c "import sys,json; d=json.load(sys.stdin); print('Status:', d.get('status'))"
```

## Common failures and fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `N active indexers` < configured count | Indexer in backoff | Steps 4–5 |
| Backoff clears but immediately regenerates after restart | Underlying indexer is down (e.g. apibay.org 522) | Fix the indexer or add a replacement |
| 0 results but Prowlarr direct search finds content | Radarr category filter or seeders filter | Steps 6, 9 |
| Only 3D / low quality results visible | Other versions have 0 seeders | Lower minimumSeeders (Step 9) |
| Indexer in Prowlarr/Sonarr but not syncing to Radarr | Cardigann definition extracts wrong category on keyword search | Patch definition default from `Other` to `Movies`, chmod 444 (Step 10) |
| Indexer add fails with "CloudFlare Protection" | Site uses Cloudflare | Need FlareSolverr; not currently deployed |
| `ApplicationIndexerSync` returns no status | Wrong command name | Use `ApplicationIndexerSync` (not `SyncApplications`) |
| Collation version mismatch on psql | Postgres upgrade | Safe to ignore; or `ALTER DATABASE prowlarrdb REFRESH COLLATION VERSION;` |

## Infrastructure notes

- **Prowlarr DB**: PostgreSQL at `nas.local.abbottland.io:5432`, database `prowlarrdb`
- **DB creds**: `postgres-credentials` secret in `media` namespace (user `postgres`)
- **No SQLite** — config is in Postgres, `/config` PVC only has definitions, logs, backups
- **Prowlarr restart is safe** — all indexer config survives in Postgres
- **FlareSolverr not deployed** — 1337x and kickasstorrents.ws won't work
- **apibay.org** is the TPB API endpoint; when it returns 522, TPB backsoff indefinitely
- **TPB `apiurl`** setting is configurable but no known working alternative to `apibay.org`
- **Cardigann definitions** live on the `/config` PVC (`/config/Definitions/`). Prowlarr updates them daily via `IndexerDefinitionUpdate` task. `chmod 444` on a patched file blocks the overwrite.

## Current indexers (as of 2026-06-15)

| Prowlarr ID | Name | Good for | Notes |
|-------------|------|----------|-------|
| 1 | The Pirate Bay | General | Uses apibay.org; goes down periodically |
| 8 | Nyaa.si | Anime TV | Synced to Radarr but anime-only results |
| 9 | AnimeTosho | Anime TV | Same — anime only despite movie cats |
| 10 | LimeTorrents | General | Radarr ID 19; cardigann patched (chmod 444) to return Movies cat; good seeded results |
| 11 | YTS | Movies | Radarr ID 18; best Radarr source; set minSeeders=0 to see all |
