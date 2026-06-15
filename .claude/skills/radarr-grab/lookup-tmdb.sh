#!/usr/bin/env bash
# Usage: lookup-tmdb.sh <search term>
source /workspaces/home-kubernetes/.env
RADARR_BASE=https://radarr.local.abbottland.io
curl -s "$RADARR_BASE/api/v3/movie/lookup?term=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(' '.join(sys.argv[1:])))" "$@")" \
  -H "X-Api-Key: $RADARR_API_KEY" | python3 -c "
import sys,json
results = json.load(sys.stdin)[:5]
if not results:
    print('No results found')
else:
    for m in results:
        print('tmdbId:', m.get('tmdbId'), '| title:', m.get('title'), '| year:', m.get('year'))
"
