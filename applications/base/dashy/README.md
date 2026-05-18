# Dashy Helm Chart

Local Helm chart wrapping the [Dashy](https://dashy.to) dashboard, deployed to prod-gen2 and non-prod-gen2.

## Structure

| Path | Purpose |
|------|---------|
| `templates/configmap.yaml` | Dashboard config rendered via Helm values |
| `values.yaml` | Base defaults (non-prod-safe) |
| `../../prod-gen2/dashy/helmrelease.yaml` | Prod overrides |
| `../../non-prod-gen2/dashy/helmrelease.yaml` | Non-prod overrides |

## Conventions

**URLs are always Helm template vars** — never hardcode service URLs in `configmap.yaml`. Add new URLs to `values.yaml` and both `helmrelease.yaml` files. Prod and non-prod use different subdomains (`*.local.abbottland.io` vs `*.local.non-prod.abbottland.io`).

**Optional sections use conditionals** — sections that should not appear on every cluster are wrapped with `{{- if .Values.sections.<flag> }}` / `{{- end }}`. The base `values.yaml` defaults to `false`; enable per cluster in the relevant `helmrelease.yaml`.

## Section flags

| Flag | prod-gen2 | non-prod-gen2 | Notes |
|------|-----------|---------------|-------|
| `sections.mediaEnabled` | `true` | `false` | qBittorrent, Plex, Servarr stack |
| `sections.appsEnabled` | `true` | `false` | Personal apps (blog, diagram maker, etc.) |

## Versioning

**Bump `Chart.yaml` patch version on every change** — Flux uses the chart version to detect updates. Without a bump, changes may not reconcile. Increment `version` in `Chart.yaml` (e.g. `0.1.12` → `0.1.13`) for every PR that touches this chart.

## Adding a new section

1. Add `{{- if .Values.sections.<newFlag> }}` block to `configmap.yaml`
2. Add `<newFlag>: false` under `sections:` in `values.yaml`
3. Set `<newFlag>: true` in whichever `helmrelease.yaml` should show it
