# home-kubernetes

Flux GitOps repo for my homelab's k3s cluster. Only `prod-gen3` is live. Overview, contribution docs and the full app/infra inventory: `README.md`.

## Layout

| Path | Purpose |
|---|---|
| `clusters/prod-gen3/` | Flux entry points, applied in order: `00-crds-ks` → `01-infra-ks` → `02-apps-ks` → `03-flux-gitops-ks` (Flux web UI + MCP) |
| `crds/` | CRD installs (`base/` + `prod-gen3/`), applied before anything that uses them |
| `infra/` | Cluster infrastructure. `base/` + `prod-gen3/` overlay, grouped `<category>/<component>` |
| `apps/` | Workloads. `base/` + `prod-gen3/` overlay, grouped `<category>/<app>`; overlays are thin patches (hostnames, sizing) |
| `docs/` | Guides, references, plans, incidents; map below |
| `scripts/` | Helpers for secrets, Grafana and Longhorn restores. Manifest: `scripts/CLAUDE.md` |

Hosts, VMs and IPs live in `home-playbooks/docs/HOSTS.md`; the cluster itself is built by `home-playbooks/playbooks/kubernetes-gen3/`.

## How the infra fits together

- **Ingress**: eero forwards 80/443 to the HAProxy LXC `192.168.6.29`, which fronts Istio (ambient mesh + Gateway API) on the gen3 workers. Two Gateways: `istio-ingress` (internal, `*.local.abbottland.io`) and `istio-ingress-public` (`*.abbottland.io`). `docs/ai-reference/httproute-dns.md`
- **external-dns**: two instances build all DNS from HTTPRoutes: Cloudflare for public `*.abbottland.io`, Pi-hole (on `bananapi`) for internal `*.local.abbottland.io`. The DNS target comes from the Gateway annotation. Never create records by hand (Pi-hole runs `sync`); use an HTTPRoute or a `DNSEndpoint`. `docs/ai-reference/external-dns-pihole.md`, `docs/ai-reference/pihole-api.md`; for DNS questions use the `dns-expert` agent.
- **Secrets**: 1Password Connect operator turns `OnePasswordItem`s into Secrets; sealed-secrets exists only to bootstrap the Connect credentials. `docs/ai-reference/secrets.md` (start here), `docs/ai-reference/onepassword-operator.md`, `docs/reference/secret-management-strategy.md`
- **Storage**: Longhorn (replicated block on the worker SSDs, backups to the NAS) for app config and databases; `nas-storage` (NFS on the Asustor NAS `192.168.4.124`) for bulk data and media. Postgres and Redis also live on the NAS. `.cursor/k8s-storage-classes.md`, `docs/ai-reference/infra.md`
- **cert-manager**: Let's Encrypt via Cloudflare DNS-01 issues the wildcard certs on the two Gateways.
- **pihole** (in `infra/`, not `apps/`): proxy route to the Pi-hole UI; external-dns depends on it so it must reconcile first.
- **Observability**: kube-prometheus-stack (Prometheus, Grafana; Alertmanager deliberately disabled); k3s control plane + kube-proxy scraped via node IPs (needs the k3s args in `home-playbooks`); dashboards are gitops-managed ConfigMaps.
- **Flux**: The `FluxInstance` is bootstrapped by Ansible (`home-playbooks`), not by this repo. `docs/developer-guides/flux-bootstrap.md`, `docs/developer-guides/flux-overview.md`

## Workload index

Every workload by name, so you can map a name in a prompt to a directory: `apps/base/<category>/<name>` (overlay: `apps/prod-gen3/<category>/<name>`) and `infra/base/<category>/<name>` (overlay: `infra/prod-gen3/...`). One-line summaries are in the README "Workloads" tables.

**Apps**
- `ci-registry/`: arc (CI runners for `home-web-apps`, plus build caches), harbor (private registry + Docker Hub mirror that CI and image automation depend on), harbor-cleanup, regcred-flux
- `public-sites/`: blog, diagram-maker, fui-components, home-hud, umami (public, so NetworkPolicy + image automation required)
- `media/`: media (sonarr, radarr, prowlarr, qbittorrent, gluetun VPN, byparr, and the arr and qbittorrent MCP servers) and plex
- `host-proxies/`: asustor, haproxy, home-assistant, proxmox (routes/services in front of hosts that are not in k8s)
- `dev-ai/`: coder, openclaw, mcp-grafana
- `platform/`: dashy (dashboard/homepage), flux-gitops (Flux web UI + MCP), podinfo (routing/cert smoke test)

**Infra** (CRDs for these come from `crds/base/`: istio, gateway-api, cert-manager-1.20, flux-operator, sealed-secrets, onepassword, kube-prometheus-stack, external-dns, longhorn)
- `core/`: flux-operator, metrics-server, priorityclass
- `networking/`: istio, external-dns, cert-manager, pihole
- `secrets/`: onepassword, sealed-secrets
- `storage/`: longhorn, nas-storage
- `observability/`: kube-prometheus-stack

## Working with the cluster

- Use `kubectl` directly (no ssh); `kubectx` switches contexts. Prefer the `flux` CLI or the flux MCP over annotating resources.
- MCP servers (`.mcp.json`): grafana, flux, arr, qbittorrent.
- Kubeconfig comes from `scripts/get-kubeconfig.sh` in the workspace repo (see the workspace `CLAUDE.md`).
- `kubectl kustomize` needs `--load-restrictor LoadRestrictionsNone` for the overlays.

## Scripts

Prefer these over hand-rolled commands (details and the full manifest: `scripts/CLAUDE.md`, keep it updated when scripts change):

- Re-seal 1Password Connect credentials: `scripts/op-connect-secret.sh` (procedure in `docs/ai-reference/secrets.md`).
- Grafana: `export GRAFANA_TOKEN_PROD=$(./scripts/get-grafana-api-key.sh)`; `./scripts/dev-grafana-dashboards.py` to hot-push dashboards.
- Longhorn restore into a named PVC: `scripts/longhorn-restore.sh` (dry-run by default; see `docs/ai-reference/gen3-data-move.md`).
- When you add or change a script, update `scripts/CLAUDE.md` in the same commit; the pre-commit hook (`scripts/check-manifest.sh`) checks the manifest.

## Agents and skills

Agents (`.claude/agents/`): `arc-debug`, `flux-recover`, `istio-debug`, `longhorn-ops`, `media-debug`, `secrets-ops`.
Skills (`.claude/skills/`): `flux-app-add` (add an app), `helm-values` (real chart defaults), `arc-optimize`, `grafana-analyze`,
`dump` (session summaries), and the media/Coder ones (`radarr-grab`, `sonarr-grab`, `media-source-debug`, `plex-collection`, `coder-*`).

## Documentation map

- `docs/developer-guides/`: how-tos for working in this repo. Conventions for apps, NetworkPolicy and image automation: `workload-conventions.md`. Adding a cluster: `new-cluster.md`.
- `docs/secret-rotations/`: one doc per secret, covering where it is used and how to rotate it.
- `docs/reference/`: human-oriented background (1Password setup, chart links, secret strategy).
- `docs/ai-reference/`: procedures and gotchas for AI use. Read before acting: `gen3-manual-steps.md` (adding a node or rebuilding gen3), `gen3-data-move.md` (moving app data between clusters), `secrets.md` (anything secret-related).
  Also `infra.md` (clusters, DNS patterns, Flux layering, Longhorn backup targets), `op-connect-api-access.md` (query the 1Password vault API).
- `docs/plans/`: implementation plans for migrations and features (new plans go here). The gen2→gen3 migration plan holds the loose-ends register.
- `docs/incidents/`: post-mortems. `docs/claude-sessions/`: session dumps from `/dump`.
- `docs/archive/`: gen1/gen2 overview; the code lives only at git tags (`archive-gen1-homelab`, `archive-gen2-prod`, `archive-gen2-nonprod`). It is history: don't restore it unless asked.
- `.cursor/k8s-namespaces.md`: namespace inventory.

## Rules of the road

- Adding, removing or renaming a workload: update the README "Workloads" tables in the same change, and use an existing category directory where one fits.
- Public apps (any Cloudflare HTTPRoute) need a NetworkPolicy and image update automation; details in `workload-conventions.md`.
- Adding, changing or removing a script: update the manifest in `scripts/CLAUDE.md` in the same commit.
- The `ImageUpdateAutomation` is suspended in the cluster on purpose. Do not unsuspend it.
