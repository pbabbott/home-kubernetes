#!/usr/bin/env bash
# Usage: check-queue.sh <title keyword>
source /workspaces/home-kubernetes/.env
RADARR_BASE=https://radarr.local.abbottland.io
KEYWORD="${*,,}"
curl -s "$RADARR_BASE/api/v3/queue?pageSize=100" -H "X-Api-Key: $RADARR_API_KEY" | python3 -c "
import sys,json
records = json.load(sys.stdin).get('records', [])
target = [r for r in records if '${KEYWORD}'.lower() in r.get('title','').lower()]
print('Queue entries:', len(target))
for r in target[:3]:
    print('  Title:', r.get('title','?')[:70])
    print('  Status:', r.get('status'), '| State:', r.get('trackedDownloadState'))
    print('  Size:', round(r.get('size',0)/1024/1024/1024, 2), 'GB')
"
