---
name: sonarr-grab
description: Find a good torrent for a specific TV series/season and add it to Sonarr — search Prowlarr, evaluate seeds/quality, confirm with user, enable monitoring, grab
---

User wants to download a specific TV series season via Sonarr. Get series name and season number from user. **Always confirm with user before grabbing.**

## Auth

```bash
source /workspaces/home-kubernetes/.env
SONARR_BASE=https://sonarr.local.abbottland.io
PROWLARR_BASE=https://prowlarr.local.abbottland.io
```

Note: `SONARR_BASE` is NOT set in `.env` — always set it explicitly.

## Step 1: Find series in Sonarr

```bash
curl -s "$SONARR_BASE/api/v3/series" -H "X-Api-Key: $SONARR_API_KEY" | \
  python3 -c "
import sys,json
term = '<search term>'.lower()
[print(s['id'], s['title'], s.get('tvdbId','')) for s in json.load(sys.stdin)
 if term in s['title'].lower()]
"
```

If not found, the series may need to be added to Sonarr first (out of scope for this skill — add via UI).

## Step 2: Check season exists and current monitoring state

```bash
curl -s "$SONARR_BASE/api/v3/series/<ID>" -H "X-Api-Key: $SONARR_API_KEY" | \
  python3 -c "
import sys,json
d=json.load(sys.stdin)
print('Title:', d['title'])
for s in d.get('seasons',[]):
    stats = s.get('statistics',{})
    print(f\"S{s['seasonNumber']:02d}: monitored={s['monitored']} eps={stats.get('totalEpisodeCount','?')}\")
"
```

## Step 3: Search Sonarr release endpoint for the season

This searches all indexers synced to Sonarr:

```bash
curl -s "$SONARR_BASE/api/v3/release?seriesId=<ID>&seasonNumber=<N>" \
  -H "X-Api-Key: $SONARR_API_KEY" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('Total:', len(d))
d.sort(key=lambda r: r.get('seeders',0), reverse=True)
for r in d[:20]:
    print(
        r.get('seeders','?'), 'seeds |',
        r.get('quality',{}).get('quality',{}).get('name','?'), '|',
        r.get('indexer','?'), '|',
        r.get('title','?')[:80]
    )
"
```

## Step 4: Prowlarr direct search (catches what Sonarr misses)

Useful when Sonarr results look wrong or incomplete:

```bash
curl -s "$PROWLARR_BASE/api/v1/search?query=<Title+Season+Keywords>&categories[]=5000&type=search" \
  -H "X-Api-Key: $PROWLARR_API_KEY" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('Total:', len(d))
d.sort(key=lambda r: r.get('seeders',0), reverse=True)
for r in d[:20]:
    print(r.get('seeders','?'), 'seeds |', r.get('indexer','?'), '|', r.get('title','?')[:90])
"
```

Note: Prowlarr direct search bypasses backoffs and finds releases Sonarr may not surface. However, releases found only via Prowlarr (not in Sonarr's `/release` results) need a manual push using their GUID and indexer ID.

## Step 5: Evaluate and present options to user

Pick top candidates and show:

| # | Title | Seeds | Size | Source | Notes |
|---|-------|-------|------|--------|-------|
| 1 | ... | N | X GB | indexer | quality notes |

**Quality guidance for classic/older shows:**
- DVD is often the best authentic source for pre-2010 anime/shows — no real 720p/1080p exists
- Season packs preferred over individual episode torrents for Sonarr
- `fullSeason: true` in Sonarr release JSON = season pack, maps to all episodes
- Suspicious: complete season under ~2 GB usually means very low quality
- Check `languages` field to verify English dub if needed
- `approved: true` in Sonarr release JSON = passes quality profile; grab it

**Always confirm with user before proceeding.**

## Step 6: Enable season monitoring

```bash
SERIES=$(curl -s "$SONARR_BASE/api/v3/series/<ID>" -H "X-Api-Key: $SONARR_API_KEY")
UPDATED=$(echo "$SERIES" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for s in d['seasons']:
    if s['seasonNumber'] == <N>:
        s['monitored'] = True
print(json.dumps(d))
")
curl -s -X PUT "$SONARR_BASE/api/v3/series/<ID>" \
  -H "X-Api-Key: $SONARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$UPDATED" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for s in d.get('seasons',[]):
    if s['seasonNumber'] == <N>:
        print('S0<N> monitored:', s['monitored'])
"
```

## Step 7: Grab the release

Use the `guid` and `indexerId` from the Sonarr release search result:

```bash
curl -s -X POST "$SONARR_BASE/api/v3/release" \
  -H "X-Api-Key: $SONARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"guid": "<guid>", "indexerId": <indexerId>}' | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('approved:', d.get('approved'))
print('rejected:', d.get('rejected'))
print('rejections:', d.get('rejections'))
"
```

Note: ambiguous response (approved=False, rejected=False, empty title) is normal for a successful grab — always verify via queue.

## Step 8: Verify in queue

```bash
curl -s "$SONARR_BASE/api/v3/queue?pageSize=100" -H "X-Api-Key: $SONARR_API_KEY" | python3 -c "
import sys,json
d=json.load(sys.stdin)
records = d.get('records', [])
target = [r for r in records if '<title keyword>'.lower() in r.get('title','').lower()]
ids = set(r.get('downloadId','') for r in target)
print(f'Queue entries: {len(target)} | Unique downloads: {len(ids)}')
for r in target[:3]:
    print('  Status:', r.get('status'), '| State:', r.get('trackedDownloadState'))
    print('  Size:', round(r.get('size',0)/1024/1024/1024, 2), 'GB')
    break
"
```

Multiple queue entries with 1 unique `downloadId` = correct. Sonarr creates one entry per episode from season pack, all pointing to the same torrent.

## Known indexer notes (as of 2026-06-15)

| Prowlarr ID | Sonarr indexerId | Name | Notes |
|-------------|-----------------|------|-------|
| 8 | 16 | Nyaa.si | Best for anime; classic series often here |
| 9 | ? | AnimeTosho | Anime; mirrors Nyaa |
| 1 | ? | The Pirate Bay | General; check quality carefully |
| 10 | 15 | LimeTorrents | General TV; good for recent content |
| 11 | ? | YTS | Movies only |

## Common issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Sonarr season search returns wrong show's episodes | TVDB season numbering mismatch | Use Prowlarr direct search with specific title keywords |
| Release in Prowlarr but not Sonarr results | Category mismatch or indexer not synced for TV | Push via GUID + indexerId from Prowlarr result |
| 10+ same entry in queue | Normal for season pack | Verify unique downloadId count = 1 |
| `approved: False` on POST response | Normal — response format differs from GET | Check queue instead |
