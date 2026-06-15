#!/usr/bin/env bash
# Usage: grab-by-rank.sh <movieId> <rank>
# rank is 1-indexed (1 = top result by seeds)
source /workspaces/home-kubernetes/.env
RADARR_BASE=https://radarr.local.abbottland.io
MOVIE_ID="$1"
RANK="${2:-1}"

RELEASE=$(curl -s "$RADARR_BASE/api/v3/release?movieId=$MOVIE_ID" -H "X-Api-Key: $RADARR_API_KEY" | python3 -c "
import sys,json
d=json.load(sys.stdin)
d.sort(key=lambda r: r.get('seeders',0), reverse=True)
idx = $RANK - 1
if idx >= len(d):
    print('ERROR: rank $RANK out of range (total: ' + str(len(d)) + ')', file=sys.stderr)
    sys.exit(1)
r = d[idx]
print(r.get('guid',''))
print(r.get('indexerId',''))
print(r.get('title',''))
")

GUID=$(echo "$RELEASE" | sed -n '1p')
INDEXER_ID=$(echo "$RELEASE" | sed -n '2p')
TITLE=$(echo "$RELEASE" | sed -n '3p')

if [ -z "$GUID" ] || [ -z "$INDEXER_ID" ]; then
    echo "ERROR: could not extract guid/indexerId"
    exit 1
fi

echo "Grabbing: $TITLE"
echo "guid: $GUID"
echo "indexerId: $INDEXER_ID"

curl -s -X POST "$RADARR_BASE/api/v3/release" \
  -H "X-Api-Key: $RADARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"guid\": \"$GUID\", \"indexerId\": $INDEXER_ID}" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('approved:', d.get('approved'), '| rejected:', d.get('rejected'), '| rejections:', d.get('rejections'))
print('(ambiguous response is normal — verify via check-queue.sh)')
"
