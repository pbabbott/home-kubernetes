---
name: plex-collection
description: Add or remove movies/shows from a named Plex collection — search library by title, resolve ratingKey, PUT into collection by name
---

User wants to manage a Plex collection (add/remove items, rename, create). Get collection name and movie/show titles from user. **Confirm before removing items.**

## Auth

```bash
source /workspaces/home-kubernetes/.env
PLEX_BASE=https://192.168.4.124:32400
MACHINE_ID=48c52a8de213a6b0f3612495444d29c912aceb26
# PLEX_TOKEN is set by sourcing .env
```

Note: Plex uses self-signed cert — always pass `-sk` to curl.

## Library section IDs

| ID | Type | Title |
|----|------|-------|
| 1  | movie | Movies |
| 2  | show  | TV Shows |

## Step 1: Find collection by name

```bash
curl -sk -H "X-Plex-Token: $PLEX_TOKEN" \
  "$PLEX_BASE/library/sections/1/collections" | \
  grep -oP 'ratingKey="\K[^"]+|title="\K[^"]+' | paste - -
```

Use section `2` for TV collections. The `ratingKey` is the collection ID needed for all subsequent calls.

## Step 2: Find movie/show by title

```bash
curl -sk -H "X-Plex-Token: $PLEX_TOKEN" \
  "$PLEX_BASE/library/sections/1/all?title=<Title>&type=1" | \
  grep -oP 'ratingKey="\K[^"]+|title="\K[^"]+' | paste - -
```

Use `type=1` for movies, `type=4` for shows. Title search is case-insensitive substring match — verify the returned title matches what the user asked for before proceeding (multiple results may appear).

## Step 3: Add item to collection

```bash
curl -sk -X PUT -H "X-Plex-Token: $PLEX_TOKEN" \
  "$PLEX_BASE/library/collections/<COLLECTION_RATINGKEY>/items?uri=server://$MACHINE_ID/com.plexapp.plugins.library/library/metadata/<ITEM_RATINGKEY>" \
  -w "%{http_code}\n" -o /dev/null
```

200 = success. Repeat per item — bulk URI format does not work.

## Step 4: Verify collection contents

```bash
curl -sk -H "X-Plex-Token: $PLEX_TOKEN" \
  "$PLEX_BASE/library/collections/<COLLECTION_RATINGKEY>/children" | \
  grep -oP 'title="\K[^"]+'
```

## Optional: Remove item from collection

**Confirm with user before removing.**

```bash
curl -sk -X DELETE -H "X-Plex-Token: $PLEX_TOKEN" \
  "$PLEX_BASE/library/collections/<COLLECTION_RATINGKEY>/items/<ITEM_RATINGKEY>" \
  -w "%{http_code}\n" -o /dev/null
```

## Optional: Rename collection

```bash
curl -sk -X PUT -H "X-Plex-Token: $PLEX_TOKEN" \
  "$PLEX_BASE/library/collections/<COLLECTION_RATINGKEY>?title=<New+Title>&titleSort=<New+Title>" \
  -w "%{http_code}\n" -o /dev/null
```

## Optional: Create new collection

Add first item with a `collection[0].tag` param to auto-create:

```bash
curl -sk -X POST -H "X-Plex-Token: $PLEX_TOKEN" \
  "$PLEX_BASE/library/sections/1/all?type=1&id=<ITEM_RATINGKEY>&collection[0].tag.tag=<Collection+Name>" \
  -w "%{http_code}\n" -o /dev/null
```

Then add remaining items via Step 3.

## Common issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| 400 Bad Request on search | Wrong endpoint — `/search` not valid | Use `/all?title=<query>&type=1` |
| 404 on bulk PUT | Comma-separated IDs in URI not supported | Add items one at a time |
| Multiple results returned | Title is substring match | Check year field or pick exact match |
| Self-signed cert error | Plex uses self-signed TLS | Always use `curl -sk` |
