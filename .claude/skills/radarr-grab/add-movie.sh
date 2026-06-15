#!/usr/bin/env bash
# Usage: add-movie.sh <tmdbId>
source /workspaces/home-kubernetes/.env
RADARR_BASE=https://radarr.local.abbottland.io
TMDB_ID="$1"
MOVIE=$(curl -s "$RADARR_BASE/api/v3/movie/lookup/tmdb?tmdbId=$TMDB_ID" -H "X-Api-Key: $RADARR_API_KEY")
PAYLOAD=$(echo "$MOVIE" | python3 -c "
import sys,json
d=json.load(sys.stdin)
d['qualityProfileId'] = 5
d['rootFolderPath'] = '/data/media/movies'
d['monitored'] = True
d['addOptions'] = {'searchForMovie': False}
print(json.dumps(d))
")
curl -s -X POST "$RADARR_BASE/api/v3/movie" \
  -H "X-Api-Key: $RADARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('id:', d.get('id'), '| title:', d.get('title'), '| qualityProfileId:', d.get('qualityProfileId'))
"
