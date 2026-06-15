#!/usr/bin/env bash
# Usage: grab-release.sh <guid> <indexerId>
source /workspaces/home-kubernetes/.env
RADARR_BASE=https://radarr.local.abbottland.io
curl -s -X POST "$RADARR_BASE/api/v3/release" \
  -H "X-Api-Key: $RADARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"guid\": \"$1\", \"indexerId\": $2}" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('approved:', d.get('approved'), '| rejected:', d.get('rejected'), '| rejections:', d.get('rejections'))
print('(ambiguous response is normal — verify via check-queue.sh)')
"
