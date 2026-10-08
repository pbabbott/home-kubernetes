# n8n -> OpenClaw: Manual Steps

Companion to `n8n-to-openclaw.md`. Steps that need a human (secrets, external systems, cleanup).

## Before deploy

1. **1Password:** create item `openclaw` in Homelab vault with field `OPENCLAW_GATEWAY_TOKEN` (random, e.g. `openssl rand -hex 32`).
2. **LM Studio** (192.168.5.142:1234):
   - Server running and listening on LAN (not just localhost).
   - `google/gemma-4-e4b` loaded; listed by `curl http://192.168.5.142:1234/v1/models`.
   - Note loaded context length; update `contextWindow` in `applications/base/openclaw/openclaw-config-configmap.yaml` (currently guessed 32768).
   - If model is text-only, drop `"image"` from `input`.
3. ~~Config check~~ **Done** against docs (openclaw 2026.9.9): `bind: "lan"` valid (0.0.0.0; non-loopback requires auth, token supplied). LM Studio provider schema matches docs. Added `gateway.publicOrigin` for Control UI behind Istio HTTPS. Startup probe changed to `/readyz` (`/startupz` needs image >= 2026.8.1; pinned 2026.7.1-2 lacks it). Optional: bump image tag to a newer `-slim` and switch back to `/startupz`.
4. **Export n8n workflows/credentials** (UI or API) before n8n is removed, if anything is worth keeping. Data stays in NAS Postgres but nothing reads it afterward.

## Deploy

5. Review diff; commit and push. Exclude unrelated `applications/base/media/` changes.
6. `flux reconcile` the apps kustomization; watch `kubectl -n openclaw get pods`.
7. Open `https://openclaw.local.abbottland.io`, log in with gateway token, send a test message to confirm the model responds.
8. Rebuild any needed n8n automations (webhooks, schedules) in OpenClaw. No migration path.

## Cleanup

9. **Namespace:** `kubectl get ns n8n`; delete manually if Flux did not prune (removes PVCs/secrets).
10. **Database:** drop `n8n` database on NAS Postgres (192.168.4.124).
11. **1Password:** delete `n8n` and `n8n-api-key` items.
12. **DNS:**
    - Pi-hole: confirm `n8n.local.abbottland.io` record gone.
    - Cloudflare: confirm `n8n.abbottland.io` gone.
    - Delete manually if external-dns left either.
13. **Repo/local leftovers:**
    - Remove n8n entries from `.claude/settings.local.json`.
    - Rerun `grep -rn community-charts --include='*.yaml' .` to confirm nothing else used the deleted HelmRepository.
14. **Env:** unset `N8N_API_KEY` in shell profile / devcontainer env if set.
