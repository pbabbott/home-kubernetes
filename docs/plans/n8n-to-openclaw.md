# Replace n8n with OpenClaw (prod-gen2)

Status: manifests written in working tree, **uncommitted, not applied**. Pick up from "Remaining steps".

## Done (working tree only)

- Removed `applications/base/n8n/`, `applications/prod-gen2/n8n/`, `./n8n` entry in `applications/prod-gen2/kustomization.yaml`.
- Removed `scripts/get-n8n-api-key.sh`, `n8n` server in `.mcp.json`, n8n section in `docs/ai-reference-infra.md`.
- Added `applications/base/openclaw/` + `applications/prod-gen2/openclaw/`, wired into `applications/prod-gen2/kustomization.yaml`.
  - Image `ghcr.io/openclaw/openclaw:2026.7.1-2-slim`, port 18789, Recreate strategy, 10Gi Longhorn PVC.
  - Init container seeds `openclaw.json` + `AGENTS.md` from ConfigMap only if missing on PVC (PVC copy is source of truth after first run).
  - Local HTTPRoute only: `openclaw.local.abbottland.io` (pihole DNS). No public route.
  - NetworkPolicy: ingress from `istio-system` only; egress DNS + 443.
  - Secrets via `OnePasswordItem` -> `openclaw-secrets` (envFrom).
- `kubectl kustomize applications/prod-gen2/openclaw` builds OK.
- Reference: https://docs.openclaw.ai/install/kubernetes.md

## Remaining steps

1. **Create 1Password item** `openclaw` in Homelab vault with fields:
   - `OPENCLAW_GATEWAY_TOKEN` (random string)
   - (No LLM API key: model is local LM Studio at `192.168.5.142:1234`, `google/gemma-4-e4b`, configured in `openclaw-config-configmap.yaml` as `lmstudio` provider. Port 1234 = LM Studio, OpenAI-compatible `/v1`, not Ollama.)
2. **Verify gateway bind + model config.** Also confirm `contextWindow` (32768 guessed) matches LM Studio load setting, and that `/v1/models` on the server lists `google/gemma-4-e4b`. ConfigMap sets `"bind": "lan"`. Upstream default is `loopback`, unreachable from Istio. Confirm correct value in OpenClaw config docs.
3. **Review diff** (`git status` / `git diff`), then commit (conventional commit) and push.
4. **Reconcile**: `flux reconcile kustomization <apps-ks> --with-source`; watch `kubectl -n openclaw get pods`.
5. **Verify**:
   - `kubectl -n openclaw get onepassworditem,secret,pvc`
   - Pod passes `/startupz`, `/readyz`.
   - `https://openclaw.local.abbottland.io` loads; gateway token auth works.
   - Pihole record exists (see `docs/ai-reference-httproute-dns.md`).
6. **n8n cleanup** after Flux prune:
   - `kubectl get ns n8n` — delete manually if prune is off.
   - Drop `n8n` database on NAS Postgres (192.168.4.124) if no longer wanted.
   - Delete `n8n` / `n8n-api-key` items in 1Password.
   - Remove n8n entries from `.claude/settings.local.json`.
   - Remove public DNS record `n8n.abbottland.io` in Cloudflare if external-dns doesn't.
   - `community-charts` HelmRepository was deleted with n8n; confirm nothing else used it (grep was inconclusive due to a zsh glob error — rerun `grep -rn community-charts --include='*.yaml' .`).

## Open decisions

- Public exposure: currently local-only. If public needed, add Cloudflare HTTPRoute per `docs/ai-reference-httproute-dns.md` (NetworkPolicy already allows `istio-system`).
- Image update automation: skipped (local-only, pinned tag). CLAUDE.md requires it only for public apps. Add `ImageRepository` + `ImagePolicy` + marker if wanted.
- Egress: currently 443 + `192.168.5.142:1234` (LM Studio). Add rules if OpenClaw needs NAS, other LAN services, or non-443 providers.
- Resources: requests 100m / 512Mi, limit 2Gi memory. Tune after observing.
