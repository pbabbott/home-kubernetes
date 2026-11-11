# home-kubernetes
A gitops-based approach for all my kubernetes charts, manifests, and helm deployments. Flux for Gitops, 1password for secrets, and a variety of shell scripts to support a myriad of operators and applications.

- [home-kubernetes](#home-kubernetes)
- [Contribution](#contribution)
  - [Getting Started](#getting-started)
  - [Developer Guides](#developer-guides)
  - [Scripts](#scripts)
  - [Secret Rotations](#secret-rotations)
  - [Reference](#reference)
    - [External Docs](#external-docs)
- [Workloads](#workloads)
  - [Flux layout](#flux-layout)
  - [Infrastructure](#infrastructure)
  - [Apps](#apps)
- [Archive](#archive)

# Contribution 

This project is meant to run in a `devcontainer` on a VM in my homelab. That is, this codebase targets many specific aspects of my home infra and its not really meant to run anywhere else, though many of its parts could be made to be re-usable or serve as inspiration for others.

## Getting Started

Follow this guide to make sure you're ready to start work on this project: [Dev Environment - Main](./docs/developer-guides/dev-env-main.md)

## Developer Guides

These are common activities one might take while working on this repository.

- [Bootstrap the cluster with Flux](./docs/developer-guides/flux-bootstrap.md) - This is a one-time activity unless the cluster needs to be rebuilt or more flux features need to be added.
- [Login to 1Password](./docs/developer-guides/login-to-one-password.md) - Depending on the state of the connect server, here are some tips for authenticating with 1Password.
- [SealedSecrets - Create Manifest](./docs/developer-guides/sealed-secrets-create-manifest.md) - Here is how you can create a SealedSecret for use within the cluster
- [Cluster Access](./docs/developer-guides/cluster-access.md) - Once the cluster has been provisioned, this is how you can can set a secret in 1Password so the home-web-apps can access.
- [New Cluster Checklist](./docs/developer-guides/new-cluster.md) - Steps to stand up a new cluster with Flux Operator (CRDs, infra, apps overlays).
- [Flux Overview](./docs/developer-guides/flux-overview.md) - Handy Flux commands and debugging tips.
- [Dev Containers over SSH](./docs/developer-guides/devcontainer-ssh-gitconfig.md) - Fix for `.gitconfig` / authority resolution problems when using Dev Containers on a Remote-SSH host.
- [Workload Conventions](./docs/developer-guides/workload-conventions.md) - File naming, HelmRelease apiVersion, and the NetworkPolicy and image-automation rules for public apps.

## Scripts

Helpers live in `scripts/`; run them from the repo root. What each does, with the full manifest: [scripts/CLAUDE.md](./scripts/CLAUDE.md). Common workflows:

- **Re-seal 1Password Connect credentials:** `./scripts/op-connect-secret.sh` (procedure: [AI reference - Secrets](./docs/ai-reference/secrets.md)).
- **Grafana token:** `export GRAFANA_TOKEN_PROD=$(./scripts/get-grafana-api-key.sh)`. **Iterate on dashboards:** `./scripts/dev-grafana-dashboards.py`.
- **Restore a Longhorn backup into a PVC:** `./scripts/longhorn-restore.sh` (dry-run by default).

Run `pre-commit install` once per clone; the hook fails if a script has no row in the manifest.

## Secret Rotations

Secrets should be rotated and it can become a bit tedious to do so. These documents make it easier to discern each secret's usage and how it should be rotated.

- [Cloudflare Token](./docs/secret-rotations/cloudflare-token.md)
- [Private Internet Access Credentials](./docs/secret-rotations/pia-credentials.md)
- [QbitTorrent Credentials](./docs/secret-rotations/qbittorrent.md)
- [Registry Credentials](./docs/secret-rotations/regcred.md)
- [Harbor Administration](./docs/secret-rotations/harbor-admin.md)
- [Longhorn NAS Backup Credentials](./docs/secret-rotations/longhorn-nas.md)
- [GitHub PAT](./docs/secret-rotations/gh-pat.md)


## Reference
- [1Password Integration Overview](./docs/reference/1password-integration-overview.md) - Here is how 1Password is setup and steps to get it working in the case of cluster rebuild.
- [Chart Documentation](./docs/reference/chart-documentation.md) - A bunch of links to handy documentation websites and a few commands.
- [Secret Management Strategy](./docs/reference/secret-management-strategy.md) - Here is how to choose when to use 1Password or SealedSecrets.

### External Docs
- [Grafana Operator Documentation](https://grafana.github.io/grafana-operator/docs/)
- [Kustomize Documentation Reference](https://kubectl.docs.kubernetes.io/references/kustomize/)

# Workloads

What runs on the live cluster, `prod-gen3` (k3s on `hogwarts`, plus controller-3 and worker-3 on `chimaera`). Hosts: `home-playbooks/docs/HOSTS.md`.

## Flux layout
Four numbered Kustomizations in `clusters/prod-gen3/`, each depending on the previous one: `00-crds-ks` (`crds/prod-gen3`), `01-infra-ks` (`infra/prod-gen3`), `02-apps-ks` (`apps/prod-gen3`) and `03-flux-gitops-ks` (the Flux web UI and MCP server). Overlays are thin: each `apps/prod-gen3/<category>/<app>/kustomization.yaml` references `apps/base/<category>/<app>` and patches hostnames, labels or sizing. Ingress is Istio ambient + Gateway API behind the HAProxy LXC. DNS is two external-dns instances (Cloudflare for `*.abbottland.io`, Pi-hole for `*.local.abbottland.io`). Secrets come from the 1Password Connect operator (`OnePasswordItem`), with SealedSecrets only to bootstrap it.

## Infrastructure
Lives in `infra/<category>/<component>` under `infra/base` and the `infra/prod-gen3` overlay. The Category column maps to the directory name (e.g. `CI & registry` is `ci-registry`).

| Category | Component | Summary |
| --- | --- | --- |
| Core | crds | Everything with CRDs is installed first from `crds/base/*`: Istio, Gateway API, cert-manager, flux-operator, sealed-secrets, onepassword, kube-prometheus-stack, external-dns, longhorn. |
| Core | metrics-server, priorityclass | Shared base: resource metrics API and cluster PriorityClasses. |
| Networking | cert-manager | Let's Encrypt issuers (Cloudflare DNS-01) issuing the wildcard gateway certs. |
| Networking | external-dns | Cloudflare and Pi-hole external-dns instances reading HTTPRoutes by label. |
| Networking | istio | Istio ambient mesh (istiod, cni, ztunnel) plus the internal and public Gateways. |
| Networking | pihole | Proxy route to the Pi-hole admin UI on `bananapi`. Kept in infra because external-dns depends on it. |
| Observability | kube-prometheus-stack | Prometheus, Grafana and Alertmanager with gitops-managed dashboards, plus scrape configs for physical hosts. |
| Secrets | onepassword | 1Password Connect + operator; `op-credentials` sealed per cluster. |
| Secrets | sealed-secrets | Controller used to bootstrap the 1Password Connect credentials. |
| Storage | longhorn | Replicated block storage with recurring backups to the NAS NFS target. |
| Storage | nas-storage | NFS subdir provisioner StorageClass (`nas-storage`) on the Asustor NAS. |

## Apps
Lives in `apps/<category>/<app>` under `apps/base` and the `apps/prod-gen3` overlay. The Category column maps to the directory name (e.g. `CI & registry` is `ci-registry`).

| Category | App | Summary |
| --- | --- | --- |
| CI & registry | arc | Actions Runner Controller scale sets (amd64 and dind) for home-web-apps CI, plus actions-cache and turborepo remote cache servers. |
| CI & registry | harbor | Harbor registry (Helm) with NAS-backed registry storage; Docker Hub proxy mirror for CI. |
| CI & registry | harbor-cleanup | Custom service that cleans up Harbor; see `docs/plans/2026-06-01-harbor-cleanup.md`. |
| CI & registry | regcred-flux | OnePasswordItem providing the registry pull credential Flux uses for image automation. |
| Dev & AI | coder | Coder dev-workspace platform (Helm) with NAS Postgres and a workspaces namespace. |
| Dev & AI | mcp-grafana | Grafana MCP server exposed internally for AI agents. |
| Dev & AI | openclaw | OpenClaw agent platform with config map, PVC and NetworkPolicy. |
| Host proxies | asustor | Service + EndpointSlice + routes proxying the NAS admin UI; DNSEndpoint for the NAS. |
| Host proxies | haproxy | Proxy to the HAProxy stats page plus a Prometheus scrape config. |
| Host proxies | home-assistant | Public route (via Cloudflare) to the Home Assistant host. |
| Host proxies | proxmox | Proxy route to the Proxmox UI with an Istio DestinationRule. |
| Media | media | sonarr, radarr, prowlarr, qBittorrent and gluetun (VPN), with config PVCs on Longhorn and media on NFS. |
| Media | plex | Service + EndpointSlice proxying Plex on the NAS. |
| Platform | dashy | Dashy dashboard as a local Helm chart with per-cluster values. |
| Platform | flux-gitops | Flux web UI route and Flux Operator MCP server, applied by `03-flux-gitops-ks`. |
| Platform | podinfo | Test app used to prove public/internal routing and certs. |
| Public sites | blog | Public blog (apex `abbottland.io`), image automation, NetworkPolicy. |
| Public sites | diagram-maker | Public diagram-maker app with NetworkPolicy and image automation. |
| Public sites | fui-components | Public component-library site with NetworkPolicy and image automation. |
| Public sites | home-hud | home-hud dashboard with video-api/-worker, backup worker, and `homelab-api`, all with image automation and ServiceMonitors. |
| Public sites | umami | Self-hosted analytics (public script, internal admin) on NAS Postgres. |

> **Keep this section current.** Add, remove or rename a row here whenever a workload is added to, removed from or renamed in `apps/prod-gen3` or `infra/prod-gen3` (or the `crds/prod-gen3` list). Rows are sorted by Category, then name.

# Archive

Only the gen 3 cluster (`prod-gen3`) lives in this repo. The earlier clusters' code was removed and is preserved at git tags (all at `c32de0e`). Each overview page lists the apps and infrastructure the cluster ran, its Flux layout and technology choices, and how to browse the old code.

- [Archive index and how to browse the tags](./docs/archive/README.md)
- [Gen 1 `homelab`](./docs/archive/gen1-homelab.md) - tag `archive-gen1-homelab`
- [Gen 2 `prod-gen2`](./docs/archive/gen2-prod.md) - tag `archive-gen2-prod`
- [Gen 2 `non-prod-gen2`](./docs/archive/gen2-nonprod.md) - tag `archive-gen2-nonprod`
