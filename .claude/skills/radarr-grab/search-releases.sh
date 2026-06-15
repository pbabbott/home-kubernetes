#!/usr/bin/env bash
# Usage: search-releases.sh <movieId>
source /workspaces/home-kubernetes/.env
RADARR_BASE=https://radarr.local.abbottland.io
curl -s "$RADARR_BASE/api/v3/release?movieId=$1" -H "X-Api-Key: $RADARR_API_KEY" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('Total:', len(d))
d.sort(key=lambda r: r.get('seeders',0), reverse=True)
for i,r in enumerate(d[:15], 1):
    print(
        f\"{i}.\",
        r.get('seeders','?'), 'seeds |',
        r.get('quality',{}).get('quality',{}).get('name','?'), '|',
        round(r.get('size',0)/1024/1024/1024, 2), 'GB |',
        'approved:', r.get('approved'), '|',
        r.get('indexer','?'), '|',
        r.get('title','?')[:70]
    )
"
