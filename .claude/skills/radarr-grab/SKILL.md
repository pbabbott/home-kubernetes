---
name: radarr-grab
description: Find a good torrent for a specific movie and add it to Radarr — search releases, evaluate seeds/quality, confirm with user, grab
---

User wants to download a specific movie via Radarr. Get movie title from user. **Always confirm with user before grabbing.**

Scripts live in `.claude/skills/radarr-grab/`. All are auto-approved via settings allowlist.

## Auth

```bash
source /workspaces/home-kubernetes/.env
RADARR_BASE=https://radarr.local.abbottland.io
```

## Step 1: Find movie in Radarr

```bash
bash .claude/skills/radarr-grab/lookup-movie.sh <search term>
```

If not found, add it (Step 1b).

## Step 1b: Add movie to Radarr (if not present)

First lookup TMDB ID:
```bash
bash .claude/skills/radarr-grab/lookup-tmdb.sh <search term>
```

Then add:
```bash
bash .claude/skills/radarr-grab/add-movie.sh <tmdbId>
```

Default quality profile: **5 (Ultra-HD)**. Root folder: `/data/media/movies`.

## Step 2: Search releases

```bash
bash .claude/skills/radarr-grab/search-releases.sh <movieId>
```

## Step 3: Evaluate and present options to user

Pick top candidates and show:

| # | Title | Seeds | Size | Quality | Approved |
|---|-------|-------|------|---------|----------|
| 1 | ... | N | X GB | Bluray-2160p | ✓ |

**Quality guidance:**
- Prefer 2160p (Ultra-HD) with good seeds
- `approved: True` = passes quality profile; prefer these
- YTS: small/clean x265 — good default
- Remux: 50–80 GB lossless — only if user wants best possible
- Rejected releases may still be grabbed; check `rejections` for reason (often just quality profile mismatch)

**Always confirm with user before proceeding.**

## Step 4: Grab by rank

```bash
bash .claude/skills/radarr-grab/grab-by-rank.sh <movieId> <rank>
```

`rank` is 1-indexed matching the number shown in search-releases output.

## Step 5: Verify in queue

```bash
bash .claude/skills/radarr-grab/check-queue.sh <title keyword>
```

## Quality profiles

| ID | Name |
|----|------|
| 1 | Any |
| 4 | HD-1080p |
| 5 | Ultra-HD |
| 6 | HD - 720p/1080p |

If a release is rejected due to quality profile mismatch, update the movie's profile before grabbing:
```bash
source /workspaces/home-kubernetes/.env
RADARR_BASE=https://radarr.local.abbottland.io
MOVIE=$(curl -s "$RADARR_BASE/api/v3/movie/<ID>" -H "X-Api-Key: $RADARR_API_KEY")
UPDATED=$(echo "$MOVIE" | python3 -c "import sys,json; d=json.load(sys.stdin); d['qualityProfileId']=5; print(json.dumps(d))")
curl -s -X PUT "$RADARR_BASE/api/v3/movie/<ID>" -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" -d "$UPDATED" | python3 -c "import sys,json; d=json.load(sys.stdin); print('qualityProfileId:', d.get('qualityProfileId'))"
```

## Known indexer notes (as of 2026-06-15)

| Indexer | Radarr indexerId | Notes |
|---------|-----------------|-------|
| YTS | 18 | Movies only; clean x265; 720p/1080p/2160p |
| LimeTorrents | ? | General; broad coverage including remux/4K |
| The Pirate Bay | ? | General |
