# Radarr: An die Grenze (2007) — Search Notes

**Radarr URL:** https://radarr.local.abbottland.io/movie/12136  
**TMDB ID:** 12136 | **IMDB ID:** tt0874850  
**Radarr internal ID:** 420  
**Status:** monitored=true, hasFile=false  

## What We Tried

| Method | Result |
|--------|--------|
| `GET /api/v3/release?movieId=420` | 0 results |
| Prowlarr search: `An die Grenze` (category 2000) | 0 results |
| Prowlarr search: `An die Grenze 2007` (no category) | 0 results |
| Prowlarr search: `Grenze 2007` | 0 results |
| Prowlarr IMDB ID search (`tt0874850`) | returned unrelated dump of all YTS movies |
| YTS only (indexer 11): `An die Grenze` | 0 results |
| TPB (indexer 1): `An die Grenze` | 0 results |
| LimeTorrents (indexer 10): `An die Grenze` | 0 results |
| Radarr `MoviesSearch` command (all indexers) | completed, 0 reports downloaded |

Prowlarr health: clean (no warnings, no indexer backoffs).

## Active Indexers

| Prowlarr ID | Name | Movie support |
|-------------|------|---------------|
| 11 | YTS | yes (primary movies indexer) |
| 1 | The Pirate Bay | general |
| 10 | LimeTorrents | general |
| 9 | AnimeTosho | anime focus |
| 8 | Nyaa.si | anime focus |

## Why It's Missing

Obscure 2007 German TV film. Not on YTS (only publishes popular/mainstream titles). TPB/LimeTorrents have sparse coverage of non-English content.

## Possible Next Steps

1. **Add 1337x to Prowlarr** — broad coverage, European content, good for older/foreign films
2. **Add a RARBG mirror** — archived RARBG dump has wide historical coverage
3. **Find magnet manually** (e.g., 1337x.to, solidtorrents.to, btdig.com) and drop in qBittorrent watched folder — Radarr will auto-import
4. **Usenet** — add an NZB indexer (NZBGeek, NZBFinder) if Usenet access available; better for obscure foreign content
5. **German-specific tracker** — e.g., HDArea, German-language private tracker
6. **Check alternate English title** — may be released as "To the Border" or similar; retry searches with English title
