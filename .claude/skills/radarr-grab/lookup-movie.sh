#!/usr/bin/env bash
# Usage: lookup-movie.sh <search term>
source /workspaces/home-kubernetes/.env
RADARR_BASE=https://radarr.local.abbottland.io
TERM="${*,,}"
curl -s "$RADARR_BASE/api/v3/movie" -H "X-Api-Key: $RADARR_API_KEY" | python3 -c "
import sys,json
term = '${TERM}'.lower()
results = [m for m in json.load(sys.stdin) if term in m['title'].lower()]
if not results:
    print('Not found in Radarr')
else:
    for m in results:
        print('id:', m['id'], '| title:', m['title'], '| year:', m.get('year',''), '| monitored:', m.get('monitored'), '| hasFile:', m.get('hasFile'))
"
